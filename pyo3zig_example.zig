const std = @import("std");
const pz = @import("pyo3zig");

// Opt into the panic safety net: a Zig panic becomes a Python exception
// instead of aborting the interpreter.
pub const panic = pz.panic;

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

// Container conversions (returned by value -> Python list / dict / tuple).
fn make_array() [3]i64 {
    return .{ 10, 20, 30 };
}

// Container arguments: Python list -> []const i64, dict -> struct.
fn sum_list(xs: []const i64) i64 {
    var total: i64 = 0;
    for (xs) |x| total += x;
    return total;
}

fn point_sum(p: struct { x: i64, y: i64 }) i64 {
    return p.x + p.y;
}

// GIL release: heavy pure-Zig compute runs without holding the GIL.
fn compute_sum(n: i64) i64 {
    var total: i64 = 0;
    var i: i64 = 0;
    while (i < n) : (i += 1) total += i;
    return total;
}

fn heavy_sum(n: i64) i64 {
    return pz.allowThreads(compute_sum, .{n});
}

// Custom/typed exceptions: raise a specific Python exception with a message.
// The framework preserves it instead of mapping the Zig error generically.
fn parse_positive(x: i64) !i64 {
    if (x <= 0) {
        pz.setError(pz.PyExc_ValueError(), "value must be positive");
        return error.NotPositive;
    }
    return x;
}

// kwargs + defaults: power(base, exp=2) -> base**exp
fn power(base: i64, exp: i64) i64 {
    var result: i64 = 1;
    var n = exp;
    while (n > 0) : (n -= 1) result *= base;
    return result;
}

fn make_point() struct { x: i64, y: i64 } {
    return .{ .x = 1, .y = 2 };
}

fn make_pair() struct { i64, f64 } {
    return .{ 7, 1.5 };
}

// Triggers a Zig panic; with the panic handler installed it surfaces as a
// Python exception instead of crashing the interpreter.
fn boom() i64 {
    @panic("boom from Zig");
}

// Safety-check panic (index out of bounds) in ReleaseSafe/Debug.
fn oob() i64 {
    const arr = [_]i64{ 1, 2, 3 };
    var i: usize = 9;
    _ = &i; // force a runtime index so the bounds check isn't comptime-folded
    return arr[i];
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

// Class with keyword __init__ (with a default) and a keyword method.
const Vec2 = extern struct {
    x: i64,
    y: i64,

    pub fn init(x: i64, y: i64) Vec2 {
        return .{ .x = x, .y = y };
    }
};

fn vec2_dot(self: *Vec2, other_x: i64, other_y: i64) i64 {
    return self.x * other_x + self.y * other_y;
}

// Computed property (read-only).
fn vec2_length_sq(self: *Vec2) i64 {
    return self.x * self.x + self.y * self.y;
}

// Static method (no self / no instance).
fn vec2_dims() i64 {
    return 2;
}

const Vec2Class = pz.PyClass(Vec2, .{
    .init_args = &.{ "x", "y" },
    .init_defaults = .{ .y = @as(i64, 0) },
    .properties = &.{
        .{ .name = "length_sq", .get = vec2_length_sq },
    },
    .methods = &[_]pz.PyMethodDef{
        pz.wrapMethodKw(Vec2, "dot", vec2_dot, .{
            .args = &.{ "other_x", "other_y" },
            .defaults = .{ .other_y = @as(i64, 0) },
        }),
        pz.staticMethod("dims", vec2_dims),
    },
});

// Container + iterator protocols: __len__, __getitem__, __contains__,
// __next__ (auto __iter__ -> self-iterator).
const Range = extern struct {
    start: i64,
    stop: i64,
    cur: i64,

    pub fn init(start: i64, stop: i64) Range {
        return .{ .start = start, .stop = stop, .cur = start };
    }
    pub fn __len__(self: *Range) i64 {
        return if (self.stop > self.start) self.stop - self.start else 0;
    }
    pub fn __getitem__(self: *Range, i: i64) i64 {
        return self.start + i;
    }
    pub fn __contains__(self: *Range, v: i64) bool {
        return v >= self.start and v < self.stop;
    }
    pub fn __next__(self: *Range) ?i64 {
        if (self.cur >= self.stop) return null;
        const v = self.cur;
        self.cur += 1;
        return v;
    }
};

const RangeClass = pz.PyClass(Range, .{ .init_args = &.{ "start", "stop" } });

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

// Comptime-generated .pyi stub for the module's functions.
const STUB = pz.moduleStub(.{
    .{ .name = "hello", .func = hello },
    .{ .name = "add", .func = add, .args = &.{ "a", "b" } },
    .{ .name = "double", .func = double, .args = &.{"x"} },
    .{ .name = "greet", .func = greet, .args = &.{"name"} },
    .{ .name = "make_array", .func = make_array },
    .{ .name = "make_point", .func = make_point },
    .{ .name = "make_pair", .func = make_pair },
    .{ .name = "sum_list", .func = sum_list, .args = &.{"xs"} },
    .{ .name = "point_sum", .func = point_sum, .args = &.{"p"} },
    .{ .name = "power", .func = power, .args = &.{ "base", "exp" } },
});

fn __pyi__() []const u8 {
    return STUB;
}

const Mod = pz.pyModule("pyo3zig_demo", .{
    .doc = "Demo module built with pyo3zig.",
    .constants = .{
        .VERSION = "0.2.0",
        .MAX_ITEMS = @as(i64, 100),
        .PI = @as(f64, 3.14159),
    },
    .functions = &[_]pz.PyMethodDef{
        pz.pyFnNamed("hello", hello),
        pz.pyFnNamed("add", add),
        pz.pyFnNamed("double", double),
        pz.pyFnNamed("identity", identity),
        pz.pyFnNamed("make_array", make_array),
        pz.pyFnNamed("make_point", make_point),
        pz.pyFnNamed("make_pair", make_pair),
        pz.pyFnNamed("sum_list", sum_list),
        pz.pyFnNamed("point_sum", point_sum),
        pz.pyFnNamed("parse_positive", parse_positive),
        pz.pyFnNamed("heavy_sum", heavy_sum),
        pz.pyFnNamed("boom", boom),
        pz.pyFnNamed("oob", oob),
        pz.pyFnKw("power", power, .{
            .args = &.{ "base", "exp" },
            .defaults = .{ .exp = @as(i64, 2) },
        }),
        pz.pyFnNamed("__pyi__", __pyi__),
        pz.pyFnNamed("greet", greet),
        pz.pyFnNamed("repeat_bytes", repeat_bytes),
        pz.pyFnNamed("get_deinit_count", get_deinit_count),
    },
    .classes = &[_]type{ GreeterClass, DeinitTrackerClass, Vec2Class, RangeClass },
});

comptime {
    pz.exportModule(Mod);
}
