const std = @import("std");
const zm = @import("zig-maturin");
const conversion = @import("conversion.zig");

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

            // Opt in to free-threading: on a no-GIL interpreter a module that
            // doesn't declare itself safe forces the GIL back on process-wide.
            // No-op on regular/Limited-API builds.
            zm.pyo3zig_module_declare_no_gil(m);

            const classes: []const type = if (@hasField(@TypeOf(config), "classes")) config.classes else &.{};
            inline for (classes) |cls| {
                const type_obj = cls.py_type_obj();
                // Types built from a bare (undotted) PyType_Spec name have no
                // __module__, which breaks repr, pickling, and CPython 3.13's
                // dict-key error message (it reads type.__module__). Set it to
                // the owning module's name before handing the type over.
                if (zm.PyUnicode_FromString(@as([*:0]const u8, @ptrCast(name.ptr)))) |mod_name_obj| {
                    _ = zm.PyObject_SetAttrString(type_obj, "__module__", mod_name_obj);
                    zm.Py_XDECREF(mod_name_obj);
                }
                if (zm.PyModule_AddObject(m, cls.class_name(), type_obj) != 0) {
                    zm.Py_XDECREF(type_obj);
                    zm.Py_XDECREF(m);
                    allocator.free(methods);
                    allocator.destroy(mod_ptr);
                    return null;
                }
            }

            // Module-level constants: .constants = .{ .VERSION = "1.0", .MAX = 100 }
            if (@hasField(@TypeOf(config), "constants")) {
                const consts = config.constants;
                inline for (std.meta.fields(@TypeOf(consts))) |field| {
                    const val_obj = conversion.toPyObject(@field(consts, field.name)) catch {
                        zm.PyErr_SetString(zm.PyExc_RuntimeError(), "failed to convert module constant");
                        zm.Py_XDECREF(m);
                        return null;
                    };
                    const cname = @as([*:0]const u8, @ptrCast(field.name.ptr));
                    if (zm.PyModule_AddObject(m, cname, val_obj) != 0) {
                        zm.Py_XDECREF(val_obj);
                        zm.Py_XDECREF(m);
                        return null;
                    }
                }
            }

            // Nested submodules: .submodules = .{ pz.pyModule("sub", .{...}), ... }
            // Each child is created, set as an attribute of the parent, and
            // registered in sys.modules under the dotted "parent.child" name so
            // both `parent.sub` and `import parent.sub` work.
            if (@hasField(@TypeOf(config), "submodules")) {
                const sys_modules = zm.PyImport_GetModuleDict();
                inline for (config.submodules) |Child| {
                    // Comptime "parent.child" for the sys.modules key.
                    const dotted_z: [*:0]const u8 = std.fmt.comptimePrint(
                        "{s}.{s}",
                        .{ name, Child.module_name },
                    );

                    const sub = Child.init() orelse {
                        zm.Py_XDECREF(m);
                        return null;
                    };
                    // Give the submodule its fully-qualified __name__ so repr,
                    // pickling and tracebacks read "parent.child", not "child".
                    if (zm.PyUnicode_FromString(dotted_z)) |qual| {
                        _ = zm.PyObject_SetAttrString(sub, "__name__", qual);
                        zm.Py_XDECREF(qual);
                    }
                    // SetAttrString / SetItemString both incref; drop our own
                    // reference from init() after both holders are established.
                    if (zm.PyObject_SetAttrString(m, Child.class_name_z(), sub) != 0 or
                        (sys_modules != null and zm.PyDict_SetItemString(sys_modules, dotted_z, sub) != 0))
                    {
                        zm.Py_XDECREF(sub);
                        zm.Py_XDECREF(m);
                        return null;
                    }
                    zm.Py_XDECREF(sub);
                }
            }

            return m;
        }

        pub const module_name: [:0]const u8 = name;
        /// Null-terminated short module name (for attribute registration).
        pub fn class_name_z() [*:0]const u8 {
            return @as([*:0]const u8, @ptrCast(name.ptr));
        }
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
