const std = @import("std");
const zm = @import("zig-maturin");
const pycell = @import("pycell.zig");
const funcwrap = @import("funcwrap.zig");
const conversion = @import("conversion.zig");
const errors = @import("errors.zig");

fn buildTypeName(comptime T: type) [*:0]const u8 {
    const full = @typeName(T);
    const dot = std.mem.lastIndexOfScalar(u8, full, '.') orelse 0;
    const short = if (dot > 0) full[dot+1..] else full;
    return @as([*:0]const u8, @ptrCast(short.ptr));
}

fn callFuncReturningPyObject(comptime func: anytype, comptime fn_info: std.builtin.Type.Fn, args: anytype) ?*zm.PyObject {
    if (fn_info.return_type) |ret| {
        if (ret == void) {
            @call(.auto, func, args);
            return zm.Py_NewRef(zm.Py_None());
        }
        const ret_info = @typeInfo(ret);
        if (ret_info == .error_union) {
            const result = @call(.auto, func, args) catch |err| {
                errors.setPyExceptionIfNeeded(err);
                return null;
            };
            return funcwrap.returnToPyObjectValue(result);
        }
        const result = @call(.auto, func, args);
        return funcwrap.returnToPyObjectValue(result);
    } else {
        @call(.auto, func, args);
        return zm.Py_NewRef(zm.Py_None());
    }
}

/// True if the class stores any Python object reference (`?*PyObject`) field.
/// Such classes participate in cyclic garbage collection (Py_TPFLAGS_HAVE_GC):
/// the framework owns one reference per non-null field, visits them in
/// tp_traverse, and clears them in tp_clear/dealloc.
fn structHasPyObjectField(comptime T: type) bool {
    inline for (std.meta.fields(T)) |f| {
        if (f.type == ?*zm.PyObject) return true;
    }
    return false;
}

/// Allocate a new instance of class `T` belonging to type object `cls`.
/// PyType_GenericAlloc zero-inits the object, sets the refcount, increfs the
/// (heap) type, sizes the allocation by `cls`'s own basicsize (so Python
/// subclasses get enough room), and GC-tracks it when the type has HAVE_GC.
fn createInstance(comptime T: type, cls: ?*zm.PyObject) ?*zm.PyObject {
    _ = T;
    return zm.PyType_GenericAlloc(cls, 0);
}

/// Free an instance allocated by `createInstance`. GC types are untracked and
/// freed via the GC allocator; plain types via PyObject_Free.
fn freeInstanceMem(comptime T: type, obj: ?*zm.PyObject) void {
    if (comptime structHasPyObjectField(T)) {
        zm.PyObject_GC_UnTrack(@as(?*anyopaque, @ptrCast(obj)));
        zm.PyObject_GC_Del(@as(?*anyopaque, @ptrCast(obj)));
    } else {
        zm.PyObject_Free(@as(?*anyopaque, @ptrCast(obj)));
    }
}

/// Increment the framework-owned reference for each non-null `?*PyObject` field
/// after the struct has been populated (init / classmethod / operator result).
fn ownFields(comptime T: type, obj: ?*zm.PyObject) void {
    const ptr = pycell.PyCell(T).ptrFromObj(obj);
    inline for (std.meta.fields(T)) |f| {
        if (f.type == ?*zm.PyObject) zm.Py_XINCREF(@field(ptr, f.name));
    }
}

/// Drop the framework-owned references and null the fields (tp_clear / dealloc).
fn releaseFields(comptime T: type, obj: ?*zm.PyObject) void {
    const ptr = pycell.PyCell(T).ptrFromObj(obj);
    inline for (std.meta.fields(T)) |f| {
        if (f.type == ?*zm.PyObject) {
            const tmp = @field(ptr, f.name);
            @field(ptr, f.name) = null;
            zm.Py_XDECREF(tmp);
        }
    }
}

pub fn wrapMethodNamed(comptime T: type, comptime name: [:0]const u8, comptime func: anytype) zm.PyMethodDef {
    const FnType = @TypeOf(func);
    const fn_info = @typeInfo(FnType).@"fn";
    const func_params = fn_info.params;
    const Cell = pycell.PyCell(T);

    const Wrapper = struct {
        const Ctx = struct { self: ?*zm.PyObject, args: ?*zm.PyObject };

        fn thunk(p: ?*anyopaque) callconv(.c) ?*zm.PyObject {
            const c = @as(*Ctx, @ptrCast(@alignCast(p)));
            return inner(c.self, c.args);
        }

        pub fn trampoline(self_obj: ?*zm.PyObject, args_obj: ?*zm.PyObject) callconv(.c) ?*zm.PyObject {
            var ctx = Ctx{ .self = self_obj, .args = args_obj };
            return zm.pz_guard(&thunk, &ctx);
        }

        fn inner(self_obj: ?*zm.PyObject, args_obj: ?*zm.PyObject) ?*zm.PyObject {
            const return_type = fn_info.return_type;

            const self_ptr = Cell.ptrFromObj(self_obj);
            const method_params = func_params[1..];

            if (args_obj) |args| {
                const expected = @as(isize, @intCast(method_params.len));
                const actual = zm.PyTuple_Size(args);
                if (actual != expected) {
                    var buf: [128]u8 = std.mem.zeroes([128]u8);
                    const msg = std.fmt.bufPrint(&buf, "expected {d} arguments, got {d}", .{ expected, actual }) catch "argument count mismatch";
                    const end = @min(msg.len, buf.len - 1);
                    buf[end] = 0;
                    zm.PyErr_SetString(zm.PyExc_TypeError(), @ptrCast(&buf));
                    return null;
                }

                const TupleType = funcwrap.paramTypesTupleDirect(method_params);
                var call_args: TupleType = undefined;

                var arena = std.heap.ArenaAllocator.init(std.heap.c_allocator);
                defer arena.deinit();
                const alloc = arena.allocator();

                inline for (method_params, 0..) |param, i| {
                    const ParamT = param.type.?;
                    const arg_obj = zm.PyTuple_GetItem(args, @as(isize, @intCast(i)));
                    call_args[i] = conversion.fromPyObject(ParamT, arg_obj, alloc) catch |err| {
                        funcwrap.setConversionError(err);
                        return null;
                    };
                }

                if (return_type) |ret| {
                    if (ret == void) {
                        @call(.auto, func, .{self_ptr} ++ call_args);
                        return zm.Py_NewRef(zm.Py_None());
                    }
                    const ret_info = @typeInfo(ret);
                    if (ret_info == .error_union) {
                        const result = @call(.auto, func, .{self_ptr} ++ call_args) catch |err| {
                            errors.setPyExceptionIfNeeded(err);
                            return null;
                        };
                        return funcwrap.returnToPyObjectValue(result);
                    }
                    const result = @call(.auto, func, .{self_ptr} ++ call_args);
                    return funcwrap.returnToPyObjectValue(result);
                } else {
                    @call(.auto, func, .{self_ptr} ++ call_args);
                    return zm.Py_NewRef(zm.Py_None());
                }
            } else {
                zm.PyErr_SetString(zm.PyExc_TypeError(), "no arguments tuple");
                return null;
            }
        }
    };

    return zm.PyMethodDef{
        .ml_name = @as(?[*:0]const u8, @ptrCast(name.ptr)),
        .ml_meth = &Wrapper.trampoline,
        .ml_flags = zm.METH_VARARGS,
        .ml_doc = null,
    };
}

/// Like wrapMethodNamed but with keyword-argument and default support.
/// `spec.args` names the method's parameters (excluding `self`).
pub fn wrapMethodKw(comptime T: type, comptime name: [:0]const u8, comptime func: anytype, comptime spec: anytype) zm.PyMethodDef {
    const fn_info = @typeInfo(@TypeOf(func)).@"fn";
    const method_params = fn_info.params[1..];
    if (spec.args.len != method_params.len) {
        @compileError("wrapMethodKw: .args length must match the method's parameter count (excluding self)");
    }
    const Cell = pycell.PyCell(T);

    const Wrapper = struct {
        const Ctx = struct { self: ?*zm.PyObject, args: ?*zm.PyObject, kwargs: ?*zm.PyObject };

        fn inner(self_obj: ?*zm.PyObject, args_obj: ?*zm.PyObject, kwargs_obj: ?*zm.PyObject) ?*zm.PyObject {
            const self_ptr = Cell.ptrFromObj(self_obj);
            var arena = std.heap.ArenaAllocator.init(std.heap.c_allocator);
            defer arena.deinit();
            const ca = funcwrap.bindArgs(method_params, spec, args_obj, kwargs_obj, arena.allocator()) orelse return null;
            return funcwrap.callAndConvert(func, fn_info, .{self_ptr} ++ ca);
        }

        fn thunk(p: ?*anyopaque) callconv(.c) ?*zm.PyObject {
            const c = @as(*Ctx, @ptrCast(@alignCast(p)));
            return inner(c.self, c.args, c.kwargs);
        }

        pub fn trampoline(self_obj: ?*zm.PyObject, args_obj: ?*zm.PyObject, kwargs_obj: ?*zm.PyObject) callconv(.c) ?*zm.PyObject {
            var ctx = Ctx{ .self = self_obj, .args = args_obj, .kwargs = kwargs_obj };
            return zm.pz_guard(&thunk, &ctx);
        }
    };

    return zm.PyMethodDef{
        .ml_name = @as(?[*:0]const u8, @ptrCast(name.ptr)),
        .ml_meth = @ptrCast(&Wrapper.trampoline),
        .ml_flags = zm.METH_VARARGS | zm.METH_KEYWORDS,
        .ml_doc = null,
    };
}

const METH_CLASS: c_int = 0x10;
const METH_STATIC: c_int = 0x20;

/// A static method (no `self`, no instance) on a class. Register it in the
/// class's `.methods` list.
pub fn staticMethod(comptime name: [:0]const u8, comptime func: anytype) zm.PyMethodDef {
    var def = funcwrap.wrap(func, name, "");
    def.ml_flags |= METH_STATIC;
    return def;
}

/// A class method: receives the class (not an instance). The most common use
/// is an alternative constructor — if `func` returns `T` (or `!T`), the
/// returned struct is wrapped into a fresh instance of the class, just like
/// `__init__` would. Otherwise the return value is converted normally.
///
///     fn from_pair(p: struct { x: i64, y: i64 }) Vec2 { return .{ .x = p.x, .y = p.y }; }
///     pz.classMethod(Vec2, "from_pair", from_pair)
pub fn classMethod(comptime T: type, comptime name: [:0]const u8, comptime func: anytype) zm.PyMethodDef {
    const Cell = pycell.PyCell(T);
    const fn_info = @typeInfo(@TypeOf(func)).@"fn";
    const params = fn_info.params;

    const Wrapper = struct {
        const Ctx = struct { cls: ?*zm.PyObject, args: ?*zm.PyObject };

        // Wrap a returned T into a new Python instance of `cls`.
        fn build(cls: ?*zm.PyObject, result: T) ?*zm.PyObject {
            const obj = createInstance(T, cls) orelse return null;
            Cell.ptrFromObj(obj).* = result;
            if (comptime structHasPyObjectField(T)) ownFields(T, obj);
            return obj;
        }

        fn inner(cls: ?*zm.PyObject, args_obj: ?*zm.PyObject) ?*zm.PyObject {
            const expected = @as(isize, @intCast(params.len));
            const actual: isize = if (args_obj) |a| zm.PyTuple_Size(a) else 0;
            if (actual != expected) {
                zm.PyErr_SetString(zm.PyExc_TypeError(), "wrong number of arguments");
                return null;
            }
            var arena = std.heap.ArenaAllocator.init(std.heap.c_allocator);
            defer arena.deinit();
            const a = arena.allocator();
            var call_args: funcwrap.paramTypesTupleDirect(params) = undefined;
            inline for (params, 0..) |param, i| {
                const arg_obj = zm.PyTuple_GetItem(args_obj, @as(isize, @intCast(i)));
                call_args[i] = conversion.fromPyObject(param.type.?, arg_obj, a) catch |err| {
                    funcwrap.setConversionError(err);
                    return null;
                };
            }
            const RetT = fn_info.return_type orelse void;
            if (RetT == T) {
                return build(cls, @call(.auto, func, call_args));
            } else if (@typeInfo(RetT) == .error_union and @typeInfo(RetT).error_union.payload == T) {
                const result = @call(.auto, func, call_args) catch |err| {
                    errors.setPyExceptionIfNeeded(err);
                    return null;
                };
                return build(cls, result);
            }
            return funcwrap.callAndConvert(func, fn_info, call_args);
        }

        fn thunk(p: ?*anyopaque) callconv(.c) ?*zm.PyObject {
            const c = @as(*Ctx, @ptrCast(@alignCast(p)));
            return inner(c.cls, c.args);
        }
        pub fn trampoline(cls: ?*zm.PyObject, args_obj: ?*zm.PyObject) callconv(.c) ?*zm.PyObject {
            var ctx = Ctx{ .cls = cls, .args = args_obj };
            return zm.pz_guard(&thunk, &ctx);
        }
    };

    return zm.PyMethodDef{
        .ml_name = @as(?[*:0]const u8, @ptrCast(name.ptr)),
        .ml_meth = &Wrapper.trampoline,
        .ml_flags = zm.METH_VARARGS | METH_CLASS,
        .ml_doc = null,
    };
}

pub fn PyClass(comptime T: type, comptime config: anytype) type {
    const Cell = pycell.PyCell(T);
    const type_name = buildTypeName(T);
    const short_name = comptime blk: {
        const full = @typeName(T);
        const dot = std.mem.lastIndexOfScalar(u8, full, '.');
        break :blk if (dot) |d| full[d + 1 ..] else full;
    };
    const has_methods = @hasField(@TypeOf(config), "methods");
    const has_readonly = @hasField(@TypeOf(config), "readonly");
    // Optional keyword-argument support for __init__: declare parameter names
    // (and optional defaults) on the class config.
    const has_init_args = @hasField(@TypeOf(config), "init_args");
    const has_init_defaults = @hasField(@TypeOf(config), "init_defaults");
    const init_spec = if (has_init_args)
        (if (has_init_defaults)
            .{ .args = config.init_args, .defaults = config.init_defaults }
        else
            .{ .args = config.init_args })
    else
        .{};
    const has_str = @hasDecl(T, "__str__");
    const has_repr = @hasDecl(T, "__repr__");
    const has_hash = @hasDecl(T, "__hash__");
    const has_eq = @hasDecl(T, "__eq__");
    const has_len = @hasDecl(T, "__len__");
    const has_getitem = @hasDecl(T, "__getitem__");
    const has_setitem = @hasDecl(T, "__setitem__");
    const has_contains = @hasDecl(T, "__contains__");
    const has_next = @hasDecl(T, "__next__");
    const has_iter = @hasDecl(T, "__iter__") or has_next;
    const has_add = @hasDecl(T, "__add__");
    const has_sub = @hasDecl(T, "__sub__");
    const has_mul = @hasDecl(T, "__mul__");
    const has_truediv = @hasDecl(T, "__truediv__");
    const has_floordiv = @hasDecl(T, "__floordiv__");
    const has_mod = @hasDecl(T, "__mod__");
    const has_pow = @hasDecl(T, "__pow__");
    const has_matmul = @hasDecl(T, "__matmul__");
    const has_neg = @hasDecl(T, "__neg__");
    const has_bool = @hasDecl(T, "__bool__");
    // Reflected binary operators (called when the left operand is not this type).
    const has_radd = @hasDecl(T, "__radd__");
    const has_rsub = @hasDecl(T, "__rsub__");
    const has_rmul = @hasDecl(T, "__rmul__");
    // Rich comparisons (a type may define any subset).
    const has_lt = @hasDecl(T, "__lt__");
    const has_le = @hasDecl(T, "__le__");
    const has_gt = @hasDecl(T, "__gt__");
    const has_ge = @hasDecl(T, "__ge__");
    const has_richcompare = has_eq or has_lt or has_le or has_gt or has_ge;
    const has_call = @hasDecl(T, "__call__");
    const has_doc = @hasField(@TypeOf(config), "doc");
    // Numeric conversions and in-place operators.
    const has_int = @hasDecl(T, "__int__");
    const has_float_conv = @hasDecl(T, "__float__");
    const has_index = @hasDecl(T, "__index__");
    const has_iadd = @hasDecl(T, "__iadd__");
    const has_isub = @hasDecl(T, "__isub__");
    const has_imul = @hasDecl(T, "__imul__");
    // Unary number ops: abs(x), +x, ~x.
    const has_abs = @hasDecl(T, "__abs__");
    const has_pos = @hasDecl(T, "__pos__");
    const has_invert = @hasDecl(T, "__invert__");
    // Bitwise / shift binary ops (same dispatch as the arithmetic ones, no
    // reflected form).
    const has_and = @hasDecl(T, "__and__");
    const has_or = @hasDecl(T, "__or__");
    const has_xor = @hasDecl(T, "__xor__");
    const has_lshift = @hasDecl(T, "__lshift__");
    const has_rshift = @hasDecl(T, "__rshift__");
    const has_divmod = @hasDecl(T, "__divmod__");
    // The remaining in-place operators (mutate self, return self).
    const has_itruediv = @hasDecl(T, "__itruediv__");
    const has_ifloordiv = @hasDecl(T, "__ifloordiv__");
    const has_imod = @hasDecl(T, "__imod__");
    const has_ipow = @hasDecl(T, "__ipow__");
    const has_imatmul = @hasDecl(T, "__imatmul__");
    const has_iand = @hasDecl(T, "__iand__");
    const has_ior = @hasDecl(T, "__ior__");
    const has_ixor = @hasDecl(T, "__ixor__");
    const has_ilshift = @hasDecl(T, "__ilshift__");
    const has_irshift = @hasDecl(T, "__irshift__");
    // Item deletion (`del obj[k]`) shares the mp_ass_subscript slot with
    // __setitem__; reversed()/format() are looked up as plain methods.
    const has_delitem = @hasDecl(T, "__delitem__");
    const has_assitem = has_setitem or has_delitem;
    // Python semantics: defining __eq__ without __hash__ makes instances
    // unhashable. Reproduce it (CPython would otherwise keep identity hashing).
    const auto_unhashable = has_eq and !has_hash;
    // Dynamic attribute access (fall back to generic lookup).
    const has_getattr = @hasDecl(T, "__getattr__");
    const has_setattr = @hasDecl(T, "__setattr__");
    // Plain methods auto-registered when present (context manager, pickle, copy,
    // formatting, ...). __enter__ is special-cased (void return -> self); the
    // rest are detected directly in the auto_methods loop via @hasDecl.
    const has_enter = @hasDecl(T, "__enter__");
    // copy.copy / copy.deepcopy: these return a fresh instance of the class, so
    // (unlike the plain-method dunders) they get instance-wrapping wrappers.
    const has_copy = @hasDecl(T, "__copy__");
    const has_deepcopy = @hasDecl(T, "__deepcopy__");
    // Read-only buffer protocol: __buffer__(self) returns a byte slice viewed
    // zero-copy (e.g. by numpy / memoryview). The slice must stay valid while
    // the buffer is held, so back it with a field of the instance.
    const has_buffer = @hasDecl(T, "__buffer__");

    const is_gc = structHasPyObjectField(T);
    const has_deinit = @hasDecl(T, "__deinit__");
    // A class needs a custom tp_dealloc only when it must run __deinit__ or
    // release PyObject fields. Otherwise we omit tp_dealloc and let CPython's
    // default handle teardown — which also makes the type safe to subclass from
    // Python (the default orchestrates a subclass's managed __dict__ and GC).
    const needs_custom_dealloc = has_deinit or is_gc;
    const can_subclass = !needs_custom_dealloc;

    // Cached type object (set once the type is built), used for isinstance
    // checks in operator dispatch so subclasses dispatch correctly.
    const TypeRef = struct {
        const Owner = T; // force a distinct type (and static var) per class
        var obj: ?*zm.PyObject = null;
    };

    const DeallocWrapper = struct {
        fn dealloc(obj: ?*zm.PyObject) callconv(.c) void {
            if (obj) |o| {
                const header = @as(*zm.PyObjectHeader, @ptrCast(@alignCast(o)));
                const ty = @as(?*zm.PyObject, @ptrCast(@alignCast(header.ob_type)));
                // GC objects must be untracked before running teardown.
                if (is_gc) zm.PyObject_GC_UnTrack(@as(?*anyopaque, @ptrCast(o)));
                // Invalidate any weak references before the object goes away
                // (managed weakref is enabled only for GC types; our custom
                // dealloc must clear it explicitly).
                if (is_gc) zm.PyObject_ClearWeakRefs(o);
                if (@hasDecl(T, "__deinit__")) {
                    Cell.ptrFromObj(o).__deinit__();
                }
                // Release the framework-owned references to PyObject fields.
                if (is_gc) releaseFields(T, o);
                if (is_gc) {
                    zm.PyObject_GC_Del(@as(?*anyopaque, @ptrCast(o)));
                } else {
                    zm.PyObject_Free(@as(?*anyopaque, @ptrCast(o)));
                }
                // Heap types are reference-counted; release the type ref taken
                // when the instance was allocated.
                zm.Py_XDECREF(ty);
            }
        }
    };

    const NewWrapper = struct {
        const Ctx = struct { ty: ?*zm.PyObject, args: ?*zm.PyObject, kwargs: ?*zm.PyObject };

        fn thunk(p: ?*anyopaque) callconv(.c) ?*zm.PyObject {
            const c = @as(*Ctx, @ptrCast(@alignCast(p)));
            return newInner(c.ty, c.args, c.kwargs);
        }

        fn new(ty: ?*zm.PyObject, args: ?*zm.PyObject, kwargs: ?*zm.PyObject) callconv(.c) ?*zm.PyObject {
            var ctx = Ctx{ .ty = ty, .args = args, .kwargs = kwargs };
            return zm.pz_guard(&thunk, &ctx);
        }

        // Free a partially-constructed instance (init failed). Fields are not
        // yet framework-owned, so they are not released here.
        fn freeOnError(obj: ?*zm.PyObject) void {
            const header = @as(*zm.PyObjectHeader, @ptrCast(@alignCast(obj)));
            const ty = @as(?*zm.PyObject, @ptrCast(@alignCast(header.ob_type)));
            freeInstanceMem(T, obj);
            zm.Py_XDECREF(ty);
        }

        fn newInner(ty: ?*zm.PyObject, args: ?*zm.PyObject, kwargs: ?*zm.PyObject) ?*zm.PyObject {
            if (!has_init_args and kwargs != null and zm.PyDict_Size(kwargs) > 0) {
                zm.PyErr_SetString(zm.PyExc_TypeError(), "keyword arguments not supported for init");
                return null;
            }
            const obj = createInstance(T, ty) orelse return null;

            if (@hasDecl(T, "init")) {
                const ptr = Cell.ptrFromObj(obj);
                const init_fn = T.init;
                const fn_info = @typeInfo(@TypeOf(init_fn)).@"fn";
                const params = fn_info.params;

                var arg_arena = std.heap.ArenaAllocator.init(std.heap.c_allocator);
                defer arg_arena.deinit();
                const arg_alloc = arg_arena.allocator();

                const init_args = blk: {
                    if (has_init_args) {
                        break :blk funcwrap.bindArgs(params, init_spec, args, kwargs, arg_alloc) orelse {
                            freeOnError(obj);
                            return null;
                        };
                    } else {
                        const actual: isize = if (args) |a| zm.PyTuple_Size(a) else 0;
                        if (actual != @as(isize, @intCast(params.len))) {
                            zm.PyErr_SetString(zm.PyExc_TypeError(), "wrong number of arguments for init");
                            freeOnError(obj);
                            return null;
                        }
                        var ia: funcwrap.paramTypesTupleDirect(params) = undefined;
                        inline for (params, 0..) |param, i| {
                            const arg_obj = zm.PyTuple_GetItem(args, @as(isize, @intCast(i)));
                            ia[i] = conversion.fromPyObject(param.type.?, arg_obj, arg_alloc) catch {
                                zm.PyErr_SetString(zm.PyExc_TypeError(), "init argument conversion failed");
                                freeOnError(obj);
                                return null;
                            };
                        }
                        break :blk ia;
                    }
                };

                const InitReturn = fn_info.return_type orelse void;
                if (InitReturn == void) {
                    @call(.auto, init_fn, init_args);
                } else if (@typeInfo(InitReturn) == .error_union) {
                    ptr.* = @call(.auto, init_fn, init_args) catch |err| {
                        errors.setPyExceptionIfNeeded(err);
                        freeOnError(obj);
                        return null;
                    };
                } else {
                    ptr.* = @call(.auto, init_fn, init_args);
                }
            }

            // The instance now owns a reference to each PyObject field.
            if (is_gc) ownFields(T, obj);
            return obj;
        }
    };

    // All slot bodies below run user code, so each is wrapped in the panic
    // safety net (pz_guard / pz_guard_ssize / pz_guard_int): a Zig panic
    // becomes a Python exception instead of aborting the interpreter. Slots
    // taking only `self` pass it straight through as the guard context; others
    // pack their arguments into a small stack Ctx.
    const StrWrapper = struct {
        fn inner(self_obj: ?*zm.PyObject) ?*zm.PyObject {
            const ptr = Cell.ptrFromObj(self_obj);
            const fn_info = @typeInfo(@TypeOf(T.__str__)).@"fn";
            return callFuncReturningPyObject(T.__str__, fn_info, .{ptr});
        }
        fn thunk(p: ?*anyopaque) callconv(.c) ?*zm.PyObject {
            return inner(@as(?*zm.PyObject, @ptrCast(@alignCast(p))));
        }
        fn str(self_obj: ?*zm.PyObject) callconv(.c) ?*zm.PyObject {
            return zm.pz_guard(&thunk, @ptrCast(self_obj));
        }
    };

    const ReprWrapper = struct {
        fn inner(self_obj: ?*zm.PyObject) ?*zm.PyObject {
            const ptr = Cell.ptrFromObj(self_obj);
            const fn_info = @typeInfo(@TypeOf(T.__repr__)).@"fn";
            return callFuncReturningPyObject(T.__repr__, fn_info, .{ptr});
        }
        fn thunk(p: ?*anyopaque) callconv(.c) ?*zm.PyObject {
            return inner(@as(?*zm.PyObject, @ptrCast(@alignCast(p))));
        }
        fn repr(self_obj: ?*zm.PyObject) callconv(.c) ?*zm.PyObject {
            return zm.pz_guard(&thunk, @ptrCast(self_obj));
        }
    };

    const HashWrapper = struct {
        fn inner(self_obj: ?*zm.PyObject) isize {
            const ptr = Cell.ptrFromObj(self_obj);
            const result = @as(isize, @intCast(T.__hash__(ptr)));
            // -1 is CPython's error sentinel; remap to a valid hash.
            return if (result == -1) -2 else result;
        }
        fn thunk(p: ?*anyopaque) callconv(.c) isize {
            return inner(@as(?*zm.PyObject, @ptrCast(@alignCast(p))));
        }
        fn hash(self_obj: ?*zm.PyObject) callconv(.c) isize {
            return zm.pz_guard_ssize(&thunk, @ptrCast(self_obj));
        }
    };

    const RichcompareWrapper = struct {
        // CPython richcompare op codes.
        const Py_LT: c_int = 0;
        const Py_LE: c_int = 1;
        const Py_EQ: c_int = 2;
        const Py_NE: c_int = 3;
        const Py_GT: c_int = 4;
        const Py_GE: c_int = 5;
        const Ctx = struct { self: ?*zm.PyObject, other: ?*zm.PyObject, op: c_int };

        fn boolResult(b: bool) ?*zm.PyObject {
            return zm.Py_NewRef(if (b) zm.Py_True() else zm.Py_False());
        }

        fn inner(self_obj: ?*zm.PyObject, other_obj: ?*zm.PyObject, op: c_int) ?*zm.PyObject {
            if (other_obj == null) return zm.Py_NewRef(zm.Py_NotImplemented());
            const hdr_self = @as(*zm.PyObjectHeader, @ptrCast(@alignCast(self_obj)));
            const hdr_other = @as(*zm.PyObjectHeader, @ptrCast(@alignCast(other_obj)));
            // Comparisons are defined between two operands of the same type;
            // anything else yields NotImplemented (Python then decides).
            if (hdr_self.ob_type != hdr_other.ob_type) return zm.Py_NewRef(zm.Py_NotImplemented());
            const a = Cell.ptrFromObj(self_obj);
            const b = Cell.ptrFromObj(other_obj);
            switch (op) {
                Py_EQ => if (comptime has_eq) return boolResult(T.__eq__(a, b)),
                // __ne__ is derived from __eq__ when not given explicitly.
                Py_NE => if (comptime has_eq) return boolResult(!T.__eq__(a, b)),
                Py_LT => if (comptime has_lt) return boolResult(T.__lt__(a, b)),
                Py_LE => if (comptime has_le) return boolResult(T.__le__(a, b)),
                Py_GT => if (comptime has_gt) return boolResult(T.__gt__(a, b)),
                Py_GE => if (comptime has_ge) return boolResult(T.__ge__(a, b)),
                else => {},
            }
            return zm.Py_NewRef(zm.Py_NotImplemented());
        }
        fn thunk(p: ?*anyopaque) callconv(.c) ?*zm.PyObject {
            const c = @as(*Ctx, @ptrCast(@alignCast(p)));
            return inner(c.self, c.other, c.op);
        }
        fn richcompare(self_obj: ?*zm.PyObject, other_obj: ?*zm.PyObject, op: c_int) callconv(.c) ?*zm.PyObject {
            var ctx = Ctx{ .self = self_obj, .other = other_obj, .op = op };
            return zm.pz_guard(&thunk, &ctx);
        }
    };

    const LenWrapper = struct {
        fn inner(self_obj: ?*zm.PyObject) isize {
            const ptr = Cell.ptrFromObj(self_obj);
            return @as(isize, @intCast(T.__len__(ptr)));
        }
        fn thunk(p: ?*anyopaque) callconv(.c) isize {
            return inner(@as(?*zm.PyObject, @ptrCast(@alignCast(p))));
        }
        fn len(self_obj: ?*zm.PyObject) callconv(.c) isize {
            return zm.pz_guard_ssize(&thunk, @ptrCast(self_obj));
        }
    };

    const GetItemWrapper = struct {
        const Ctx = struct { self: ?*zm.PyObject, key: ?*zm.PyObject };
        fn inner(self_obj: ?*zm.PyObject, key_obj: ?*zm.PyObject) ?*zm.PyObject {
            const ptr = Cell.ptrFromObj(self_obj);
            const fn_info = @typeInfo(@TypeOf(T.__getitem__)).@"fn";
            const KeyT = fn_info.params[1].type.?;
            var arena = std.heap.ArenaAllocator.init(std.heap.c_allocator);
            defer arena.deinit();
            var key = conversion.fromPyObject(KeyT, key_obj, arena.allocator()) catch |err| {
                funcwrap.setConversionError(err);
                return null;
            };
            // Python sequence semantics: a negative integer index counts from
            // the end. Normalize it when the class also defines __len__.
            if (has_len and @typeInfo(KeyT) == .int) {
                if (key < 0) key += @as(KeyT, @intCast(T.__len__(ptr)));
            }
            return callFuncReturningPyObject(T.__getitem__, fn_info, .{ ptr, key });
        }
        fn thunk(p: ?*anyopaque) callconv(.c) ?*zm.PyObject {
            const c = @as(*Ctx, @ptrCast(@alignCast(p)));
            return inner(c.self, c.key);
        }
        fn getitem(self_obj: ?*zm.PyObject, key_obj: ?*zm.PyObject) callconv(.c) ?*zm.PyObject {
            var ctx = Ctx{ .self = self_obj, .key = key_obj };
            return zm.pz_guard(&thunk, &ctx);
        }
    };

    const SetItemWrapper = struct {
        const Ctx = struct { self: ?*zm.PyObject, key: ?*zm.PyObject, val: ?*zm.PyObject };
        fn inner(self_obj: ?*zm.PyObject, key_obj: ?*zm.PyObject, val_obj: ?*zm.PyObject) c_int {
            const ptr = Cell.ptrFromObj(self_obj);
            var arena = std.heap.ArenaAllocator.init(std.heap.c_allocator);
            defer arena.deinit();
            const a = arena.allocator();
            // A null value means `del obj[key]` -> __delitem__.
            if (val_obj == null) {
                if (comptime has_delitem) {
                    const di = @typeInfo(@TypeOf(T.__delitem__)).@"fn";
                    const key = conversion.fromPyObject(di.params[1].type.?, key_obj, a) catch |err| {
                        funcwrap.setConversionError(err);
                        return -1;
                    };
                    if (@typeInfo(di.return_type orelse void) == .error_union) {
                        T.__delitem__(ptr, key) catch |err| {
                            errors.setPyExceptionIfNeeded(err);
                            return -1;
                        };
                    } else {
                        T.__delitem__(ptr, key);
                    }
                    return 0;
                }
                zm.PyErr_SetString(zm.PyExc_TypeError(), "item deletion not supported");
                return -1;
            }
            if (comptime !has_setitem) {
                zm.PyErr_SetString(zm.PyExc_TypeError(), "item assignment not supported");
                return -1;
            }
            const fn_info = @typeInfo(@TypeOf(T.__setitem__)).@"fn";
            const key = conversion.fromPyObject(fn_info.params[1].type.?, key_obj, a) catch |err| {
                funcwrap.setConversionError(err);
                return -1;
            };
            const value = conversion.fromPyObject(fn_info.params[2].type.?, val_obj, a) catch |err| {
                funcwrap.setConversionError(err);
                return -1;
            };
            if (@typeInfo(fn_info.return_type orelse void) == .error_union) {
                T.__setitem__(ptr, key, value) catch |err| {
                    errors.setPyExceptionIfNeeded(err);
                    return -1;
                };
            } else {
                T.__setitem__(ptr, key, value);
            }
            return 0;
        }
        fn thunk(p: ?*anyopaque) callconv(.c) c_int {
            const c = @as(*Ctx, @ptrCast(@alignCast(p)));
            return inner(c.self, c.key, c.val);
        }
        fn setitem(self_obj: ?*zm.PyObject, key_obj: ?*zm.PyObject, val_obj: ?*zm.PyObject) callconv(.c) c_int {
            var ctx = Ctx{ .self = self_obj, .key = key_obj, .val = val_obj };
            return zm.pz_guard_int(&thunk, &ctx);
        }
    };

    const ContainsWrapper = struct {
        const Ctx = struct { self: ?*zm.PyObject, item: ?*zm.PyObject };
        fn inner(self_obj: ?*zm.PyObject, item_obj: ?*zm.PyObject) c_int {
            const ptr = Cell.ptrFromObj(self_obj);
            const fn_info = @typeInfo(@TypeOf(T.__contains__)).@"fn";
            var arena = std.heap.ArenaAllocator.init(std.heap.c_allocator);
            defer arena.deinit();
            const item = conversion.fromPyObject(fn_info.params[1].type.?, item_obj, arena.allocator()) catch {
                return -1;
            };
            return if (T.__contains__(ptr, item)) 1 else 0;
        }
        fn thunk(p: ?*anyopaque) callconv(.c) c_int {
            const c = @as(*Ctx, @ptrCast(@alignCast(p)));
            return inner(c.self, c.item);
        }
        fn contains(self_obj: ?*zm.PyObject, item_obj: ?*zm.PyObject) callconv(.c) c_int {
            var ctx = Ctx{ .self = self_obj, .item = item_obj };
            return zm.pz_guard_int(&thunk, &ctx);
        }
    };

    const NextWrapper = struct {
        fn inner(self_obj: ?*zm.PyObject) ?*zm.PyObject {
            const ptr = Cell.ptrFromObj(self_obj);
            const RetT = @typeInfo(@TypeOf(T.__next__)).@"fn".return_type.?;
            const maybe = if (@typeInfo(RetT) == .error_union)
                (T.__next__(ptr) catch |err| {
                    errors.setPyExceptionIfNeeded(err);
                    return null;
                })
            else
                T.__next__(ptr);
            // null optional -> StopIteration (return null with no exception set).
            if (maybe) |v| return funcwrap.returnToPyObjectValue(v);
            return null;
        }
        fn thunk(p: ?*anyopaque) callconv(.c) ?*zm.PyObject {
            return inner(@as(?*zm.PyObject, @ptrCast(@alignCast(p))));
        }
        fn iternext(self_obj: ?*zm.PyObject) callconv(.c) ?*zm.PyObject {
            return zm.pz_guard(&thunk, @ptrCast(self_obj));
        }
    };

    const IterWrapper = struct {
        fn inner(self_obj: ?*zm.PyObject) ?*zm.PyObject {
            if (@hasDecl(T, "__iter__")) {
                const ptr = Cell.ptrFromObj(self_obj);
                const fn_info = @typeInfo(@TypeOf(T.__iter__)).@"fn";
                return callFuncReturningPyObject(T.__iter__, fn_info, .{ptr});
            }
            // Self-iterator: a type with __next__ is its own iterator.
            return zm.Py_NewRef(self_obj);
        }
        fn thunk(p: ?*anyopaque) callconv(.c) ?*zm.PyObject {
            return inner(@as(?*zm.PyObject, @ptrCast(@alignCast(p))));
        }
        fn iter(self_obj: ?*zm.PyObject) callconv(.c) ?*zm.PyObject {
            return zm.pz_guard(&thunk, @ptrCast(self_obj));
        }
    };

    // Number-protocol operators. Binary ops support same-type operands and
    // mixed operands (e.g. `vec * 2` if __mul__ takes an int); when the left
    // operand isn't this type, the reflected form (`__radd__`/`__rsub__`/
    // `__rmul__`) is tried. A result of type T is wrapped into a new instance;
    // any other type is converted normally (e.g. a dot product returning i64).
    const NumberWrapper = struct {
        // True if `obj` is an instance of this class or a Python subclass. Uses
        // the cached type object so subclasses (with a different tp_name) still
        // dispatch operators correctly.
        fn isOurs(obj: ?*zm.PyObject) bool {
            if (TypeRef.obj) |ty| return zm.PyObject_IsInstance(obj, ty) == 1;
            return std.mem.eql(u8, std.mem.span(zm.pz_type_name(obj)), short_name);
        }
        fn convertResult(cls: ?*zm.PyObject, result: anytype) ?*zm.PyObject {
            if (@TypeOf(result) == T) {
                const obj = createInstance(T, cls) orelse return null;
                Cell.ptrFromObj(obj).* = result;
                if (comptime structHasPyObjectField(T)) ownFields(T, obj);
                return obj;
            }
            return funcwrap.returnToPyObjectValue(result);
        }
        // Call `func(self, other)` where `self_obj` is this type and `other_obj`
        // is converted to func's second parameter type. A conversion failure
        // means the operand isn't acceptable -> NotImplemented.
        fn invoke(comptime func: anytype, self_obj: ?*zm.PyObject, other_obj: ?*zm.PyObject) ?*zm.PyObject {
            const fi = @typeInfo(@TypeOf(func)).@"fn";
            const OtherT = fi.params[1].type.?;
            var arena = std.heap.ArenaAllocator.init(std.heap.c_allocator);
            defer arena.deinit();
            const other = conversion.fromPyObject(OtherT, other_obj, arena.allocator()) catch {
                zm.PyErr_Clear();
                return zm.Py_NewRef(zm.Py_NotImplemented());
            };
            const self_ptr = Cell.ptrFromObj(self_obj);
            const hdr = @as(*zm.PyObjectHeader, @ptrCast(@alignCast(self_obj)));
            const cls = @as(?*zm.PyObject, @ptrCast(@alignCast(hdr.ob_type)));
            const RetT = fi.return_type.?;
            if (@typeInfo(RetT) == .error_union) {
                const r = func(self_ptr, other) catch |e| {
                    errors.setPyExceptionIfNeeded(e);
                    return null;
                };
                return convertResult(cls, r);
            }
            return convertResult(cls, func(self_ptr, other));
        }
        fn dispatch(comptime fwd: anytype, comptime has_rev: bool, comptime rev: anytype, a_obj: ?*zm.PyObject, b_obj: ?*zm.PyObject) ?*zm.PyObject {
            if (isOurs(a_obj)) return invoke(fwd, a_obj, b_obj);
            if (comptime has_rev) {
                if (isOurs(b_obj)) return invoke(rev, b_obj, a_obj);
            }
            return zm.Py_NewRef(zm.Py_NotImplemented());
        }
        // In-place operators mutate `self` in place (the op fn returns void) and
        // yield a new reference to the same object.
        fn invokeInplace(comptime func: anytype, self_obj: ?*zm.PyObject, other_obj: ?*zm.PyObject) ?*zm.PyObject {
            const fi = @typeInfo(@TypeOf(func)).@"fn";
            const OtherT = fi.params[1].type.?;
            var arena = std.heap.ArenaAllocator.init(std.heap.c_allocator);
            defer arena.deinit();
            const other = conversion.fromPyObject(OtherT, other_obj, arena.allocator()) catch {
                zm.PyErr_Clear();
                return zm.Py_NewRef(zm.Py_NotImplemented());
            };
            const self_ptr = Cell.ptrFromObj(self_obj);
            const RetT = fi.return_type.?;
            if (@typeInfo(RetT) == .error_union) {
                func(self_ptr, other) catch |e| {
                    errors.setPyExceptionIfNeeded(e);
                    return null;
                };
            } else {
                func(self_ptr, other);
            }
            return zm.Py_NewRef(self_obj);
        }
        fn dispatchInplace(comptime func: anytype, a_obj: ?*zm.PyObject, b_obj: ?*zm.PyObject) ?*zm.PyObject {
            if (isOurs(a_obj)) return invokeInplace(func, a_obj, b_obj);
            return zm.Py_NewRef(zm.Py_NotImplemented());
        }
        fn callUnary(comptime func: anytype, self_obj: ?*zm.PyObject) ?*zm.PyObject {
            const hdr = @as(*zm.PyObjectHeader, @ptrCast(@alignCast(self_obj)));
            const cls = @as(?*zm.PyObject, @ptrCast(@alignCast(hdr.ob_type)));
            const ptr = Cell.ptrFromObj(self_obj);
            const RetT = @typeInfo(@TypeOf(func)).@"fn".return_type.?;
            if (@typeInfo(RetT) == .error_union) {
                const r = func(ptr) catch |e| {
                    errors.setPyExceptionIfNeeded(e);
                    return null;
                };
                return convertResult(cls, r);
            }
            return convertResult(cls, func(ptr));
        }
    };

    // One binary-op wrapper, parameterized by the forward decl and (optional)
    // reflected decl. `BinCtx` carries the two operands through the panic guard.
    const BinCtx = struct { a: ?*zm.PyObject, b: ?*zm.PyObject };
    const BinaryOp = struct {
        fn make(comptime fwd: anytype, comptime has_rev: bool, comptime rev: anytype) type {
            return struct {
                fn thunk(p: ?*anyopaque) callconv(.c) ?*zm.PyObject {
                    const c = @as(*BinCtx, @ptrCast(@alignCast(p)));
                    return NumberWrapper.dispatch(fwd, has_rev, rev, c.a, c.b);
                }
                fn op(a_obj: ?*zm.PyObject, b_obj: ?*zm.PyObject) callconv(.c) ?*zm.PyObject {
                    var ctx = BinCtx{ .a = a_obj, .b = b_obj };
                    return zm.pz_guard(&thunk, &ctx);
                }
                // nb_power is ternary (a, b, modulo); the modulo is ignored.
                fn powop(a_obj: ?*zm.PyObject, b_obj: ?*zm.PyObject, _: ?*zm.PyObject) callconv(.c) ?*zm.PyObject {
                    var ctx = BinCtx{ .a = a_obj, .b = b_obj };
                    return zm.pz_guard(&thunk, &ctx);
                }
            };
        }
    }.make;

    const AddWrapper = BinaryOp(if (has_add) T.__add__ else {}, has_radd, if (has_radd) T.__radd__ else {});
    const SubWrapper = BinaryOp(if (has_sub) T.__sub__ else {}, has_rsub, if (has_rsub) T.__rsub__ else {});
    const MulWrapper = BinaryOp(if (has_mul) T.__mul__ else {}, has_rmul, if (has_rmul) T.__rmul__ else {});
    const TrueDivWrapper = BinaryOp(if (has_truediv) T.__truediv__ else {}, false, {});
    const FloorDivWrapper = BinaryOp(if (has_floordiv) T.__floordiv__ else {}, false, {});
    const ModWrapper = BinaryOp(if (has_mod) T.__mod__ else {}, false, {});
    const PowWrapper = BinaryOp(if (has_pow) T.__pow__ else {}, false, {});
    const MatMulWrapper = BinaryOp(if (has_matmul) T.__matmul__ else {}, false, {});
    const AndWrapper = BinaryOp(if (has_and) T.__and__ else {}, false, {});
    const OrWrapper = BinaryOp(if (has_or) T.__or__ else {}, false, {});
    const XorWrapper = BinaryOp(if (has_xor) T.__xor__ else {}, false, {});
    const LshiftWrapper = BinaryOp(if (has_lshift) T.__lshift__ else {}, false, {});
    const RshiftWrapper = BinaryOp(if (has_rshift) T.__rshift__ else {}, false, {});
    const DivmodWrapper = BinaryOp(if (has_divmod) T.__divmod__ else {}, false, {});

    const NegWrapper = struct {
        fn thunk(p: ?*anyopaque) callconv(.c) ?*zm.PyObject {
            return NumberWrapper.callUnary(T.__neg__, @as(?*zm.PyObject, @ptrCast(@alignCast(p))));
        }
        fn op(self_obj: ?*zm.PyObject) callconv(.c) ?*zm.PyObject {
            return zm.pz_guard(&thunk, @ptrCast(self_obj));
        }
    };
    const BoolWrapper = struct {
        fn inner(self_obj: ?*zm.PyObject) c_int {
            const ptr = Cell.ptrFromObj(self_obj);
            return if (T.__bool__(ptr)) 1 else 0;
        }
        fn thunk(p: ?*anyopaque) callconv(.c) c_int {
            return inner(@as(?*zm.PyObject, @ptrCast(@alignCast(p))));
        }
        fn op(self_obj: ?*zm.PyObject) callconv(.c) c_int {
            return zm.pz_guard_int(&thunk, @ptrCast(self_obj));
        }
    };

    // Generic unary number op (abs/pos/invert): like __neg__, a result of type
    // T is wrapped into a new instance, any other type converted normally.
    const UnaryOp = struct {
        fn make(comptime func: anytype) type {
            return struct {
                fn thunk(p: ?*anyopaque) callconv(.c) ?*zm.PyObject {
                    return NumberWrapper.callUnary(func, @as(?*zm.PyObject, @ptrCast(@alignCast(p))));
                }
                fn op(self_obj: ?*zm.PyObject) callconv(.c) ?*zm.PyObject {
                    return zm.pz_guard(&thunk, @ptrCast(self_obj));
                }
            };
        }
    }.make;
    const AbsWrapper = UnaryOp(if (has_abs) T.__abs__ else {});
    const PosWrapper = UnaryOp(if (has_pos) T.__pos__ else {});
    const InvertWrapper = UnaryOp(if (has_invert) T.__invert__ else {});

    // Scalar-returning unary conversions: __int__, __float__, __index__.
    const ScalarUnary = struct {
        fn make(comptime func: anytype) type {
            return struct {
                fn thunk(p: ?*anyopaque) callconv(.c) ?*zm.PyObject {
                    const self_obj = @as(?*zm.PyObject, @ptrCast(@alignCast(p)));
                    const ptr = Cell.ptrFromObj(self_obj);
                    const fi = @typeInfo(@TypeOf(func)).@"fn";
                    return callFuncReturningPyObject(func, fi, .{ptr});
                }
                fn op(self_obj: ?*zm.PyObject) callconv(.c) ?*zm.PyObject {
                    return zm.pz_guard(&thunk, @ptrCast(self_obj));
                }
            };
        }
    }.make;
    const IntWrapper = ScalarUnary(if (has_int) T.__int__ else {});
    const FloatWrapper = ScalarUnary(if (has_float_conv) T.__float__ else {});
    const IndexWrapper = ScalarUnary(if (has_index) T.__index__ else {});

    // In-place operators (__iadd__/__isub__/__imul__).
    const InplaceOp = struct {
        fn make(comptime func: anytype) type {
            return struct {
                fn thunk(p: ?*anyopaque) callconv(.c) ?*zm.PyObject {
                    const c = @as(*BinCtx, @ptrCast(@alignCast(p)));
                    return NumberWrapper.dispatchInplace(func, c.a, c.b);
                }
                fn op(a_obj: ?*zm.PyObject, b_obj: ?*zm.PyObject) callconv(.c) ?*zm.PyObject {
                    var ctx = BinCtx{ .a = a_obj, .b = b_obj };
                    return zm.pz_guard(&thunk, &ctx);
                }
                // nb_inplace_power is ternary (a, b, modulo); modulo ignored.
                fn powop(a_obj: ?*zm.PyObject, b_obj: ?*zm.PyObject, _: ?*zm.PyObject) callconv(.c) ?*zm.PyObject {
                    var ctx = BinCtx{ .a = a_obj, .b = b_obj };
                    return zm.pz_guard(&thunk, &ctx);
                }
            };
        }
    }.make;
    const IaddWrapper = InplaceOp(if (has_iadd) T.__iadd__ else {});
    const IsubWrapper = InplaceOp(if (has_isub) T.__isub__ else {});
    const ImulWrapper = InplaceOp(if (has_imul) T.__imul__ else {});
    const ItruedivWrapper = InplaceOp(if (has_itruediv) T.__itruediv__ else {});
    const IfloordivWrapper = InplaceOp(if (has_ifloordiv) T.__ifloordiv__ else {});
    const ImodWrapper = InplaceOp(if (has_imod) T.__imod__ else {});
    const IpowWrapper = InplaceOp(if (has_ipow) T.__ipow__ else {});
    const ImatmulWrapper = InplaceOp(if (has_imatmul) T.__imatmul__ else {});
    const IandWrapper = InplaceOp(if (has_iand) T.__iand__ else {});
    const IorWrapper = InplaceOp(if (has_ior) T.__ior__ else {});
    const IxorWrapper = InplaceOp(if (has_ixor) T.__ixor__ else {});
    const IlshiftWrapper = InplaceOp(if (has_ilshift) T.__ilshift__ else {});
    const IrshiftWrapper = InplaceOp(if (has_irshift) T.__irshift__ else {});

    // tp_getattro: only consulted when normal attribute lookup fails, matching
    // Python's __getattr__ semantics. __getattr__(self, name: []const u8).
    const GetAttrWrapper = struct {
        const Ctx = struct { self: ?*zm.PyObject, name: ?*zm.PyObject };
        fn inner(self_obj: ?*zm.PyObject, name_obj: ?*zm.PyObject) ?*zm.PyObject {
            const res = zm.PyObject_GenericGetAttr(self_obj, name_obj);
            if (res != null) return res;
            // Normal lookup failed; only fall back on AttributeError.
            if (zm.PyErr_ExceptionMatches(zm.PyExc_AttributeError()) == 0) return null;
            zm.PyErr_Clear();
            const ptr = Cell.ptrFromObj(self_obj);
            const fi = @typeInfo(@TypeOf(T.__getattr__)).@"fn";
            var arena = std.heap.ArenaAllocator.init(std.heap.c_allocator);
            defer arena.deinit();
            const name = conversion.fromPyObject([]const u8, name_obj, arena.allocator()) catch {
                return null;
            };
            return callFuncReturningPyObject(T.__getattr__, fi, .{ ptr, name });
        }
        fn thunk(p: ?*anyopaque) callconv(.c) ?*zm.PyObject {
            const c = @as(*Ctx, @ptrCast(@alignCast(p)));
            return inner(c.self, c.name);
        }
        fn getattro(self_obj: ?*zm.PyObject, name_obj: ?*zm.PyObject) callconv(.c) ?*zm.PyObject {
            var ctx = Ctx{ .self = self_obj, .name = name_obj };
            return zm.pz_guard(&thunk, &ctx);
        }
    };

    // tp_setattro: user handles every attribute assignment.
    // __setattr__(self, name: []const u8, value: ?*PyObject) (void or !void).
    const SetAttrWrapper = struct {
        const Ctx = struct { self: ?*zm.PyObject, name: ?*zm.PyObject, value: ?*zm.PyObject };
        fn inner(self_obj: ?*zm.PyObject, name_obj: ?*zm.PyObject, value_obj: ?*zm.PyObject) c_int {
            const ptr = Cell.ptrFromObj(self_obj);
            const fi = @typeInfo(@TypeOf(T.__setattr__)).@"fn";
            var arena = std.heap.ArenaAllocator.init(std.heap.c_allocator);
            defer arena.deinit();
            const name = conversion.fromPyObject([]const u8, name_obj, arena.allocator()) catch return -1;
            if (@typeInfo(fi.return_type orelse void) == .error_union) {
                T.__setattr__(ptr, name, value_obj) catch |e| {
                    errors.setPyExceptionIfNeeded(e);
                    return -1;
                };
            } else {
                T.__setattr__(ptr, name, value_obj);
            }
            return 0;
        }
        fn thunk(p: ?*anyopaque) callconv(.c) c_int {
            const c = @as(*Ctx, @ptrCast(@alignCast(p)));
            return inner(c.self, c.name, c.value);
        }
        fn setattro(self_obj: ?*zm.PyObject, name_obj: ?*zm.PyObject, value_obj: ?*zm.PyObject) callconv(.c) c_int {
            var ctx = Ctx{ .self = self_obj, .name = name_obj, .value = value_obj };
            return zm.pz_guard_int(&thunk, &ctx);
        }
    };

    // __enter__ auto-method: returns the user's value, or `self` if it returns
    // void (the common `with x as x` case).
    const EnterWrapper = struct {
        fn inner(self_obj: ?*zm.PyObject) ?*zm.PyObject {
            const ptr = Cell.ptrFromObj(self_obj);
            const fi = @typeInfo(@TypeOf(T.__enter__)).@"fn";
            const RetT = fi.return_type orelse void;
            if (RetT == void) {
                T.__enter__(ptr);
                return zm.Py_NewRef(self_obj);
            }
            return callFuncReturningPyObject(T.__enter__, fi, .{ptr});
        }
        fn thunk(p: ?*anyopaque) callconv(.c) ?*zm.PyObject {
            return inner(@as(?*zm.PyObject, @ptrCast(@alignCast(p))));
        }
        fn meth(self_obj: ?*zm.PyObject, args_obj: ?*zm.PyObject) callconv(.c) ?*zm.PyObject {
            _ = args_obj;
            return zm.pz_guard(&thunk, @ptrCast(self_obj));
        }
    };

    // copy.copy(obj): __copy__(self) returns a new value of the class, wrapped
    // into a fresh instance of self's (sub)type.
    const CopyWrapper = struct {
        fn inner(self_obj: ?*zm.PyObject) ?*zm.PyObject {
            const ptr = Cell.ptrFromObj(self_obj);
            const hdr = @as(*zm.PyObjectHeader, @ptrCast(@alignCast(self_obj)));
            const cls = @as(?*zm.PyObject, @ptrCast(@alignCast(hdr.ob_type)));
            const RetT = @typeInfo(@TypeOf(T.__copy__)).@"fn".return_type.?;
            if (@typeInfo(RetT) == .error_union) {
                const r = T.__copy__(ptr) catch |e| {
                    errors.setPyExceptionIfNeeded(e);
                    return null;
                };
                return NumberWrapper.convertResult(cls, r);
            }
            return NumberWrapper.convertResult(cls, T.__copy__(ptr));
        }
        fn thunk(p: ?*anyopaque) callconv(.c) ?*zm.PyObject {
            return inner(@as(?*zm.PyObject, @ptrCast(@alignCast(p))));
        }
        fn meth(self_obj: ?*zm.PyObject, args_obj: ?*zm.PyObject) callconv(.c) ?*zm.PyObject {
            _ = args_obj;
            return zm.pz_guard(&thunk, @ptrCast(self_obj));
        }
    };

    // copy.deepcopy(obj, memo): __deepcopy__(self, memo) returns a new instance.
    // The memo argument is converted to the second parameter's type (commonly
    // `?*pz.PyObject`).
    const DeepCopyWrapper = struct {
        const Ctx = struct { self: ?*zm.PyObject, args: ?*zm.PyObject };
        fn inner(self_obj: ?*zm.PyObject, args_obj: ?*zm.PyObject) ?*zm.PyObject {
            const ptr = Cell.ptrFromObj(self_obj);
            const hdr = @as(*zm.PyObjectHeader, @ptrCast(@alignCast(self_obj)));
            const cls = @as(?*zm.PyObject, @ptrCast(@alignCast(hdr.ob_type)));
            const fi = @typeInfo(@TypeOf(T.__deepcopy__)).@"fn";
            const MemoT = fi.params[1].type.?;
            const memo_obj = if (args_obj != null and zm.PyTuple_Size(args_obj) > 0)
                zm.PyTuple_GetItem(args_obj, 0)
            else
                null;
            var arena = std.heap.ArenaAllocator.init(std.heap.c_allocator);
            defer arena.deinit();
            const memo = conversion.fromPyObject(MemoT, memo_obj, arena.allocator()) catch |err| {
                funcwrap.setConversionError(err);
                return null;
            };
            if (@typeInfo(fi.return_type.?) == .error_union) {
                const r = T.__deepcopy__(ptr, memo) catch |e| {
                    errors.setPyExceptionIfNeeded(e);
                    return null;
                };
                return NumberWrapper.convertResult(cls, r);
            }
            return NumberWrapper.convertResult(cls, T.__deepcopy__(ptr, memo));
        }
        fn thunk(p: ?*anyopaque) callconv(.c) ?*zm.PyObject {
            const c = @as(*Ctx, @ptrCast(@alignCast(p)));
            return inner(c.self, c.args);
        }
        fn meth(self_obj: ?*zm.PyObject, args_obj: ?*zm.PyObject) callconv(.c) ?*zm.PyObject {
            var ctx = Ctx{ .self = self_obj, .args = args_obj };
            return zm.pz_guard(&thunk, &ctx);
        }
    };

    // bf_getbuffer: expose a read-only contiguous byte view (memoryview/numpy).
    const BufferWrapper = struct {
        fn getbuffer(exporter: ?*zm.PyObject, view: ?*anyopaque, flags: c_int) callconv(.c) c_int {
            if (view == null) {
                zm.PyErr_SetString(zm.PyExc_RuntimeError(), "NULL buffer view");
                return -1;
            }
            const ptr = Cell.ptrFromObj(exporter);
            const data: []const u8 = T.__buffer__(ptr);
            return zm.PyBuffer_FillInfo(view, exporter, @constCast(@ptrCast(data.ptr)), @as(isize, @intCast(data.len)), 1, flags);
        }
    };

    // tp_call: makes instances callable. Positional arguments only (kwargs are
    // ignored); `__call__(self, ...)` is wrapped like a method.
    const CallWrapper = struct {
        const Ctx = struct { self: ?*zm.PyObject, args: ?*zm.PyObject, kwargs: ?*zm.PyObject };
        fn inner(self_obj: ?*zm.PyObject, args_obj: ?*zm.PyObject) ?*zm.PyObject {
            const fn_info = @typeInfo(@TypeOf(T.__call__)).@"fn";
            const method_params = fn_info.params[1..];
            const self_ptr = Cell.ptrFromObj(self_obj);
            const expected = @as(isize, @intCast(method_params.len));
            const actual: isize = if (args_obj) |a| zm.PyTuple_Size(a) else 0;
            if (actual != expected) {
                zm.PyErr_SetString(zm.PyExc_TypeError(), "wrong number of arguments");
                return null;
            }
            var arena = std.heap.ArenaAllocator.init(std.heap.c_allocator);
            defer arena.deinit();
            const a = arena.allocator();
            var call_args: funcwrap.paramTypesTupleDirect(method_params) = undefined;
            inline for (method_params, 0..) |param, i| {
                const arg_obj = zm.PyTuple_GetItem(args_obj, @as(isize, @intCast(i)));
                call_args[i] = conversion.fromPyObject(param.type.?, arg_obj, a) catch |err| {
                    funcwrap.setConversionError(err);
                    return null;
                };
            }
            return funcwrap.callAndConvert(T.__call__, fn_info, .{self_ptr} ++ call_args);
        }
        fn thunk(p: ?*anyopaque) callconv(.c) ?*zm.PyObject {
            const c = @as(*Ctx, @ptrCast(@alignCast(p)));
            return inner(c.self, c.args);
        }
        fn call(self_obj: ?*zm.PyObject, args_obj: ?*zm.PyObject, kwargs_obj: ?*zm.PyObject) callconv(.c) ?*zm.PyObject {
            var ctx = Ctx{ .self = self_obj, .args = args_obj, .kwargs = kwargs_obj };
            return zm.pz_guard(&thunk, &ctx);
        }
    };

    // GC support for classes holding PyObject fields: visit fields in traverse,
    // clear them in clear (breaks reference cycles).
    const GcWrapper = struct {
        fn traverse(self_obj: ?*zm.PyObject, visit: zm.visitproc, arg: ?*anyopaque) callconv(.c) c_int {
            const ptr = Cell.ptrFromObj(self_obj);
            inline for (std.meta.fields(T)) |f| {
                if (f.type == ?*zm.PyObject) {
                    if (@field(ptr, f.name)) |o| {
                        const r = visit(o, arg);
                        if (r != 0) return r;
                    }
                }
            }
            return 0;
        }
        fn clear(self_obj: ?*zm.PyObject) callconv(.c) c_int {
            releaseFields(T, self_obj);
            return 0;
        }
    };

    const has_properties = @hasField(@TypeOf(config), "properties");

    const TypeBuilder = struct {
        fn getTypeObject() ?*zm.PyObject {
            const fields = comptime std.meta.fields(T);
            const field_count = fields.len;
            const prop_count = if (has_properties) config.properties.len else 0;
            const defs_count = field_count + prop_count + 1;

            const getset_ptr = zm.PyMem_RawMalloc(@sizeOf(zm.PyGetSetDef) * defs_count);
            if (getset_ptr == null) {
                zm.PyErr_SetString(zm.PyExc_MemoryError(), "out of memory");
                return null;
            }
            const getset_defs = @as([*]zm.PyGetSetDef, @ptrCast(@alignCast(getset_ptr.?)));
            @memset(getset_defs[0..defs_count], .{
                .name = null, .get = null, .set = null, .doc = null, .closure = null,
            });

            inline for (fields, 0..) |field, i| {
                const is_pyobj_field = field.type == ?*zm.PyObject;
                const FieldWrapper = struct {
                    fn getter(obj: ?*zm.PyObject, _: ?*anyopaque) callconv(.c) ?*zm.PyObject {
                        const ptr = Cell.ptrFromObj(obj);
                        const val = @field(ptr, field.name);
                        // A getset getter returns a new reference. For a stored
                        // PyObject the instance only holds a borrow's worth, so
                        // hand out a fresh reference (None if null).
                        if (comptime is_pyobj_field) {
                            return zm.Py_NewRef(val orelse zm.Py_None());
                        }
                        return conversion.toPyObject(val) catch |err| {
                            funcwrap.setConversionError(err);
                            return null;
                        };
                    }
                    fn setter(obj: ?*zm.PyObject, val: ?*zm.PyObject, _: ?*anyopaque) callconv(.c) c_int {
                        const ptr = Cell.ptrFromObj(obj);
                        // PyObject fields are framework-owned: incref the new
                        // value, decref the old. (GC traverse/clear rely on this.)
                        if (comptime is_pyobj_field) {
                            const old = @field(ptr, field.name);
                            @field(ptr, field.name) = zm.Py_XNewRef(val);
                            zm.Py_XDECREF(old);
                            return 0;
                        }
                        // Fields are stored permanently, so a per-call arena
                        // would dangle; scalars don't allocate. Container-typed
                        // settable fields are not supported.
                        const converted = conversion.fromPyObject(field.type, val, std.heap.c_allocator) catch {
                            zm.PyErr_SetString(zm.PyExc_TypeError(), "type mismatch for field");
                            return -1;
                        };
                        @field(ptr, field.name) = converted;
                        return 0;
                    }
                };

                const field_name = @as([*:0]const u8, @ptrCast(field.name.ptr));
                const is_readonly = comptime (has_readonly and blk: {
                    for (config.readonly) |ro| {
                        if (std.mem.eql(u8, ro, field.name)) break :blk true;
                    }
                    break :blk false;
                });
                getset_defs[i] = .{
                    .name = field_name,
                    .get = &FieldWrapper.getter,
                    .set = if (is_readonly) null else &FieldWrapper.setter,
                    .doc = null,
                    .closure = null,
                };
            }

            // Computed properties: .properties = &.{ .{ .name="area", .get=fn, .set=fn? } }
            if (has_properties) {
                inline for (config.properties, 0..) |prop, j| {
                    const has_set = @hasField(@TypeOf(prop), "set");
                    const PropWrapper = struct {
                        const SetCtx = struct { obj: ?*zm.PyObject, val: ?*zm.PyObject };
                        fn getInner(obj: ?*zm.PyObject) ?*zm.PyObject {
                            const ptr = Cell.ptrFromObj(obj);
                            const gi = @typeInfo(@TypeOf(prop.get)).@"fn";
                            return callFuncReturningPyObject(prop.get, gi, .{ptr});
                        }
                        fn getThunk(p: ?*anyopaque) callconv(.c) ?*zm.PyObject {
                            return getInner(@as(?*zm.PyObject, @ptrCast(@alignCast(p))));
                        }
                        fn getter(obj: ?*zm.PyObject, _: ?*anyopaque) callconv(.c) ?*zm.PyObject {
                            return zm.pz_guard(&getThunk, @ptrCast(obj));
                        }
                        fn setInner(obj: ?*zm.PyObject, val: ?*zm.PyObject) c_int {
                            const ptr = Cell.ptrFromObj(obj);
                            const set_params = @typeInfo(@TypeOf(prop.set)).@"fn".params;
                            const ValT = set_params[1].type.?;
                            const converted = conversion.fromPyObject(ValT, val, std.heap.c_allocator) catch {
                                zm.PyErr_SetString(zm.PyExc_TypeError(), "type mismatch for property");
                                return -1;
                            };
                            prop.set(ptr, converted);
                            return 0;
                        }
                        fn setThunk(p: ?*anyopaque) callconv(.c) c_int {
                            const c = @as(*SetCtx, @ptrCast(@alignCast(p)));
                            return setInner(c.obj, c.val);
                        }
                        fn setter(obj: ?*zm.PyObject, val: ?*zm.PyObject, _: ?*anyopaque) callconv(.c) c_int {
                            var ctx = SetCtx{ .obj = obj, .val = val };
                            return zm.pz_guard_int(&setThunk, &ctx);
                        }
                    };
                    getset_defs[field_count + j] = .{
                        .name = @as([*:0]const u8, @ptrCast(prop.name.ptr)),
                        .get = &PropWrapper.getter,
                        .set = if (has_set) &PropWrapper.setter else null,
                        .doc = null,
                        .closure = null,
                    };
                }
            }

            // Auto-registered plain methods: dunders that CPython looks up by
            // name (not via a type slot) — context manager, pickle, copy,
            // formatting, bytes(), the math.* hooks, reversed(). __enter__ is
            // special (it may return void -> self), the rest are wrapped as-is.
            const auto_methods = comptime blk: {
                var arr: []const zm.PyMethodDef = &.{};
                if (has_enter) arr = arr ++ &[_]zm.PyMethodDef{.{
                    .ml_name = @as(?[*:0]const u8, "__enter__"),
                    .ml_meth = &EnterWrapper.meth,
                    .ml_flags = zm.METH_VARARGS,
                    .ml_doc = null,
                }};
                // (Hooks returning the class's own type aren't here: a plain
                // method converts a returned struct to a dict, not an instance —
                // so __copy__/__deepcopy__ would misbehave and are omitted.)
                const plain_dunders = .{
                    "__exit__",   "__reduce__", "__reversed__",  "__format__",
                    "__bytes__",  "__trunc__",  "__floor__",     "__ceil__",
                    "__round__",  "__getstate__", "__setstate__",
                };
                for (plain_dunders) |dn| {
                    if (@hasDecl(T, dn)) arr = arr ++ &[_]zm.PyMethodDef{wrapMethodNamed(T, dn, @field(T, dn))};
                }
                if (has_copy) arr = arr ++ &[_]zm.PyMethodDef{.{
                    .ml_name = @as(?[*:0]const u8, "__copy__"),
                    .ml_meth = &CopyWrapper.meth,
                    .ml_flags = zm.METH_VARARGS,
                    .ml_doc = null,
                }};
                if (has_deepcopy) arr = arr ++ &[_]zm.PyMethodDef{.{
                    .ml_name = @as(?[*:0]const u8, "__deepcopy__"),
                    .ml_meth = &DeepCopyWrapper.meth,
                    .ml_flags = zm.METH_VARARGS,
                    .ml_doc = null,
                }};
                break :blk arr;
            };
            const has_any_method = has_methods or auto_methods.len > 0;

            var method_defs: []zm.PyMethodDef = &.{};
            if (has_any_method) {
                const cfg_methods: []const zm.PyMethodDef = if (has_methods) config.methods else &.{};
                const method_count = cfg_methods.len + auto_methods.len + 1;
                method_defs = std.heap.c_allocator.alloc(zm.PyMethodDef, method_count) catch {
                    zm.PyErr_SetString(zm.PyExc_MemoryError(), "out of memory");
                    zm.PyMem_RawFree(getset_ptr);
                    return null;
                };
                var midx: usize = 0;
                for (cfg_methods) |m| {
                    method_defs[midx] = m;
                    midx += 1;
                }
                inline for (auto_methods) |m| {
                    method_defs[midx] = m;
                    midx += 1;
                }
                method_defs[method_count - 1] = .{ .ml_name = null, .ml_meth = null, .ml_flags = 0, .ml_doc = null };
            }

            comptime var slot_count: usize = 3; // dealloc(optional) handled below
            if (needs_custom_dealloc) slot_count += 1;
            if (has_any_method) slot_count += 1;
            if (has_str) slot_count += 1;
            if (has_repr) slot_count += 1;
            if (has_hash) slot_count += 1;
            if (auto_unhashable) slot_count += 1;
            if (has_richcompare) slot_count += 1;
            if (has_len) slot_count += 1;
            if (has_getitem) slot_count += 1;
            if (has_assitem) slot_count += 1;
            if (has_contains) slot_count += 1;
            if (has_next) slot_count += 1;
            if (has_iter) slot_count += 1;
            if (has_call) slot_count += 1;
            if (has_doc) slot_count += 1;
            if (has_add) slot_count += 1;
            if (has_sub) slot_count += 1;
            if (has_mul) slot_count += 1;
            if (has_truediv) slot_count += 1;
            if (has_floordiv) slot_count += 1;
            if (has_mod) slot_count += 1;
            if (has_pow) slot_count += 1;
            if (has_matmul) slot_count += 1;
            if (has_neg) slot_count += 1;
            if (has_bool) slot_count += 1;
            if (has_int) slot_count += 1;
            if (has_float_conv) slot_count += 1;
            if (has_index) slot_count += 1;
            if (has_iadd) slot_count += 1;
            if (has_isub) slot_count += 1;
            if (has_imul) slot_count += 1;
            if (has_abs) slot_count += 1;
            if (has_pos) slot_count += 1;
            if (has_invert) slot_count += 1;
            if (has_and) slot_count += 1;
            if (has_or) slot_count += 1;
            if (has_xor) slot_count += 1;
            if (has_lshift) slot_count += 1;
            if (has_rshift) slot_count += 1;
            if (has_divmod) slot_count += 1;
            if (has_itruediv) slot_count += 1;
            if (has_ifloordiv) slot_count += 1;
            if (has_imod) slot_count += 1;
            if (has_ipow) slot_count += 1;
            if (has_imatmul) slot_count += 1;
            if (has_iand) slot_count += 1;
            if (has_ior) slot_count += 1;
            if (has_ixor) slot_count += 1;
            if (has_ilshift) slot_count += 1;
            if (has_irshift) slot_count += 1;
            if (has_getattr) slot_count += 1;
            if (has_setattr) slot_count += 1;
            if (has_buffer) slot_count += 1;
            if (is_gc) slot_count += 2; // tp_traverse + tp_clear

            var slots: [slot_count]zm.PyType_Slot = undefined;
            var slot_idx: usize = 0;
            // tp_dealloc only when we must run __deinit__ or release fields;
            // omitting it lets CPython's default dealloc make the type
            // subclassable from Python.
            if (needs_custom_dealloc) {
                slots[slot_idx] = .{ .slot = zm.Py_tp_dealloc, .pfunc = @constCast(@as(*const anyopaque, @ptrCast(&DeallocWrapper.dealloc))) };
                slot_idx += 1;
            }
            slots[slot_idx] = .{ .slot = zm.Py_tp_new, .pfunc = @constCast(@as(*const anyopaque, @ptrCast(&NewWrapper.new))) };
            slot_idx += 1;
            slots[slot_idx] = .{ .slot = zm.Py_tp_getset, .pfunc = @as(?*anyopaque, @ptrCast(getset_defs)) };
            slot_idx += 1;
            if (has_any_method) {
                slots[slot_idx] = .{ .slot = zm.Py_tp_methods, .pfunc = @as(?*anyopaque, @ptrCast(method_defs.ptr)) };
                slot_idx += 1;
            }
            if (has_str) {
                slots[slot_idx] = .{ .slot = zm.Py_tp_str, .pfunc = @constCast(@as(*const anyopaque, @ptrCast(&StrWrapper.str))) };
                slot_idx += 1;
            }
            if (has_repr) {
                slots[slot_idx] = .{ .slot = zm.Py_tp_repr, .pfunc = @constCast(@as(*const anyopaque, @ptrCast(&ReprWrapper.repr))) };
                slot_idx += 1;
            }
            if (has_hash) {
                slots[slot_idx] = .{ .slot = zm.Py_tp_hash, .pfunc = @constCast(@as(*const anyopaque, @ptrCast(&HashWrapper.hash))) };
                slot_idx += 1;
            }
            if (auto_unhashable) {
                // CPython recognizes this exact pointer and exposes __hash__ as
                // None (matching a Python class with __eq__ and no __hash__).
                slots[slot_idx] = .{ .slot = zm.Py_tp_hash, .pfunc = zm.HashNotImplemented() };
                slot_idx += 1;
            }
            if (has_richcompare) {
                slots[slot_idx] = .{ .slot = zm.Py_tp_richcompare, .pfunc = @constCast(@as(*const anyopaque, @ptrCast(&RichcompareWrapper.richcompare))) };
                slot_idx += 1;
            }
            if (has_len) {
                slots[slot_idx] = .{ .slot = zm.Py_sq_length, .pfunc = @constCast(@as(*const anyopaque, @ptrCast(&LenWrapper.len))) };
                slot_idx += 1;
            }
            if (has_getitem) {
                slots[slot_idx] = .{ .slot = zm.Py_mp_subscript, .pfunc = @constCast(@as(*const anyopaque, @ptrCast(&GetItemWrapper.getitem))) };
                slot_idx += 1;
            }
            if (has_assitem) {
                slots[slot_idx] = .{ .slot = zm.Py_mp_ass_subscript, .pfunc = @constCast(@as(*const anyopaque, @ptrCast(&SetItemWrapper.setitem))) };
                slot_idx += 1;
            }
            if (has_contains) {
                slots[slot_idx] = .{ .slot = zm.Py_sq_contains, .pfunc = @constCast(@as(*const anyopaque, @ptrCast(&ContainsWrapper.contains))) };
                slot_idx += 1;
            }
            if (has_iter) {
                slots[slot_idx] = .{ .slot = zm.Py_tp_iter, .pfunc = @constCast(@as(*const anyopaque, @ptrCast(&IterWrapper.iter))) };
                slot_idx += 1;
            }
            if (has_next) {
                slots[slot_idx] = .{ .slot = zm.Py_tp_iternext, .pfunc = @constCast(@as(*const anyopaque, @ptrCast(&NextWrapper.iternext))) };
                slot_idx += 1;
            }
            if (has_call) {
                slots[slot_idx] = .{ .slot = zm.Py_tp_call, .pfunc = @constCast(@as(*const anyopaque, @ptrCast(&CallWrapper.call))) };
                slot_idx += 1;
            }
            if (has_doc) {
                const doc_z: [:0]const u8 = config.doc;
                slots[slot_idx] = .{ .slot = zm.Py_tp_doc, .pfunc = @constCast(@as(*const anyopaque, @ptrCast(doc_z.ptr))) };
                slot_idx += 1;
            }
            if (has_add) {
                slots[slot_idx] = .{ .slot = zm.Py_nb_add, .pfunc = @constCast(@as(*const anyopaque, @ptrCast(&AddWrapper.op))) };
                slot_idx += 1;
            }
            if (has_sub) {
                slots[slot_idx] = .{ .slot = zm.Py_nb_subtract, .pfunc = @constCast(@as(*const anyopaque, @ptrCast(&SubWrapper.op))) };
                slot_idx += 1;
            }
            if (has_mul) {
                slots[slot_idx] = .{ .slot = zm.Py_nb_multiply, .pfunc = @constCast(@as(*const anyopaque, @ptrCast(&MulWrapper.op))) };
                slot_idx += 1;
            }
            if (has_truediv) {
                slots[slot_idx] = .{ .slot = zm.Py_nb_true_divide, .pfunc = @constCast(@as(*const anyopaque, @ptrCast(&TrueDivWrapper.op))) };
                slot_idx += 1;
            }
            if (has_floordiv) {
                slots[slot_idx] = .{ .slot = zm.Py_nb_floor_divide, .pfunc = @constCast(@as(*const anyopaque, @ptrCast(&FloorDivWrapper.op))) };
                slot_idx += 1;
            }
            if (has_mod) {
                slots[slot_idx] = .{ .slot = zm.Py_nb_remainder, .pfunc = @constCast(@as(*const anyopaque, @ptrCast(&ModWrapper.op))) };
                slot_idx += 1;
            }
            if (has_pow) {
                slots[slot_idx] = .{ .slot = zm.Py_nb_power, .pfunc = @constCast(@as(*const anyopaque, @ptrCast(&PowWrapper.powop))) };
                slot_idx += 1;
            }
            if (has_matmul) {
                slots[slot_idx] = .{ .slot = zm.Py_nb_matrix_multiply, .pfunc = @constCast(@as(*const anyopaque, @ptrCast(&MatMulWrapper.op))) };
                slot_idx += 1;
            }
            if (has_neg) {
                slots[slot_idx] = .{ .slot = zm.Py_nb_negative, .pfunc = @constCast(@as(*const anyopaque, @ptrCast(&NegWrapper.op))) };
                slot_idx += 1;
            }
            if (has_bool) {
                slots[slot_idx] = .{ .slot = zm.Py_nb_bool, .pfunc = @constCast(@as(*const anyopaque, @ptrCast(&BoolWrapper.op))) };
                slot_idx += 1;
            }
            if (has_int) {
                slots[slot_idx] = .{ .slot = zm.Py_nb_int, .pfunc = @constCast(@as(*const anyopaque, @ptrCast(&IntWrapper.op))) };
                slot_idx += 1;
            }
            if (has_float_conv) {
                slots[slot_idx] = .{ .slot = zm.Py_nb_float, .pfunc = @constCast(@as(*const anyopaque, @ptrCast(&FloatWrapper.op))) };
                slot_idx += 1;
            }
            if (has_index) {
                slots[slot_idx] = .{ .slot = zm.Py_nb_index, .pfunc = @constCast(@as(*const anyopaque, @ptrCast(&IndexWrapper.op))) };
                slot_idx += 1;
            }
            if (has_iadd) {
                slots[slot_idx] = .{ .slot = zm.Py_nb_inplace_add, .pfunc = @constCast(@as(*const anyopaque, @ptrCast(&IaddWrapper.op))) };
                slot_idx += 1;
            }
            if (has_isub) {
                slots[slot_idx] = .{ .slot = zm.Py_nb_inplace_subtract, .pfunc = @constCast(@as(*const anyopaque, @ptrCast(&IsubWrapper.op))) };
                slot_idx += 1;
            }
            if (has_imul) {
                slots[slot_idx] = .{ .slot = zm.Py_nb_inplace_multiply, .pfunc = @constCast(@as(*const anyopaque, @ptrCast(&ImulWrapper.op))) };
                slot_idx += 1;
            }
            if (has_abs) {
                slots[slot_idx] = .{ .slot = zm.Py_nb_absolute, .pfunc = @constCast(@as(*const anyopaque, @ptrCast(&AbsWrapper.op))) };
                slot_idx += 1;
            }
            if (has_pos) {
                slots[slot_idx] = .{ .slot = zm.Py_nb_positive, .pfunc = @constCast(@as(*const anyopaque, @ptrCast(&PosWrapper.op))) };
                slot_idx += 1;
            }
            if (has_invert) {
                slots[slot_idx] = .{ .slot = zm.Py_nb_invert, .pfunc = @constCast(@as(*const anyopaque, @ptrCast(&InvertWrapper.op))) };
                slot_idx += 1;
            }
            if (has_and) {
                slots[slot_idx] = .{ .slot = zm.Py_nb_and, .pfunc = @constCast(@as(*const anyopaque, @ptrCast(&AndWrapper.op))) };
                slot_idx += 1;
            }
            if (has_or) {
                slots[slot_idx] = .{ .slot = zm.Py_nb_or, .pfunc = @constCast(@as(*const anyopaque, @ptrCast(&OrWrapper.op))) };
                slot_idx += 1;
            }
            if (has_xor) {
                slots[slot_idx] = .{ .slot = zm.Py_nb_xor, .pfunc = @constCast(@as(*const anyopaque, @ptrCast(&XorWrapper.op))) };
                slot_idx += 1;
            }
            if (has_lshift) {
                slots[slot_idx] = .{ .slot = zm.Py_nb_lshift, .pfunc = @constCast(@as(*const anyopaque, @ptrCast(&LshiftWrapper.op))) };
                slot_idx += 1;
            }
            if (has_rshift) {
                slots[slot_idx] = .{ .slot = zm.Py_nb_rshift, .pfunc = @constCast(@as(*const anyopaque, @ptrCast(&RshiftWrapper.op))) };
                slot_idx += 1;
            }
            if (has_divmod) {
                slots[slot_idx] = .{ .slot = zm.Py_nb_divmod, .pfunc = @constCast(@as(*const anyopaque, @ptrCast(&DivmodWrapper.op))) };
                slot_idx += 1;
            }
            if (has_itruediv) {
                slots[slot_idx] = .{ .slot = zm.Py_nb_inplace_true_divide, .pfunc = @constCast(@as(*const anyopaque, @ptrCast(&ItruedivWrapper.op))) };
                slot_idx += 1;
            }
            if (has_ifloordiv) {
                slots[slot_idx] = .{ .slot = zm.Py_nb_inplace_floor_divide, .pfunc = @constCast(@as(*const anyopaque, @ptrCast(&IfloordivWrapper.op))) };
                slot_idx += 1;
            }
            if (has_imod) {
                slots[slot_idx] = .{ .slot = zm.Py_nb_inplace_remainder, .pfunc = @constCast(@as(*const anyopaque, @ptrCast(&ImodWrapper.op))) };
                slot_idx += 1;
            }
            if (has_ipow) {
                slots[slot_idx] = .{ .slot = zm.Py_nb_inplace_power, .pfunc = @constCast(@as(*const anyopaque, @ptrCast(&IpowWrapper.powop))) };
                slot_idx += 1;
            }
            if (has_imatmul) {
                slots[slot_idx] = .{ .slot = zm.Py_nb_inplace_matrix_multiply, .pfunc = @constCast(@as(*const anyopaque, @ptrCast(&ImatmulWrapper.op))) };
                slot_idx += 1;
            }
            if (has_iand) {
                slots[slot_idx] = .{ .slot = zm.Py_nb_inplace_and, .pfunc = @constCast(@as(*const anyopaque, @ptrCast(&IandWrapper.op))) };
                slot_idx += 1;
            }
            if (has_ior) {
                slots[slot_idx] = .{ .slot = zm.Py_nb_inplace_or, .pfunc = @constCast(@as(*const anyopaque, @ptrCast(&IorWrapper.op))) };
                slot_idx += 1;
            }
            if (has_ixor) {
                slots[slot_idx] = .{ .slot = zm.Py_nb_inplace_xor, .pfunc = @constCast(@as(*const anyopaque, @ptrCast(&IxorWrapper.op))) };
                slot_idx += 1;
            }
            if (has_ilshift) {
                slots[slot_idx] = .{ .slot = zm.Py_nb_inplace_lshift, .pfunc = @constCast(@as(*const anyopaque, @ptrCast(&IlshiftWrapper.op))) };
                slot_idx += 1;
            }
            if (has_irshift) {
                slots[slot_idx] = .{ .slot = zm.Py_nb_inplace_rshift, .pfunc = @constCast(@as(*const anyopaque, @ptrCast(&IrshiftWrapper.op))) };
                slot_idx += 1;
            }
            if (has_getattr) {
                slots[slot_idx] = .{ .slot = zm.Py_tp_getattro, .pfunc = @constCast(@as(*const anyopaque, @ptrCast(&GetAttrWrapper.getattro))) };
                slot_idx += 1;
            }
            if (has_setattr) {
                slots[slot_idx] = .{ .slot = zm.Py_tp_setattro, .pfunc = @constCast(@as(*const anyopaque, @ptrCast(&SetAttrWrapper.setattro))) };
                slot_idx += 1;
            }
            if (has_buffer) {
                slots[slot_idx] = .{ .slot = zm.Py_bf_getbuffer, .pfunc = @constCast(@as(*const anyopaque, @ptrCast(&BufferWrapper.getbuffer))) };
                slot_idx += 1;
            }
            if (is_gc) {
                slots[slot_idx] = .{ .slot = zm.Py_tp_traverse, .pfunc = @constCast(@as(*const anyopaque, @ptrCast(&GcWrapper.traverse))) };
                slot_idx += 1;
                slots[slot_idx] = .{ .slot = zm.Py_tp_clear, .pfunc = @constCast(@as(*const anyopaque, @ptrCast(&GcWrapper.clear))) };
                slot_idx += 1;
            }
            slots[slot_idx] = .{ .slot = 0, .pfunc = null };

            // HAVE_GC is required when the type provides tp_traverse/tp_clear.
            // BASETYPE lets Python subclass the type; only safe when CPython's
            // default dealloc handles teardown (no custom dealloc of ours).
            var flags = zm.Py_TPFLAGS_DEFAULT | zm.Py_TPFLAGS_HEAPTYPE;
            if (is_gc) flags |= zm.Py_TPFLAGS_HAVE_GC;
            if (can_subclass) flags |= zm.Py_TPFLAGS_BASETYPE;
            // Managed weakref support: instances can be the target of
            // weakref.ref(obj). The weaklist lives in CPython's managed
            // pre-header, which only exists for GC types — so this is gated on
            // HAVE_GC. A custom dealloc clears it via PyObject_ClearWeakRefs.
            if (is_gc) flags |= zm.Py_TPFLAGS_MANAGED_WEAKREF;

            var spec = zm.PyType_Spec{
                .name = type_name,
                .basicsize = @as(c_int, @intCast(Cell.allocSize())),
                .itemsize = 0,
                .flags = flags,
                .slots = &slots,
            };

            const result = zm.PyType_FromSpec(&spec);
            TypeRef.obj = result;
            return result;
        }
    };

    return struct {
        pub const pycell = Cell;
        pub fn py_type_obj() ?*zm.PyObject {
            return TypeBuilder.getTypeObject();
        }
        pub fn class_name() [*:0]const u8 {
            return type_name;
        }
    };
}
