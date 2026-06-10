const std = @import("std");
const zm = @import("zig-maturin");
const conversion = @import("conversion.zig");
const errors = @import("errors.zig");

pub fn paramTypesTupleDirect(comptime params: []const std.builtin.Type.Fn.Param) type {
    if (params.len == 0) return struct {};
    comptime var types: [params.len]type = undefined;
    inline for (params, 0..) |p, i| {
        types[i] = p.type.?;
    }
    return std.meta.Tuple(&types);
}

fn setConversionError(err: conversion.ConversionError) void {
    switch (err) {
        error.PythonTypeError => zm.PyErr_SetString(zm.PyExc_TypeError, "type conversion error"),
        error.PythonValueError => zm.PyErr_SetString(zm.PyExc_ValueError, "value conversion error"),
        error.Overflow => zm.PyErr_SetString(zm.PyExc_OverflowError, "integer overflow"),
        error.NotImplemented => zm.PyErr_SetString(zm.PyExc_NotImplementedError, "conversion not implemented"),
    }
}

fn returnToPyObjectValue(value: anytype) ?*zm.PyObject {
    const T = @TypeOf(value);
    if (T == void) {
        return zm.Py_NewRef(zm.Py_None);
    }
    return conversion.toPyObject(value) catch |err| {
        setConversionError(err);
        return null;
    };
}

fn wrapFnInner(comptime func: anytype, comptime fn_info: std.builtin.Type.Fn, self: ?*zm.PyObject, args_obj: ?*zm.PyObject) callconv(.c) ?*zm.PyObject {
    const params = fn_info.params;
    const return_type = fn_info.return_type;

    if (args_obj) |args| {
        const expected = @as(isize, @intCast(params.len));
        const actual = zm.PyTuple_Size(args);
        if (actual != expected) {
            var buf: [128]u8 = undefined;
            const msg = std.fmt.bufPrint(&buf, "expected {d} arguments, got {d}", .{ expected, actual }) catch "argument count mismatch";
            const len = @min(msg.len, buf.len - 1);
            buf[len] = 0;
            zm.PyErr_SetString(zm.PyExc_TypeError, @as([*:0]const u8, @ptrCast(&buf)));
            return null;
        }

        const TupleType = paramTypesTupleDirect(params);
        var call_args: TupleType = undefined;

        inline for (params, 0..) |param, i| {
            const T = param.type.?;
            const arg_obj = zm.PyTuple_GetItem(args, @as(isize, @intCast(i)));
            call_args[i] = conversion.fromPyObject(T, arg_obj) catch |err| {
                setConversionError(err);
                return null;
            };
        }

        if (return_type) |ret| {
            if (ret == void) {
                @call(.auto, func, call_args);
                return zm.Py_NewRef(zm.Py_None);
            }
            const ret_info = @typeInfo(ret);
            if (ret_info == .error_union) {
                const result = @call(.auto, func, call_args) catch |err| {
                    errors.setPyException(err);
                    return null;
                };
                return returnToPyObjectValue(result);
            }
            const result = @call(.auto, func, call_args);
            return returnToPyObjectValue(result);
        } else {
            @call(.auto, func, call_args);
            return zm.Py_NewRef(zm.Py_None);
        }
    } else {
        zm.PyErr_SetString(zm.PyExc_TypeError, "no arguments tuple");
        return null;
    }
}

pub fn wrap(comptime func: anytype, comptime name: [:0]const u8, comptime doc: [:0]const u8) zm.PyMethodDef {
    const FnType = @TypeOf(func);
    const fn_info = @typeInfo(FnType).fn;
    const num_params = fn_info.params.len;
    const flags: c_int = if (num_params == 0) zm.METH_NOARGS else zm.METH_VARARGS;

    const Wrapper = struct {
        pub fn trampoline(self: ?*zm.PyObject, args_obj: ?*zm.PyObject) callconv(.c) ?*zm.PyObject {
            return wrapFnInner(func, fn_info, self, args_obj);
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

pub fn pyFn(comptime func: anytype) zm.PyMethodDef {
    @compileError("Use pyFnNamed(\"name\", func) — can't infer function name from a value");
}

pub fn pyFnNamed(comptime name: [:0]const u8, comptime func: anytype) zm.PyMethodDef {
    return wrap(func, name, "");
}
