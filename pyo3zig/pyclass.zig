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

const METH_STATIC: c_int = 0x20;

/// A static method (no `self`, no instance) on a class. Register it in the
/// class's `.methods` list.
pub fn staticMethod(comptime name: [:0]const u8, comptime func: anytype) zm.PyMethodDef {
    var def = funcwrap.wrap(func, name, "");
    def.ml_flags |= METH_STATIC;
    return def;
}

pub fn PyClass(comptime T: type, comptime config: anytype) type {
    const Cell = pycell.PyCell(T);
    const type_name = buildTypeName(T);
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

    const DeallocWrapper = struct {
        fn dealloc(obj: ?*zm.PyObject) callconv(.c) void {
            if (obj) |o| {
                const header = @as(*zm.PyObjectHeader, @ptrCast(@alignCast(o)));
                const ty = @as(?*zm.PyObject, @ptrCast(@alignCast(header.ob_type)));
                if (@hasDecl(T, "__deinit__")) {
                    const ptr = Cell.ptrFromObj(o);
                    ptr.__deinit__();
                }
                zm.PyMem_RawFree(@as(?*anyopaque, @ptrCast(o)));
                // Heap types are reference-counted; release the type ref taken
                // in NewWrapper.new.
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

        fn newInner(ty: ?*zm.PyObject, args: ?*zm.PyObject, kwargs: ?*zm.PyObject) ?*zm.PyObject {
            if (!has_init_args and kwargs != null and zm.PyDict_Size(kwargs) > 0) {
                zm.PyErr_SetString(zm.PyExc_TypeError(), "keyword arguments not supported for init");
                return null;
            }
            const alloc = zm.PyMem_RawMalloc(Cell.allocSize());
            if (alloc == null) {
                zm.PyErr_SetString(zm.PyExc_MemoryError(), "out of memory");
                return null;
            }
            const obj = @as(?*zm.PyObject, @ptrCast(@alignCast(alloc)));
            const header = @as(*zm.PyObjectHeader, @ptrCast(@alignCast(alloc)));
            header.ob_refcnt = 1;
            header.ob_type = @as(?*anyopaque, @ptrCast(ty));
            // Instances of a heap type hold a reference to the type object.
            zm.Py_XINCREF(ty);

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
                            zm.PyMem_RawFree(alloc);
                            return null;
                        };
                    } else {
                        const actual: isize = if (args) |a| zm.PyTuple_Size(a) else 0;
                        if (actual != @as(isize, @intCast(params.len))) {
                            zm.PyErr_SetString(zm.PyExc_TypeError(), "wrong number of arguments for init");
                            zm.PyMem_RawFree(alloc);
                            return null;
                        }
                        var ia: funcwrap.paramTypesTupleDirect(params) = undefined;
                        inline for (params, 0..) |param, i| {
                            const arg_obj = zm.PyTuple_GetItem(args, @as(isize, @intCast(i)));
                            ia[i] = conversion.fromPyObject(param.type.?, arg_obj, arg_alloc) catch {
                                zm.PyErr_SetString(zm.PyExc_TypeError(), "init argument conversion failed");
                                zm.PyMem_RawFree(alloc);
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
                        zm.PyMem_RawFree(alloc);
                        return null;
                    };
                } else {
                    ptr.* = @call(.auto, init_fn, init_args);
                }
            }

            return obj;
        }
    };

    const StrWrapper = struct {
        fn str(self_obj: ?*zm.PyObject) callconv(.c) ?*zm.PyObject {
            const ptr = Cell.ptrFromObj(self_obj);
            const FuncType = @TypeOf(T.__str__);
            const fn_info = @typeInfo(FuncType).@"fn";
            return callFuncReturningPyObject(T.__str__, fn_info, .{ptr});
        }
    };

    const ReprWrapper = struct {
        fn repr(self_obj: ?*zm.PyObject) callconv(.c) ?*zm.PyObject {
            const ptr = Cell.ptrFromObj(self_obj);
            const FuncType = @TypeOf(T.__repr__);
            const fn_info = @typeInfo(FuncType).@"fn";
            return callFuncReturningPyObject(T.__repr__, fn_info, .{ptr});
        }
    };

    const HashWrapper = struct {
        fn hash(self_obj: ?*zm.PyObject) callconv(.c) isize {
            const ptr = Cell.ptrFromObj(self_obj);
            const result = @as(isize, @intCast(T.__hash__(ptr)));
            // -1 is CPython's error sentinel; remap to a valid hash.
            return if (result == -1) -2 else result;
        }
    };

    const RichcompareWrapper = struct {
        // CPython richcompare op codes.
        const Py_EQ: c_int = 2;
        const Py_NE: c_int = 3;

        fn richcompare(self_obj: ?*zm.PyObject, other_obj: ?*zm.PyObject, op: c_int) callconv(.c) ?*zm.PyObject {
            // Only equality is derivable from __eq__; other orderings are
            // unsupported unless the user provides them.
            if (op != Py_EQ and op != Py_NE) return zm.Py_NewRef(zm.Py_NotImplemented());
            if (other_obj == null) return zm.Py_NewRef(zm.Py_NotImplemented());
            const hdr_self = @as(*zm.PyObjectHeader, @ptrCast(@alignCast(self_obj)));
            const hdr_other = @as(*zm.PyObjectHeader, @ptrCast(@alignCast(other_obj)));
            if (hdr_self.ob_type != hdr_other.ob_type) return zm.Py_NewRef(zm.Py_NotImplemented());
            const self_ptr = Cell.ptrFromObj(self_obj);
            const other_ptr = Cell.ptrFromObj(other_obj);
            const eq = T.__eq__(self_ptr, other_ptr);
            const result = if (op == Py_EQ) eq else !eq;
            if (result) return zm.Py_NewRef(zm.Py_True());
            return zm.Py_NewRef(zm.Py_False());
        }
    };

    const LenWrapper = struct {
        fn len(self_obj: ?*zm.PyObject) callconv(.c) isize {
            const ptr = Cell.ptrFromObj(self_obj);
            return @as(isize, @intCast(T.__len__(ptr)));
        }
    };

    const GetItemWrapper = struct {
        fn getitem(self_obj: ?*zm.PyObject, key_obj: ?*zm.PyObject) callconv(.c) ?*zm.PyObject {
            const ptr = Cell.ptrFromObj(self_obj);
            const fn_info = @typeInfo(@TypeOf(T.__getitem__)).@"fn";
            var arena = std.heap.ArenaAllocator.init(std.heap.c_allocator);
            defer arena.deinit();
            const key = conversion.fromPyObject(fn_info.params[1].type.?, key_obj, arena.allocator()) catch |err| {
                funcwrap.setConversionError(err);
                return null;
            };
            return callFuncReturningPyObject(T.__getitem__, fn_info, .{ ptr, key });
        }
    };

    const SetItemWrapper = struct {
        fn setitem(self_obj: ?*zm.PyObject, key_obj: ?*zm.PyObject, val_obj: ?*zm.PyObject) callconv(.c) c_int {
            const ptr = Cell.ptrFromObj(self_obj);
            if (val_obj == null) {
                zm.PyErr_SetString(zm.PyExc_TypeError(), "item deletion not supported");
                return -1;
            }
            const fn_info = @typeInfo(@TypeOf(T.__setitem__)).@"fn";
            var arena = std.heap.ArenaAllocator.init(std.heap.c_allocator);
            defer arena.deinit();
            const a = arena.allocator();
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
    };

    const ContainsWrapper = struct {
        fn contains(self_obj: ?*zm.PyObject, item_obj: ?*zm.PyObject) callconv(.c) c_int {
            const ptr = Cell.ptrFromObj(self_obj);
            const fn_info = @typeInfo(@TypeOf(T.__contains__)).@"fn";
            var arena = std.heap.ArenaAllocator.init(std.heap.c_allocator);
            defer arena.deinit();
            const item = conversion.fromPyObject(fn_info.params[1].type.?, item_obj, arena.allocator()) catch {
                return -1;
            };
            return if (T.__contains__(ptr, item)) 1 else 0;
        }
    };

    const NextWrapper = struct {
        fn iternext(self_obj: ?*zm.PyObject) callconv(.c) ?*zm.PyObject {
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
    };

    const IterWrapper = struct {
        fn iter(self_obj: ?*zm.PyObject) callconv(.c) ?*zm.PyObject {
            if (@hasDecl(T, "__iter__")) {
                const ptr = Cell.ptrFromObj(self_obj);
                const fn_info = @typeInfo(@TypeOf(T.__iter__)).@"fn";
                return callFuncReturningPyObject(T.__iter__, fn_info, .{ptr});
            }
            // Self-iterator: a type with __next__ is its own iterator.
            return zm.Py_NewRef(self_obj);
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
                const FieldWrapper = struct {
                    fn getter(obj: ?*zm.PyObject, _: ?*anyopaque) callconv(.c) ?*zm.PyObject {
                        const ptr = Cell.ptrFromObj(obj);
                        const val = @field(ptr, field.name);
                        return conversion.toPyObject(val) catch |err| {
                            funcwrap.setConversionError(err);
                            return null;
                        };
                    }
                    fn setter(obj: ?*zm.PyObject, val: ?*zm.PyObject, _: ?*anyopaque) callconv(.c) c_int {
                        const ptr = Cell.ptrFromObj(obj);
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
                        fn getter(obj: ?*zm.PyObject, _: ?*anyopaque) callconv(.c) ?*zm.PyObject {
                            const ptr = Cell.ptrFromObj(obj);
                            const gi = @typeInfo(@TypeOf(prop.get)).@"fn";
                            return callFuncReturningPyObject(prop.get, gi, .{ptr});
                        }
                        fn setter(obj: ?*zm.PyObject, val: ?*zm.PyObject, _: ?*anyopaque) callconv(.c) c_int {
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

            var method_defs: []zm.PyMethodDef = &.{};
            if (has_methods) {
                const methods = config.methods;
                const method_count = methods.len + 1;
                method_defs = std.heap.c_allocator.alloc(zm.PyMethodDef, method_count) catch {
                    zm.PyErr_SetString(zm.PyExc_MemoryError(), "out of memory");
                    zm.PyMem_RawFree(getset_ptr);
                    return null;
                };
                for (methods, 0..) |m, i| {
                    method_defs[i] = m;
                }
                method_defs[method_count - 1] = .{ .ml_name = null, .ml_meth = null, .ml_flags = 0, .ml_doc = null };
            }

            comptime var slot_count: usize = 4;
            if (has_methods) slot_count += 1;
            if (has_str) slot_count += 1;
            if (has_repr) slot_count += 1;
            if (has_hash) slot_count += 1;
            if (has_eq) slot_count += 1;
            if (has_len) slot_count += 1;
            if (has_getitem) slot_count += 1;
            if (has_setitem) slot_count += 1;
            if (has_contains) slot_count += 1;
            if (has_next) slot_count += 1;
            if (has_iter) slot_count += 1;

            var slots: [slot_count]zm.PyType_Slot = undefined;
            var slot_idx: usize = 0;
            slots[slot_idx] = .{ .slot = zm.Py_tp_dealloc, .pfunc = @constCast(@as(*const anyopaque, @ptrCast(&DeallocWrapper.dealloc))) };
            slot_idx += 1;
            slots[slot_idx] = .{ .slot = zm.Py_tp_new, .pfunc = @constCast(@as(*const anyopaque, @ptrCast(&NewWrapper.new))) };
            slot_idx += 1;
            slots[slot_idx] = .{ .slot = zm.Py_tp_getset, .pfunc = @as(?*anyopaque, @ptrCast(getset_defs)) };
            slot_idx += 1;
            if (has_methods) {
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
            if (has_eq) {
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
            if (has_setitem) {
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
            slots[slot_idx] = .{ .slot = 0, .pfunc = null };

            var spec = zm.PyType_Spec{
                .name = type_name,
                .basicsize = @as(c_int, @intCast(Cell.allocSize())),
                .itemsize = 0,
                .flags = zm.Py_TPFLAGS_DEFAULT | zm.Py_TPFLAGS_HEAPTYPE,
                .slots = &slots,
            };

            const result = zm.PyType_FromSpec(&spec);
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
