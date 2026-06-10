const std = @import("std");
const zm = @import("zig-maturin");

fn hello(self: ?*zm.PyObject, args: ?*zm.PyObject) callconv(.c) ?*zm.PyObject {
    _ = self;
    _ = args;
    return zm.PyUnicode_FromString("Hello from Zig!");
}

const methods = [_]zm.PyMethodDef{
    zm.method("hello", &hello, zm.METH_NOARGS, "Say hello"),
    .{ .ml_name = null, .ml_meth = null, .ml_flags = 0, .ml_doc = null },
};

var mod = zm.PyModuleDef{
    .m_base = zm.PyModuleDef_HEAD_INIT,
    .m_name = "ziggreet",
    .m_doc = "A Python module written in Zig",
    .m_size = -1,
    .m_methods = @as(?[*]zm.PyMethodDef, @ptrCast(@constCast(&methods))),
    .m_slots = null,
    .m_traverse = null,
    .m_clear = null,
    .m_free = null,
};

comptime {
    @export(&py_init, .{ .name = "PyInit_ziggreet\x00", .linkage = .strong });
}

fn py_init() callconv(.c) ?*zm.PyObject {
    return zm.PyModule_Create(&mod);
}
