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
                errors.setPyException(err);
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
        pub fn trampoline(self_obj: ?*zm.PyObject, args_obj: ?*zm.PyObject) callconv(.c) ?*zm.PyObject {
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

                inline for (method_params, 0..) |param, i| {
                    const ParamT = param.type.?;
                    const arg_obj = zm.PyTuple_GetItem(args, @as(isize, @intCast(i)));
                    call_args[i] = conversion.fromPyObject(ParamT, arg_obj) catch |err| {
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
                            errors.setPyException(err);
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

pub fn PyClass(comptime T: type, comptime config: anytype) type {
    const Cell = pycell.PyCell(T);
    const type_name = buildTypeName(T);
    const has_methods = @hasField(@TypeOf(config), "methods");
    const has_readonly = @hasField(@TypeOf(config), "readonly");
    const has_str = @hasDecl(T, "__str__");
    const has_repr = @hasDecl(T, "__repr__");
    const has_hash = @hasDecl(T, "__hash__");
    const has_eq = @hasDecl(T, "__eq__");

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
        fn new(ty: ?*zm.PyObject, args: ?*zm.PyObject, kwargs: ?*zm.PyObject) callconv(.c) ?*zm.PyObject {
            if (kwargs != null) {
                if (zm.PyDict_Size(kwargs) > 0) {
                    zm.PyErr_SetString(zm.PyExc_TypeError(), "keyword arguments not supported for init");
                    return null;
                }
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
                const InitFnType = @TypeOf(init_fn);
                const fn_info = @typeInfo(InitFnType).@"fn";
                const params = fn_info.params;

                if (args) |a| {
                    const actual = zm.PyTuple_Size(a);
                    const expected = @as(isize, @intCast(params.len));
                    if (actual != expected) {
                        zm.PyErr_SetString(zm.PyExc_TypeError(), "wrong number of arguments for init");
                        zm.PyMem_RawFree(alloc);
                        return null;
                    }

                    const TupleType = funcwrap.paramTypesTupleDirect(params);
                    var init_args: TupleType = undefined;

                    inline for (params, 0..) |param, i| {
                        const ParamT = param.type.?;
                        const arg_obj = zm.PyTuple_GetItem(a, @as(isize, @intCast(i)));
                        init_args[i] = conversion.fromPyObject(ParamT, arg_obj) catch {
                            zm.PyErr_SetString(zm.PyExc_TypeError(), "init argument conversion failed");
                            zm.PyMem_RawFree(alloc);
                            return null;
                        };
                    }

                    const InitReturn = @typeInfo(@TypeOf(init_fn)).@"fn".return_type orelse void;
                    if (InitReturn == void) {
                        @call(.auto, init_fn, init_args);
                    } else if (@typeInfo(InitReturn) == .error_union) {
                        ptr.* = @call(.auto, init_fn, init_args) catch |err| {
                            errors.setPyException(err);
                            zm.PyMem_RawFree(alloc);
                            return null;
                        };
                    } else {
                        ptr.* = @call(.auto, init_fn, init_args);
                    }
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

    const TypeBuilder = struct {
        fn getTypeObject() ?*zm.PyObject {
            const fields = comptime std.meta.fields(T);
            const field_count = fields.len;
            const defs_count = field_count + 1;

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
                        const converted = conversion.fromPyObject(field.type, val) catch {
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
