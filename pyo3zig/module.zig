const std = @import("std");
const zm = @import("zig-maturin");

pub fn pyModule(comptime name: [:0]const u8, comptime config: anytype) type {
    return struct {
        pub fn init() callconv(.c) ?*zm.PyObject {
            const allocator = std.heap.c_allocator;
            const funcs: []const zm.PyMethodDef = if (@hasField(@TypeOf(config), "functions")) config.functions else &.{};

            const method_count = funcs.len + 1;
            const methods = allocator.alloc(zm.PyMethodDef, method_count) catch {
                zm.PyErr_SetString(zm.PyExc_MemoryError(), "out of memory");
                return null;
            };
            for (funcs, 0..) |f, i| {
                methods[i] = f;
            }
            methods[method_count - 1] = .{ .ml_name = null, .ml_meth = null, .ml_flags = 0, .ml_doc = null };

            const mod_ptr = allocator.create(zm.PyModuleDef) catch {
                allocator.free(methods);
                zm.PyErr_SetString(zm.PyExc_MemoryError(), "out of memory");
                return null;
            };
            const doc: ?[*:0]const u8 = if (@hasField(@TypeOf(config), "doc"))
                @as([*:0]const u8, @ptrCast(config.doc.ptr))
            else
                null;
            mod_ptr.* = zm.PyModuleDef{
                .m_base = zm.PyModuleDef_HEAD_INIT,
                .m_name = name,
                .m_doc = doc,
                .m_size = -1,
                .m_methods = @as(?[*]zm.PyMethodDef, @ptrCast(methods.ptr)),
                .m_slots = null,
                .m_traverse = null,
                .m_clear = null,
                .m_free = null,
            };

            const m = zm.PyModule_Create(mod_ptr);
            if (m == null) {
                allocator.free(methods);
                allocator.destroy(mod_ptr);
                return null;
            }

            const classes: []const type = if (@hasField(@TypeOf(config), "classes")) config.classes else &.{};
            inline for (classes) |cls| {
                const type_obj = cls.py_type_obj();
                if (zm.PyModule_AddObject(m, cls.class_name(), type_obj) != 0) {
                    zm.Py_XDECREF(type_obj);
                    zm.Py_XDECREF(m);
                    allocator.free(methods);
                    allocator.destroy(mod_ptr);
                    return null;
                }
            }

            return m;
        }

        pub const module_name: [:0]const u8 = name;
    };
}

pub fn exportModule(comptime ModuleType: type) void {
    comptime {
        const name = ModuleType.module_name;
        var buf: [256]u8 = undefined;
        const prefix = "PyInit_";
        const total = prefix.len + name.len;
        @memcpy(buf[0..prefix.len], prefix);
        @memcpy(buf[prefix.len..total], name);
        buf[total] = 0;
        @export(&ModuleType.init, .{ .name = buf[0..total :0], .linkage = .strong });
    }
}
