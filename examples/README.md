# Examples

The canonical, **compiled-and-tested** example is
[`pyo3zig_example.zig`](../pyo3zig_example.zig) in the repository root (built by
`zig build`, exercised by `tests/test_pyo3zig.py`). It demonstrates every
feature of the `pyo3zig` layer. This page walks through it.

## Build & run it

```bash
zig build test        # compiles the demo + runs the Python test suite
```

Or build a wheel and import it:

```bash
zig-maturin build
pip install --find-links dist --no-index pyo3zig_demo
python -c "import pyo3zig_demo as m; print(m.add(2, 3))"
```

## What it shows

### Plain functions

```zig
fn add(a: i64, b: i64) i64 { return a + b; }
fn double(x: f64) f64 { return x * 2.0; }
```
```python
m.add(2, 3)        # 5
m.double(2.5)      # 5.0
```

### Strings and bytes (wrapper types)

```zig
fn greet(name: []const u8) !pz.PyString {
    var buf: [256]u8 = undefined;
    return pz.PyString.init(try std.fmt.bufPrint(&buf, "Hello, {s}!", .{name}));
}
```
```python
m.greet("world")   # "Hello, world!"
```

### Returning containers

```zig
fn make_array() [3]i64 { return .{ 10, 20, 30 }; }
fn make_point() struct { x: i64, y: i64 } { return .{ .x = 1, .y = 2 }; }
fn make_pair() struct { i64, f64 } { return .{ 7, 1.5 }; }
```
```python
m.make_array()     # [10, 20, 30]
m.make_point()     # {'x': 1, 'y': 2}
m.make_pair()      # (7, 1.5)
```

### Keyword arguments and defaults

```zig
pz.pyFnKw("power", power, .{ .args = &.{ "base", "exp" }, .defaults = .{ .exp = @as(i64, 2) } });
```
```python
m.power(3)              # 9
m.power(base=5, exp=3)  # 125
```

### A class

```zig
const Greeter = extern struct {
    val: i64,
    pub fn init(v: i64) Greeter { return .{ .val = v }; }
    pub fn __str__(self: *Greeter) !pz.PyString { ... }
    pub fn __hash__(self: *Greeter) i64 { return self.val; }
    pub fn __eq__(self: *Greeter, other: *Greeter) bool { return self.val == other.val; }
};
```
```python
g = m.Greeter(7)
str(g)              # "Greeter(val=7)"
g == m.Greeter(7)   # True
g != m.Greeter(9)   # True
g.greet()           # method call
```

### Panic safety

```zig
pub const panic = pz.panic;   // at module top
fn oob() i64 { const a = [_]i64{1,2,3}; var i: usize = 9; _ = &i; return a[i]; }
```
```python
m.oob()             # raises RuntimeError instead of crashing the interpreter
m.add(2, 3)         # 5  — interpreter still alive
```

### Generated type stubs

```python
print(m.__pyi__())
# def add(a: int, b: int) -> int: ...
# def make_pair() -> tuple[int, float]: ...
# def power(base: int, exp: int) -> int: ...
```

`zig-maturin build` ships these as `pyo3zig_demo.pyi` inside the wheel.
