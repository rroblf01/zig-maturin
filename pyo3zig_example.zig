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

fn repeat_bytes(data: []const u8, count: u64) !pz.PyBytes {
    const total = data.len * count;
    const result = try std.heap.c_allocator.alloc(u8, total);
    defer std.heap.c_allocator.free(result);
    for (0..count) |i| {
        @memcpy(result[i * data.len .. (i + 1) * data.len], data);
    }
    return pz.PyBytes.init(result);
}

const Greeter = extern struct {
    val: i64,

    pub fn init(v: i64) Greeter {
        return Greeter{ .val = v };
    }
};

fn greet_method(self: *Greeter) !pz.PyString {
    var buf: [256]u8 = undefined;
    const s = try std.fmt.bufPrint(&buf, "Hello, val={d}!", .{self.val});
    return pz.PyString.init(s);
}

const GreeterClass = pz.PyClass(Greeter, .{
    .methods = &[_]pz.PyMethodDef{
        pz.wrapMethodNamed(Greeter, "greet", greet_method),
    },
});

const Mod = pz.pyModule("pyo3zig_demo", .{
    .functions = &[_]pz.PyMethodDef{
        pz.pyFnNamed("hello", hello),
        pz.pyFnNamed("add", add),
        pz.pyFnNamed("double", double),
        pz.pyFnNamed("greet", greet),
        pz.pyFnNamed("repeat_bytes", repeat_bytes),
    },
    .classes = &[_]type{GreeterClass},
});

comptime {
    pz.exportModule(Mod);
}
