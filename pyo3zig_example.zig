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

// Raw object passthrough: accepts and returns any Python object.
fn identity(obj: ?*pz.PyObject) ?*pz.PyObject {
    return pz.Py_NewRef(obj);
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

    pub fn __str__(self: *Greeter) !pz.PyString {
        var buf: [64]u8 = undefined;
        const s = try std.fmt.bufPrint(&buf, "Greeter(val={d})", .{self.val});
        return pz.PyString.init(s);
    }

    pub fn __hash__(self: *Greeter) i64 {
        return self.val;
    }

    pub fn __eq__(self: *Greeter, other: *Greeter) bool {
        return self.val == other.val;
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

var deinit_counter: i64 = 0;

const DeinitTracker = extern struct {
    pub fn __deinit__(_: *DeinitTracker) void {
        deinit_counter += 1;
    }
};

const DeinitTrackerClass = pz.PyClass(DeinitTracker, .{});

fn get_deinit_count() i64 {
    return deinit_counter;
}

const Mod = pz.pyModule("pyo3zig_demo", .{
    .doc = "Demo module built with pyo3zig.",
    .functions = &[_]pz.PyMethodDef{
        pz.pyFnNamed("hello", hello),
        pz.pyFnNamed("add", add),
        pz.pyFnNamed("double", double),
        pz.pyFnNamed("identity", identity),
        pz.pyFnNamed("greet", greet),
        pz.pyFnNamed("repeat_bytes", repeat_bytes),
        pz.pyFnNamed("get_deinit_count", get_deinit_count),
    },
    .classes = &[_]type{ GreeterClass, DeinitTrackerClass },
});

comptime {
    pz.exportModule(Mod);
}
