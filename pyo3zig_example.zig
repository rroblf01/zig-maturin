const std = @import("std");
const pz = @import("pyo3zig");

fn hello() []const u8 {
    return "Hello from pyo3zig!";
}

fn add(a: i64, b: i64) i64 {
    return a + b;
}

fn double(x: f64) f64 {
    return x * 2.0;
}

fn greet(name: []const u8) !pz.PyString {
    var buf: [256]u8 = undefined;
    const s = try std.fmt.bufPrint(&buf, "Hello, {s}!", .{name});
    return pz.PyString.init(s);
}

const Mod = pz.pyModule("pyo3zig_demo", .{
    .functions = &[_]pz.PyMethodDef{
        pz.pyFnNamed("hello", hello),
        pz.pyFnNamed("add", add),
        pz.pyFnNamed("double", double),
        pz.pyFnNamed("greet", greet),
    },
    .classes = &[_]type{},
});

comptime {
    pz.exportModule(Mod);
}
