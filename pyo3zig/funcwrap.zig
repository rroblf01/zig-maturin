const std = @import("std");
const zm = @import("zig-maturin");
const conversion = @import("conversion.zig");
const errors = @import("errors.zig");

pub fn paramTypesTupleDirect(comptime params: []const std.builtin.Type.Fn.Param) type {
    if (params.len == 0) return @TypeOf(.{});
    comptime var types: [params.len]type = undefined;
    inline for (params, 0..) |p, i| {
        types[i] = p.type.?;
    }
    return std.meta.Tuple(&types);
}

pub fn setConversionError(err: conversion.ConversionError) void {
    // Conversion may already have set a precise message (e.g. "expected int,
    // got str"); don't overwrite it with the generic fallback.
    if (zm.PyErr_Occurred() != null) return;
    switch (err) {
        error.PythonTypeError => zm.PyErr_SetString(zm.PyExc_TypeError(), "type conversion error"),
        error.PythonValueError => zm.PyErr_SetString(zm.PyExc_ValueError(), "value conversion error"),
        error.Overflow => zm.PyErr_SetString(zm.PyExc_OverflowError(), "integer overflow"),
        error.MemoryError => zm.PyErr_SetString(zm.PyExc_MemoryError(), "memory allocation failed"),
        error.NotImplemented => zm.PyErr_SetString(zm.PyExc_NotImplementedError(), "conversion not implemented"),
    }
}

pub fn returnToPyObjectValue(value: anytype) ?*zm.PyObject {
    const T = @TypeOf(value);
    if (T == void) {
        return zm.Py_NewRef(zm.Py_None());
    }
    return conversion.toPyObject(value) catch |err| {
        setConversionError(err);
        return null;
    };
}

fn wrapFnInner(comptime func: anytype, comptime fn_info: std.builtin.Type.Fn, _: ?*zm.PyObject, args_obj: ?*zm.PyObject) ?*zm.PyObject {
    const params = fn_info.params;
    const return_type = fn_info.return_type;

    if (args_obj) |args| {
        const expected = @as(isize, @intCast(params.len));
        const actual = zm.PyTuple_Size(args);
        if (actual != expected) {
            var buf: [128]u8 = std.mem.zeroes([128]u8);
            const msg = std.fmt.bufPrint(&buf, "expected {d} arguments, got {d}", .{ expected, actual }) catch "argument count mismatch";
            const end = @min(msg.len, buf.len - 1);
            buf[end] = 0;
            zm.PyErr_SetString(zm.PyExc_TypeError(), @ptrCast(&buf));
            return null;
        }

        const TupleType = paramTypesTupleDirect(params);
        var call_args: TupleType = undefined;

        // Per-call arena: backs container-argument conversions and is freed
        // when the trampoline returns (after the result has been converted).
        var arena = std.heap.ArenaAllocator.init(std.heap.c_allocator);
        defer arena.deinit();
        const alloc = arena.allocator();

        inline for (params, 0..) |param, i| {
            const T = param.type.?;
            const arg_obj = zm.PyTuple_GetItem(args, @as(isize, @intCast(i)));
            call_args[i] = conversion.fromPyObject(T, arg_obj, alloc) catch |err| {
                setConversionError(err);
                return null;
            };
        }

        if (return_type) |ret| {
            if (ret == void) {
                @call(.auto, func, call_args);
                return zm.Py_NewRef(zm.Py_None());
            }
            const ret_info = @typeInfo(ret);
            if (ret_info == .error_union) {
                const result = @call(.auto, func, call_args) catch |err| {
                    errors.setPyExceptionIfNeeded(err);
                    return null;
                };
                return returnToPyObjectValue(result);
            }
            const result = @call(.auto, func, call_args);
            return returnToPyObjectValue(result);
        } else {
            @call(.auto, func, call_args);
            return zm.Py_NewRef(zm.Py_None());
        }
    } else {
        zm.PyErr_SetString(zm.PyExc_TypeError(), "no arguments tuple");
        return null;
    }
}

pub fn wrap(comptime func: anytype, comptime name: [:0]const u8, comptime doc: [:0]const u8) zm.PyMethodDef {
    const FnType = @TypeOf(func);
    const fn_info = @typeInfo(FnType).@"fn";
    const flags: c_int = zm.METH_VARARGS;

    const Wrapper = struct {
        const Ctx = struct { self: ?*zm.PyObject, args: ?*zm.PyObject };
        fn thunk(p: ?*anyopaque) callconv(.c) ?*zm.PyObject {
            const c = @as(*Ctx, @ptrCast(@alignCast(p)));
            return wrapFnInner(func, fn_info, c.self, c.args);
        }
        // Run the body under the panic safety net (see pyo3zig_capi.c).
        pub fn trampoline(self: ?*zm.PyObject, args_obj: ?*zm.PyObject) callconv(.c) ?*zm.PyObject {
            var ctx = Ctx{ .self = self, .args = args_obj };
            return zm.pz_guard(&thunk, &ctx);
        }
    };

    return zm.PyMethodDef{
        .ml_name = name,
        .ml_meth = &Wrapper.trampoline,
        .ml_flags = flags,
        .ml_doc = doc,
    };
}

pub fn wrapNamed(comptime name: [:0]const u8, comptime func: anytype) zm.PyMethodDef {
    return wrap(func, name, "");
}

pub fn pyFn(comptime _: anytype) zm.PyMethodDef {
    @compileError("Use pyFnNamed(\"name\", func) — can't infer function name from a value");
}

pub fn pyFnNamed(comptime name: [:0]const u8, comptime func: anytype) zm.PyMethodDef {
    return wrap(func, name, "");
}

/// Register a function with keyword-argument and default support. Zig
/// reflection has no parameter names, so they are supplied explicitly:
///
///     pz.pyFnKw("greet", greet, .{
///         .args = &.{ "name", "excited" },
///         .defaults = .{ .excited = false },   // optional, by name
///     });
///
/// Callers may then use positional or keyword arguments; omitted parameters
/// fall back to their default (a TypeError is raised if none is set).
pub fn pyFnKw(comptime name: [:0]const u8, comptime func: anytype, comptime spec: anytype) zm.PyMethodDef {
    const FnType = @TypeOf(func);
    const fn_info = @typeInfo(FnType).@"fn";
    const params = fn_info.params;
    if (spec.args.len != params.len) {
        @compileError("pyFnKw: .args length must match the function's parameter count");
    }

    const Wrapper = struct {
        const Ctx = struct { args: ?*zm.PyObject, kwargs: ?*zm.PyObject };

        fn inner(args_obj: ?*zm.PyObject, kwargs_obj: ?*zm.PyObject) ?*zm.PyObject {
            var arena = std.heap.ArenaAllocator.init(std.heap.c_allocator);
            defer arena.deinit();
            const call_args = bindArgs(params, spec, args_obj, kwargs_obj, arena.allocator()) orelse return null;
            return callAndConvert(func, fn_info, call_args);
        }

        fn thunk(p: ?*anyopaque) callconv(.c) ?*zm.PyObject {
            const c = @as(*Ctx, @ptrCast(@alignCast(p)));
            return inner(c.args, c.kwargs);
        }

        pub fn trampoline(self: ?*zm.PyObject, args_obj: ?*zm.PyObject, kwargs_obj: ?*zm.PyObject) callconv(.c) ?*zm.PyObject {
            _ = self;
            var ctx = Ctx{ .args = args_obj, .kwargs = kwargs_obj };
            return zm.pz_guard(&thunk, &ctx);
        }
    };

    return zm.PyMethodDef{
        .ml_name = name,
        .ml_meth = @ptrCast(&Wrapper.trampoline),
        .ml_flags = zm.METH_VARARGS | zm.METH_KEYWORDS,
        .ml_doc = null,
    };
}

/// Bind Python positional + keyword arguments to a Zig call-args tuple, using
/// the explicit names in `spec.args` and optional `spec.defaults`. Returns null
/// with a Python exception set on error. Shared by pyFnKw, wrapMethodKw, and
/// keyword __init__.
pub fn bindArgs(
    comptime params: []const std.builtin.Type.Fn.Param,
    comptime spec: anytype,
    args_obj: ?*zm.PyObject,
    kwargs_obj: ?*zm.PyObject,
    alloc: std.mem.Allocator,
) ?paramTypesTupleDirect(params) {
    const arg_names = spec.args;
    const has_defaults = @hasField(@TypeOf(spec), "defaults");
    const npos: isize = if (args_obj) |a| zm.PyTuple_Size(a) else 0;
    if (npos > @as(isize, @intCast(params.len))) {
        zm.PyErr_SetString(zm.PyExc_TypeError(), "too many positional arguments");
        return null;
    }

    var call_args: paramTypesTupleDirect(params) = undefined;
    inline for (params, 0..) |param, i| {
        const ParamT = param.type.?;
        const pname = @as([*:0]const u8, @ptrCast(arg_names[i].ptr));
        var arg_obj: ?*zm.PyObject = null;
        if (i < npos) {
            arg_obj = zm.PyTuple_GetItem(args_obj, @as(isize, @intCast(i)));
        } else if (kwargs_obj != null) {
            arg_obj = zm.PyDict_GetItemString(kwargs_obj, pname);
        }

        if (arg_obj) |o| {
            call_args[i] = conversion.fromPyObject(ParamT, o, alloc) catch |err| {
                setConversionError(err);
                return null;
            };
        } else if (comptime has_defaults and @hasField(@TypeOf(spec.defaults), arg_names[i])) {
            call_args[i] = @field(spec.defaults, arg_names[i]);
        } else {
            var buf: [128]u8 = std.mem.zeroes([128]u8);
            const msg = std.fmt.bufPrint(&buf, "missing required argument '{s}'", .{arg_names[i]}) catch "missing required argument";
            buf[@min(msg.len, buf.len - 1)] = 0;
            zm.PyErr_SetString(zm.PyExc_TypeError(), @ptrCast(&buf));
            return null;
        }
    }
    return call_args;
}

pub fn callAndConvert(comptime func: anytype, comptime fn_info: std.builtin.Type.Fn, call_args: anytype) ?*zm.PyObject {
    const return_type = fn_info.return_type;
    if (return_type) |ret| {
        if (ret == void) {
            @call(.auto, func, call_args);
            return zm.Py_NewRef(zm.Py_None());
        }
        if (@typeInfo(ret) == .error_union) {
            const result = @call(.auto, func, call_args) catch |err| {
                errors.setPyExceptionIfNeeded(err);
                return null;
            };
            return returnToPyObjectValue(result);
        }
        return returnToPyObjectValue(@call(.auto, func, call_args));
    }
    @call(.auto, func, call_args);
    return zm.Py_NewRef(zm.Py_None());
}


