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

    pub fn __repr__(self: *Greeter) !pz.PyString {
        var buf: [64]u8 = undefined;
        const s = try std.fmt.bufPrint(&buf, "<Greeter val={d}>", .{self.val});
        return pz.PyString.init(s);
    }

    pub fn __hash__(self: *Greeter) i64 {
        return self.val;
    }

    pub fn __eq__(self: *Greeter, other: *Greeter) bool {
        return self.val == other.val;
    }

    // Full ordering: enables sorted(), min(), max(), < <= > >=.
    pub fn __lt__(self: *Greeter, other: *Greeter) bool {
        return self.val < other.val;
    }
    pub fn __le__(self: *Greeter, other: *Greeter) bool {
        return self.val <= other.val;
    }
    pub fn __gt__(self: *Greeter, other: *Greeter) bool {
        return self.val > other.val;
    }
    pub fn __ge__(self: *Greeter, other: *Greeter) bool {
        return self.val >= other.val;
    }

    // Callable instances: greeter(n) -> val + n.
    pub fn __call__(self: *Greeter, n: i64) i64 {
        return self.val + n;
    }

    // __format__ powers format(g, spec) and f"{g:spec}".
    pub fn __format__(self: *Greeter, spec: []const u8) !pz.PyString {
        var buf: [64]u8 = undefined;
        const s = if (spec.len == 0)
            try std.fmt.bufPrint(&buf, "Greeter({d})", .{self.val})
        else
            try std.fmt.bufPrint(&buf, "[{s}={d}]", .{ spec, self.val });
        return pz.PyString.init(s);
    }
};

// Class with keyword __init__ (with a default) and a keyword method.
const Vec2 = extern struct {
    x: i64,
    y: i64,

    pub fn init(x: i64, y: i64) Vec2 {
        return .{ .x = x, .y = y };
    }

    // Operator overloading via the number protocol. Binary ops returning Vec2
    // are wrapped into new instances; __mul__ here is a dot product (scalar).
    pub fn __add__(self: *Vec2, other: *Vec2) Vec2 {
        return .{ .x = self.x + other.x, .y = self.y + other.y };
    }
    pub fn __sub__(self: *Vec2, other: *Vec2) Vec2 {
        return .{ .x = self.x - other.x, .y = self.y - other.y };
    }
    pub fn __mul__(self: *Vec2, other: *Vec2) i64 {
        return self.x * other.x + self.y * other.y;
    }
    pub fn __neg__(self: *Vec2) Vec2 {
        return .{ .x = -self.x, .y = -self.y };
    }
    pub fn __bool__(self: *Vec2) bool {
        return self.x != 0 or self.y != 0;
    }
};

fn vec2_dot(self: *Vec2, other_x: i64, other_y: i64) i64 {
    return self.x * other_x + self.y * other_y;
}

// Computed property (read-only).
fn vec2_length_sq(self: *Vec2) i64 {
    return self.x * self.x + self.y * self.y;
}

// A method that panics — the panic net must turn it into an exception.
fn vec2_bad(self: *Vec2) i64 {
    _ = self;
    @panic("method boom");
}

// A class whose init panics on bad input.
const Boomable = extern struct {
    v: i64,
    pub fn init(v: i64) Boomable {
        if (v < 0) @panic("bad init");
        return .{ .v = v };
    }
};

const BoomableClass = pz.PyClass(Boomable, .{ .init_args = &.{"v"} });

// Static method (no self / no instance).
fn vec2_dims() i64 {
    return 2;
}

// Class method / alternative constructor: returns a Vec2, which the framework
// wraps into a new instance of the class.
fn vec2_from_pair(p: struct { x: i64, y: i64 }) Vec2 {
    return .{ .x = p.x, .y = p.y };
}

// Free function that takes a class instance as an argument (*Vec2) and reads
// its Zig fields directly — no copy, borrowed for the duration of the call.
fn vec_dot(a: *Vec2, b: *Vec2) i64 {
    return a.x * b.x + a.y * b.y;
}

const Vec2Class = pz.PyClass(Vec2, .{
    .doc = "A 2D integer vector with arithmetic operators.",
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
        pz.classMethod(Vec2, "from_pair", vec2_from_pair),
        pz.wrapMethodNamed(Vec2, "bad", vec2_bad),
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
        // Demonstrates the panic net on a dunder: a panic here becomes a
        // Python exception instead of crashing the interpreter.
        if (i == 99) @panic("bad index");
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
    // Custom reversed(): proves the explicit hook wins over the sequence
    // protocol fallback (returns just the endpoints, stop-first).
    pub fn __reversed__(self: *Range) [2]i64 {
        return .{ self.stop, self.start };
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

// Mixed-type and reflected operators: scalar arithmetic on a money amount.
const Money = extern struct {
    cents: i64,
    pub fn init(cents: i64) Money {
        return .{ .cents = cents };
    }
    pub fn __add__(self: *Money, o: *Money) Money {
        return .{ .cents = self.cents + o.cents };
    }
    pub fn __sub__(self: *Money, o: *Money) Money {
        return .{ .cents = self.cents - o.cents };
    }
    // mixed: money * int
    pub fn __mul__(self: *Money, k: i64) Money {
        return .{ .cents = self.cents * k };
    }
    // reflected: int * money
    pub fn __rmul__(self: *Money, k: i64) Money {
        return .{ .cents = self.cents * k };
    }
    pub fn __floordiv__(self: *Money, k: i64) Money {
        return .{ .cents = @divTrunc(self.cents, k) };
    }
    pub fn __mod__(self: *Money, k: i64) Money {
        return .{ .cents = @mod(self.cents, k) };
    }
    pub fn __pow__(self: *Money, k: i64) Money {
        var r: i64 = 1;
        var n = k;
        while (n > 0) : (n -= 1) r *= self.cents;
        return .{ .cents = r };
    }
    // In-place: money += / -= money, money *= int (mutate self).
    pub fn __iadd__(self: *Money, o: *Money) void {
        self.cents += o.cents;
    }
    pub fn __isub__(self: *Money, o: *Money) void {
        self.cents -= o.cents;
    }
    pub fn __imul__(self: *Money, k: i64) void {
        self.cents *= k;
    }
    // Pickle hook: returns a tuple describing how to reconstruct the value.
    pub fn __reduce__(self: *Money) struct { i64 } {
        return .{self.cents};
    }
    // truediv returns a float ratio (a non-Self result, converted normally).
    pub fn __truediv__(self: *Money, k: i64) f64 {
        return @as(f64, @floatFromInt(self.cents)) / @as(f64, @floatFromInt(k));
    }
    // divmod(money, k) -> (quotient, remainder).
    pub fn __divmod__(self: *Money, k: i64) struct { i64, i64 } {
        return .{ @divTrunc(self.cents, k), @mod(self.cents, k) };
    }
    // abs(m), +m.
    pub fn __abs__(self: *Money) Money {
        return .{ .cents = if (self.cents < 0) -self.cents else self.cents };
    }
    pub fn __pos__(self: *Money) Money {
        return .{ .cents = self.cents };
    }
    // More in-place operators (mutate self).
    pub fn __imod__(self: *Money, k: i64) void {
        self.cents = @mod(self.cents, k);
    }
    pub fn __ipow__(self: *Money, k: i64) void {
        var r: i64 = 1;
        var n = k;
        while (n > 0) : (n -= 1) r *= self.cents;
        self.cents = r;
    }
    // Numeric conversions: int(m), float(m).
    pub fn __int__(self: *Money) i64 {
        return self.cents;
    }
    pub fn __float__(self: *Money) f64 {
        return @floatFromInt(self.cents);
    }
};

const MoneyClass = pz.PyClass(Money, .{ .init_args = &.{"cents"} });

// Context manager: `with Resource() as r` sets/clears `open`.
const Resource = extern struct {
    open: i64,
    pub fn init() Resource {
        return .{ .open = 0 };
    }
    pub fn __enter__(self: *Resource) void {
        self.open = 1;
    }
    pub fn __exit__(self: *Resource, _: ?*pz.PyObject, _: ?*pz.PyObject, _: ?*pz.PyObject) bool {
        self.open = 0;
        return false; // don't suppress exceptions
    }
};
const ResourceClass = pz.PyClass(Resource, .{});

// Context manager whose __exit__ returns true -> suppresses the exception.
const Suppressor = extern struct {
    pub fn init() Suppressor {
        return .{};
    }
    pub fn __enter__(_: *Suppressor) void {}
    pub fn __exit__(_: *Suppressor, _: ?*pz.PyObject, _: ?*pz.PyObject, _: ?*pz.PyObject) bool {
        return true; // swallow whatever was raised inside the block
    }
};
const SuppressorClass = pz.PyClass(Suppressor, .{});

// __setattr__ that rejects every assignment with an error (read-only object).
const ReadOnly = extern struct {
    x: i64,
    pub fn init(x: i64) ReadOnly {
        return .{ .x = x };
    }
    pub fn __setattr__(_: *ReadOnly, _: []const u8, _: ?*pz.PyObject) !void {
        pz.setError(pz.PyExc_AttributeError(), "object is read-only");
        return error.ReadOnly;
    }
};
const ReadOnlyClass = pz.PyClass(ReadOnly, .{});

// __setattr__ intercepts every attribute assignment.
const Recorder = extern struct {
    sets: i64,
    pub fn init() Recorder {
        return .{ .sets = 0 };
    }
    pub fn __setattr__(self: *Recorder, _: []const u8, _: ?*pz.PyObject) void {
        self.sets += 1;
    }
};
const RecorderClass = pz.PyClass(Recorder, .{});

// __getattr__ is consulted only when normal lookup fails.
const Dynamic = extern struct {
    base: i64,
    pub fn init(base: i64) Dynamic {
        return .{ .base = base };
    }
    pub fn __getattr__(self: *Dynamic, name: []const u8) i64 {
        return self.base + @as(i64, @intCast(name.len));
    }
    // __index__ lets the object act as an integer index (hex/bin/slicing).
    pub fn __index__(self: *Dynamic) i64 {
        return self.base;
    }
};
const DynamicClass = pz.PyClass(Dynamic, .{ .init_args = &.{"base"} });

// Read-only buffer protocol: exposes 8 bytes zero-copy to memoryview/bytes().
const Bytes8 = extern struct {
    data: [8]u8,
    pub fn init(fill: i64) Bytes8 {
        var b: Bytes8 = .{ .data = undefined };
        for (&b.data) |*x| x.* = @intCast(fill);
        return b;
    }
    pub fn __buffer__(self: *Bytes8) []const u8 {
        return self.data[0..];
    }
};
const Bytes8Class = pz.PyClass(Bytes8, .{});

// Integer wider than 64 bits, round-tripped through CPython's bigint.
fn big_mul(a: i128, b: i128) i128 {
    return a * b;
}

// A class holding a Python object reference -> participates in cyclic GC. The
// framework owns the `next` reference, visits it in tp_traverse, and clears it
// in tp_clear, so reference cycles are collectable.
var node_deinit_count: i64 = 0;

const Node = extern struct {
    next: ?*pz.PyObject,
    pub fn init() Node {
        return .{ .next = null };
    }
    pub fn __deinit__(_: *Node) void {
        node_deinit_count += 1;
    }
};

const NodeClass = pz.PyClass(Node, .{});

fn get_node_deinit_count() i64 {
    return node_deinit_count;
}

// Numeric hooks that CPython looks up by name: math.floor/ceil/trunc, round(),
// bytes(), and pickle's __getstate__/__setstate__. Holds tenths of a unit.
const Temp = extern struct {
    tenths: i64,
    pub fn init(tenths: i64) Temp {
        return .{ .tenths = tenths };
    }
    pub fn __float__(self: *Temp) f64 {
        return @as(f64, @floatFromInt(self.tenths)) / 10.0;
    }
    pub fn __floor__(self: *Temp) i64 {
        return @divFloor(self.tenths, 10);
    }
    pub fn __ceil__(self: *Temp) i64 {
        return @divFloor(self.tenths + 9, 10);
    }
    pub fn __trunc__(self: *Temp) i64 {
        return @divTrunc(self.tenths, 10);
    }
    pub fn __round__(self: *Temp) i64 {
        return @divFloor(self.tenths + 5, 10);
    }
    pub fn __bytes__(self: *Temp) !pz.PyBytes {
        var buf: [8]u8 = undefined;
        std.mem.writeInt(i64, &buf, self.tenths, .little);
        return pz.PyBytes.init(buf[0..]);
    }
    pub fn __getstate__(self: *Temp) i64 {
        return self.tenths;
    }
    pub fn __setstate__(self: *Temp, state: i64) void {
        self.tenths = state;
    }
};
const TempClass = pz.PyClass(Temp, .{ .init_args = &.{"tenths"} });

// Bitwise / shift operators, unary abs/pos/invert, and the matching in-place
// forms. Operands are plain ints (mixed-type ops).
const Bits = extern struct {
    v: i64,
    pub fn init(v: i64) Bits {
        return .{ .v = v };
    }
    pub fn __and__(self: *Bits, k: i64) Bits {
        return .{ .v = self.v & k };
    }
    pub fn __or__(self: *Bits, k: i64) Bits {
        return .{ .v = self.v | k };
    }
    pub fn __xor__(self: *Bits, k: i64) Bits {
        return .{ .v = self.v ^ k };
    }
    pub fn __lshift__(self: *Bits, k: i64) Bits {
        return .{ .v = self.v << @as(u6, @intCast(k)) };
    }
    pub fn __rshift__(self: *Bits, k: i64) Bits {
        return .{ .v = self.v >> @as(u6, @intCast(k)) };
    }
    pub fn __invert__(self: *Bits) Bits {
        return .{ .v = ~self.v };
    }
    pub fn __abs__(self: *Bits) Bits {
        return .{ .v = if (self.v < 0) -self.v else self.v };
    }
    pub fn __pos__(self: *Bits) Bits {
        return .{ .v = self.v };
    }
    pub fn __iand__(self: *Bits, k: i64) void {
        self.v &= k;
    }
    pub fn __ior__(self: *Bits, k: i64) void {
        self.v |= k;
    }
    pub fn __ixor__(self: *Bits, k: i64) void {
        self.v ^= k;
    }
    pub fn __ilshift__(self: *Bits, k: i64) void {
        self.v <<= @as(u6, @intCast(k));
    }
    pub fn __irshift__(self: *Bits, k: i64) void {
        self.v >>= @as(u6, @intCast(k));
    }
    pub fn __int__(self: *Bits) i64 {
        return self.v;
    }
};
const BitsClass = pz.PyClass(Bits, .{ .init_args = &.{"v"} });

// __delitem__ powers `del obj[key]` (shares the assignment slot).
const Bag = extern struct {
    deleted: i64,
    pub fn init() Bag {
        return .{ .deleted = 0 };
    }
    pub fn __delitem__(self: *Bag, key: i64) void {
        self.deleted += key;
    }
};
const BagClass = pz.PyClass(Bag, .{});

// Defining __eq__ without __hash__ makes instances unhashable (Python rule).
const Unhashable = extern struct {
    v: i64,
    pub fn init(v: i64) Unhashable {
        return .{ .v = v };
    }
    pub fn __eq__(self: *Unhashable, o: *Unhashable) bool {
        return self.v == o.v;
    }
};
const UnhashableClass = pz.PyClass(Unhashable, .{ .init_args = &.{"v"} });

// bytearray (and bytes/str) decode to a borrowed []const u8.
fn sum_bytes(data: []const u8) i64 {
    var total: i64 = 0;
    for (data) |b| total += b;
    return total;
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
    .{ .name = "vec_dot", .func = vec_dot, .args = &.{ "a", "b" } },
    .{ .name = "power", .func = power, .args = &.{ "base", "exp" } },
    .{ .name = "sum_bytes", .func = sum_bytes, .args = &.{"data"} },
});

// Class stubs so type checkers see the classes too.
const CLASS_STUBS =
    pz.classStub(.{
        .name = "Greeter",
        .type = Greeter,
        .init = &.{"v"},
        .methods = .{
            .{ .name = "greet", .func = greet_method },
        },
    }) ++
    pz.classStub(.{
        .name = "Vec2",
        .type = Vec2,
        .init = &.{ "x", "y" },
        .methods = .{
            .{ .name = "dot", .func = vec2_dot, .args = &.{ "other_x", "other_y" } },
        },
    }) ++
    pz.classStub(.{
        .name = "Range",
        .type = Range,
        .init = &.{ "start", "stop" },
    });

fn __pyi__() []const u8 {
    return STUB ++ "\n" ++ CLASS_STUBS;
}

const Mod = pz.pyModule("pyo3zig_demo", .{
    .doc = "Demo module built with pyo3zig.",
    .constants = .{
        .VERSION = "0.3.0",
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
        pz.pyFnNamed("vec_dot", vec_dot),
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
        pz.pyFnNamed("get_node_deinit_count", get_node_deinit_count),
        pz.pyFnNamed("big_mul", big_mul),
        pz.pyFnNamed("sum_bytes", sum_bytes),
    },
    .classes = &[_]type{ GreeterClass, DeinitTrackerClass, Vec2Class, RangeClass, BoomableClass, MoneyClass, NodeClass, ResourceClass, SuppressorClass, ReadOnlyClass, RecorderClass, DynamicClass, Bytes8Class, BitsClass, BagClass, UnhashableClass, TempClass },
});

comptime {
    pz.exportModule(Mod);
}
