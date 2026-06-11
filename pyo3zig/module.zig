const std = @import("std");
const zm = @import("zig-maturin");
const conversion = @import("conversion.zig");

pub fn pyModule(comptime name: [:0]const u8, comptime config: anytype) type {
    return struct {
        const Self = @This();

        const funcs: []const zm.PyMethodDef = if (@hasField(@TypeOf(config), "functions")) config.functions else &.{};
        const sentinel = zm.PyMethodDef{ .ml_name = null, .ml_meth = null, .ml_flags = 0, .ml_doc = null };
        // The method table and module defs are process-lifetime statics, built at
        // comptime (every entry is a comptime-known trampoline pointer).
        var methods_storage: [funcs.len + 1]zm.PyMethodDef = (funcs ++ &[_]zm.PyMethodDef{sentinel}).*;

        const doc: ?[*:0]const u8 = if (@hasField(@TypeOf(config), "doc"))
            @as([*:0]const u8, @ptrCast(config.doc.ptr))
        else
            null;

        // Multi-phase init (PEP 489): declares support for (shared-GIL)
        // sub-interpreters, so the module can be imported into more than one
        // interpreter. Each interpreter runs `exec` and gets its OWN type objects
        // via the interpreter-keyed caches in pyclass.zig / datetime.zig. The
        // shared GIL serializes those caches (per-interpreter-GIL would need them
        // lock-protected, which is future work).
        var mp_slots = [_]zm.PyModuleDef_Slot{
            .{ .slot = zm.Py_mod_exec, .value = @constCast(@ptrCast(&exec)) },
            .{ .slot = zm.Py_mod_multiple_interpreters, .value = zm.Py_MOD_MULTIPLE_INTERPRETERS_SUPPORTED },
            .{ .slot = 0, .value = null },
        };
        var mp_def: zm.PyModuleDef = .{
            .m_base = zm.PyModuleDef_HEAD_INIT,
            .m_name = name,
            .m_doc = doc,
            .m_size = 0,
            .m_methods = &methods_storage,
            .m_slots = @ptrCast(&mp_slots),
            .m_traverse = null,
            .m_clear = null,
            .m_free = @constCast(@ptrCast(&freeModule)),
        };
        // Single-phase def, used only when this module is nested as a submodule
        // (created inline inside the parent's exec, not via PyInit_).
        var sp_def: zm.PyModuleDef = .{
            .m_base = zm.PyModuleDef_HEAD_INIT,
            .m_name = name,
            .m_doc = doc,
            .m_size = -1,
            .m_methods = &methods_storage,
            .m_slots = null,
            .m_traverse = null,
            .m_clear = null,
            .m_free = @constCast(@ptrCast(&freeModule)),
        };

        /// Populate a freshly-created module object: classes, constants,
        /// submodules. Returns 0 on success, -1 on error (with a Python
        /// exception set). Runs once per interpreter that imports the module.
        fn populate(m: ?*zm.PyObject) c_int {
            // Opt in to free-threading (no-op on regular / Limited-API builds).
            zm.pyo3zig_module_declare_no_gil(m);

            const classes: []const type = if (@hasField(@TypeOf(config), "classes")) config.classes else &.{};
            inline for (classes) |cls| {
                const type_obj = cls.py_type_obj() orelse return -1;
                // A bare (undotted) PyType_Spec name has no __module__, which
                // breaks repr / pickling / 3.13's dict-key error message.
                if (zm.PyUnicode_FromString(@as([*:0]const u8, @ptrCast(name.ptr)))) |mod_name_obj| {
                    _ = zm.PyObject_SetAttrString(type_obj, "__module__", mod_name_obj);
                    zm.Py_XDECREF(mod_name_obj);
                }
                if (zm.PyModule_AddObject(m, cls.class_name(), type_obj) != 0) {
                    zm.Py_XDECREF(type_obj);
                    return -1;
                }
            }

            // Module-level constants: .constants = .{ .VERSION = "1.0", .MAX = 100 }
            if (@hasField(@TypeOf(config), "constants")) {
                const consts = config.constants;
                inline for (std.meta.fields(@TypeOf(consts))) |field| {
                    const val_obj = conversion.toPyObject(@field(consts, field.name)) catch {
                        zm.PyErr_SetString(zm.PyExc_RuntimeError(), "failed to convert module constant");
                        return -1;
                    };
                    const cname = @as([*:0]const u8, @ptrCast(field.name.ptr));
                    if (zm.PyModule_AddObject(m, cname, val_obj) != 0) {
                        zm.Py_XDECREF(val_obj);
                        return -1;
                    }
                }
            }

            // Nested submodules: created inline (single-phase), set as an
            // attribute, and registered in sys.modules under the dotted name.
            if (@hasField(@TypeOf(config), "submodules")) {
                const sys_modules = zm.PyImport_GetModuleDict();
                inline for (config.submodules) |Child| {
                    const dotted_z: [*:0]const u8 = std.fmt.comptimePrint(
                        "{s}.{s}",
                        .{ name, Child.module_name },
                    );
                    const sub = Child.createInline() orelse return -1;
                    if (zm.PyUnicode_FromString(dotted_z)) |qual| {
                        _ = zm.PyObject_SetAttrString(sub, "__name__", qual);
                        zm.Py_XDECREF(qual);
                    }
                    if (zm.PyObject_SetAttrString(m, Child.class_name_z(), sub) != 0 or
                        (sys_modules != null and zm.PyDict_SetItemString(sys_modules, dotted_z, sub) != 0))
                    {
                        zm.Py_XDECREF(sub);
                        return -1;
                    }
                    zm.Py_XDECREF(sub);
                }
            }

            return 0;
        }

        /// Py_mod_exec hook (multi-phase): populate the module CPython created.
        fn exec(module: ?*zm.PyObject) callconv(.c) c_int {
            return populate(module);
        }

        /// m_free hook: when this module is torn down (notably when a
        /// sub-interpreter is destroyed), drop this interpreter's entries from
        /// every per-interpreter cache. Otherwise a freed interpreter would leave
        /// stale type pointers that a later interpreter reusing the same
        /// PyInterpreterState address could read as live objects (use-after-free).
        fn freeModule(_: ?*anyopaque) callconv(.c) void {
            const classes: []const type = if (@hasField(@TypeOf(config), "classes")) config.classes else &.{};
            inline for (classes) |cls| {
                if (@hasDecl(cls, "clearTypeCache")) cls.clearTypeCache();
            }
            @import("datetime.zig").clearCache();
            zm.pyo3zig_clear_awaitable_cache();
        }

        /// PyInit_<name>: returns the module def for multi-phase initialization.
        pub fn init() callconv(.c) ?*zm.PyObject {
            return zm.PyModuleDef_Init(&mp_def);
        }

        /// Create this module inline (single-phase) for use as a submodule.
        pub fn createInline() ?*zm.PyObject {
            const m = zm.PyModule_Create(&sp_def) orelse return null;
            if (populate(m) != 0) {
                zm.Py_XDECREF(m);
                return null;
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
