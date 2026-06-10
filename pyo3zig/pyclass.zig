const std = @import("std");
const zm = @import("zig-maturin");
const pycell = @import("pycell.zig");
const funcwrap = @import("funcwrap.zig");
const conversion = @import("conversion.zig");

fn buildTypeName(comptime T: type) [*:0]const u8 {
    const full = @typeName(T);
    comptime var buf: [256]u8 = undefined;
    comptime var len: usize = 0;
    inline for (full) |c| {
        if (len >= 255) break;
        buf[len] = c;
        len += 1;
    }
    buf[len] = 0;
    return @as([*:0]const u8, @ptrCast(&buf));
}

pub fn PyClass(comptime T: type) type {
    const Cell = pycell.PyCell(T);
    const type_name = buildTypeName(T);

    const DeallocWrapper = struct {
        fn dealloc(obj: ?*zm.PyObject) callconv(.c) void {
            if (obj) |o| {
                if (@hasDecl(T, "__deinit__")) {
                    const ptr = Cell.ptrFromObj(o);
                    ptr.__deinit__();
                }
                zm.PyMem_RawFree(@as(?*anyopaque, @ptrCast(o)));
            }
        }
    };

    const NewWrapper = struct {
        fn new(ty: ?*zm.PyObject, args: ?*zm.PyObject, kwargs: ?*zm.PyObject) callconv(.c) ?*zm.PyObject {
            _ = kwargs;
            const alloc = zm.PyMem_RawMalloc(Cell.allocSize());
            if (alloc == null) {
                zm.PyErr_SetString(zm.PyExc_MemoryError(), "out of memory");
                return null;
            }
            const obj = @as(?*zm.PyObject, @ptrCast(@alignCast(alloc)));
            const header = @as(*zm.PyObjectHeader, @ptrCast(@alignCast(alloc)));
            header.ob_refcnt = 1;
            header.ob_type = @as(?*anyopaque, @ptrCast(ty));

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

                    ptr.* = @call(.auto, init_fn, init_args) catch {
                        zm.PyErr_SetString(zm.PyExc_RuntimeError(), "init failed");
                        zm.PyMem_RawFree(alloc);
                        return null;
                    };
                }
            }

            return obj;
        }
    };

    const TypeBuilder = struct {
        fn getTypeObject() ?*zm.PyObject {
            var getset_defs: [countFields(T) + 1]zm.PyGetSetDef = undefined;
            var getset_idx: usize = 0;

            inline for (comptime std.meta.fields(T)) |field| {
                const FieldWrapper = struct {
                    fn getter(obj: ?*zm.PyObject, _: ?*anyopaque) callconv(.c) ?*zm.PyObject {
                        const ptr = Cell.ptrFromObj(obj);
                        const val = @field(ptr, field.name);
                        return conversion.toPyObject(val) catch null;
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

                const field_name = @as([*:0]const u8, @ptrCast(@as([*]const u8, @ptrCast(&field.name))));
                getset_defs[getset_idx] = .{
                    .name = field_name,
                    .get = &FieldWrapper.getter,
                    .set = &FieldWrapper.setter,
                    .doc = null,
                    .closure = null,
                };
                getset_idx += 1;
            }
            getset_defs[getset_idx] = .{ .name = null, .get = null, .set = null, .doc = null, .closure = null };

            var slots = [_]zm.PyType_Slot{
                .{ .slot = zm.Py_tp_dealloc, .pfunc = @as(?*anyopaque, @ptrCast(&DeallocWrapper.dealloc)) },
                .{ .slot = zm.Py_tp_new, .pfunc = @as(?*anyopaque, @ptrCast(&NewWrapper.new)) },
                .{ .slot = zm.Py_tp_getset, .pfunc = @as(?*anyopaque, @ptrCast(&getset_defs)) },
                .{ .slot = 0, .pfunc = null },
            };

            var spec = zm.PyType_Spec{
                .name = type_name,
                .basicsize = @as(c_int, @intCast(Cell.allocSize())),
                .itemsize = 0,
                .flags = zm.Py_TPFLAGS_DEFAULT | zm.Py_TPFLAGS_HEAPTYPE,
                .slots = &slots,
            };

            return zm.PyType_FromSpec(&spec);
        }
    };

    return struct {
        pub fn py_type_obj() ?*zm.PyObject {
            return TypeBuilder.getTypeObject();
        }
        pub fn class_name() [*:0]const u8 {
            return type_name;
        }
    };
}

fn countFields(comptime T: type) usize {
    return std.meta.fields(T).len;
}
