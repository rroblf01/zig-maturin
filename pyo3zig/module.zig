const std = @import("std");
const zm = @import("zig-maturin");

pub fn pyModule(comptime name: [:0]const u8, comptime config: anytype) type {
    return struct {
        fn init_fn() callconv(.c) ?*zm.PyObject {
            var methods = config.functions ++ [_]zm.PyMethodDef{
                .{ .ml_name = null, .ml_meth = null, .ml_flags = 0, .ml_doc = null },
            };

            var mod = zm.PyModuleDef{
                .m_base = zm.PyModuleDef_HEAD_INIT,
                .m_name = name,
                .m_doc = null,
                .m_size = -1,
                .m_methods = @as(?[*]zm.PyMethodDef, @ptrCast(@constCast(&methods))),
                .m_slots = null,
                .m_traverse = null,
                .m_clear = null,
                .m_free = null,
            };

            const m = zm.PyModule_Create(&mod);
            if (m == null) return null;

            inline for (config.classes) |cls| {
                const type_obj = cls.py_type_obj();
                if (zm.PyModule_AddObject(m, cls.class_name(), type_obj) != 0) {
                    zm.Py_XDECREF(type_obj);
                    zm.Py_XDECREF(m);
                    return null;
                }
            }

            return m;
        }

        comptime {
            var export_buf: [256]u8 = undefined;
            const prefix = "PyInit_";
            @memcpy(export_buf[0..prefix.len], prefix);
            @memcpy(export_buf[prefix.len..][0..name.len], name);
            const total_len = prefix.len + name.len;
            export_buf[total_len] = 0;
            const export_name: [:0]const u8 = export_buf[0..total_len :0];
            @export(&init_fn, .{ .name = export_name, .linkage = .strong });
        }
    };
}
