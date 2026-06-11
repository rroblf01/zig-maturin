# zig-maturin

**Build and publish Zig-powered Python extensions — `pip install`, no compiler on the user's side.**

`zig-maturin` is [Maturin](https://github.com/PyO3/maturin) + [PyO3](https://github.com/PyO3/pyo3) for Zig: a high-level Zig library (`pyo3zig`) for writing Python extensions, plus a CLI that compiles them into ready-to-install wheels.

```python
import my_extension
my_extension.add(2, 3)          # -> 5
my_extension.greet("world")     # -> "Hello, world!"
```

The extension author needs Zig. The end user just `pip install`s a wheel — no Zig, no compiler, nothing to build.

## Why Zig

| | Rust + Maturin | Zig + zig-maturin |
|---|---|---|
| Cross-compilation | needs Docker / extra toolchains | **built-in**: `--target aarch64-macos` works out of the box |
| Toolchain size | gigabytes | a few megabytes |
| Honest manylinux | via `auditwheel` | **glibc pinned at build** (`gnu.2.28`) → the tag is true |
| C-API access | `unsafe extern` | native C interop |

## Performance

Summing `0..1_000_000` in a tight loop, Zig (releasing the GIL) vs pure Python
(`examples/bench.py`, CPython 3.13, x86_64):

| Implementation | Time per call | Speedup |
|---|---|---|
| Zig (`pz.allowThreads`) | **3.3 ms** | — |
| Pure Python `sum(range(n))` | 15.6 ms | 4.8× |
| Pure Python `for` loop | 45.9 ms | 14× |

Numbers vary by machine; run `python examples/bench.py` after building the demo.

## Install

```bash
pip install zig-maturin     # the build tool (pure Python)
# you also need Zig 0.14+ on PATH (https://ziglang.org/download/)
```

## Quick start

```bash
zig-maturin scaffold my_extension
cd my_extension
zig-maturin develop                 # build + install into the current venv
python -c "import my_extension; print(my_extension.hello())"
zig-maturin build                   # produce a wheel in dist/
```

Scaffolded projects use the **PEP 517 backend**
(`build-backend = "zig_maturin.buildapi"`), so the standard tools work too —
`pip install .`, `pip wheel .`, `python -m build` — with Zig on PATH:

```bash
pip install .                       # builds + installs the extension
python -m build                     # wheel + sdist in dist/
```

### One wheel for all CPython versions (abi3)

Set `abi3` in `[tool.zig-maturin]` to build against the stable ABI and ship a
single `cp312-abi3-<platform>` wheel that works on that CPython and every later
version:

```toml
[tool.zig-maturin]
abi3 = "3.12"
```

The framework already uses out-of-line refcounting and accessor functions (not
inline macros), so abi3 adds ~no runtime overhead here. Managed `__dict__` and
weakref need the GC pre-header and are unavailable under abi3 (cyclic GC of
`?*pz.PyObject` fields still works).

## Writing an extension

A module is declared with `pyModule` and exported with `exportModule`:

```zig
const std = @import("std");
const pz = @import("pyo3zig");

// Turn a Zig panic into a Python exception instead of crashing the interpreter.
pub const panic = pz.panic;

fn add(a: i64, b: i64) i64 {
    return a + b;
}

fn greet(name: []const u8) !pz.PyString {
    var buf: [256]u8 = undefined;
    return pz.PyString.init(try std.fmt.bufPrint(&buf, "Hello, {s}!", .{name}));
}

const Mod = pz.pyModule("my_extension", .{
    .doc = "An extension written in Zig.",
    .functions = &.{
        pz.pyFnNamed("add", add),
        pz.pyFnNamed("greet", greet),
    },
});

comptime {
    pz.exportModule(Mod);
}
```

Plain Zig functions are wrapped automatically: argument count, type conversion,
and error handling are all derived from the signature. Returning `!T` makes a
Zig error surface as a Python exception.

### Type conversions

| Zig | Python (argument) | Python (return) |
|---|---|---|
| `i8`..`i64`, `u8`..`u64` | `int` | `int` |
| `f32`, `f64` | `float` | `float` |
| `bool` | `bool` | `bool` |
| `enum` | `int` (validated; bad value → `ValueError`) | `int` |
| `pz.DateTime` | `datetime.datetime` | `datetime.datetime` |
| `[]const u8` | `str` / `bytes` / `bytearray` (borrowed) | `str` |
| `?T` | `T` or `None` | `T` or `None` |
| `[]T`, `[N]T` | `list` / `tuple` | `list` |
| tuple struct | `list` / `tuple` | `tuple` |
| plain struct | `dict` (by field name; field defaults honored) | `dict` (by field name) |
| `*MyClass` | an instance of `MyClass` (borrowed) | — |
| `?*pz.PyObject` | any object | any object (passthrough) |

Conversion is bidirectional: a `list`/`tuple` becomes a `[]T` argument, a `dict`
becomes a struct argument, and an instance of one of your classes can be passed
to a function as a `*MyClass` pointer. A type mismatch raises a precise
`TypeError` (`expected int, got str`).

### Keyword arguments and defaults

Zig reflection doesn't expose parameter names, so declare them explicitly:

```zig
fn power(base: i64, exp: i64) i64 { ... }

pz.pyFnKw("power", power, .{
    .args = &.{ "base", "exp" },
    .defaults = .{ .exp = @as(i64, 2) },   // optional, by name
});
```

```python
power(3)               # 9   (exp defaults to 2)
power(2, 10)           # 1024
power(base=5, exp=3)   # 125
```

### Classes

A Zig `extern struct` becomes a Python class. Fields are exposed as attributes;
declare optional dunder methods directly on the struct:

```zig
const Greeter = extern struct {
    val: i64,

    pub fn init(v: i64) Greeter {
        return .{ .val = v };
    }
    pub fn __str__(self: *Greeter) !pz.PyString { ... }
    pub fn __hash__(self: *Greeter) i64 { return self.val; }
    pub fn __eq__(self: *Greeter, other: *Greeter) bool { return self.val == other.val; }
    pub fn __deinit__(self: *Greeter) void { ... }   // called on GC
};

fn greet_method(self: *Greeter) !pz.PyString { ... }

const GreeterClass = pz.PyClass(Greeter, .{
    .methods = &.{ pz.wrapMethodNamed(Greeter, "greet", greet_method) },
    .readonly = &.{"val"},   // expose `val` read-only
});
```

Register the class in the module's `.classes` field.

**Hooks** (declared on the struct):

- Lifecycle / repr: `init`, `__deinit__` (called on GC), `__str__`, `__repr__`,
  `__hash__`, `__format__` (`format()` / f-string specs), `__call__` (callable
  instances), `__await__` (awaitable; `await obj` resolves to its return value)
  or `__await_delegate__(self) ?*PyObject` (delegate to a real awaitable and
  suspend to the event loop), `__aiter__`/`__anext__` (`async for x in obj`;
  `__anext__(self) -> ?T`),
  `__enter__`/`__exit__` (context manager, `with obj:`), `__reduce__`
  (pickle), `__getstate__`/`__setstate__`, `__bytes__` (`bytes(obj)`),
  `__floor__`/`__ceil__`/`__trunc__` (`math.*`), `__round__`,
  `__copy__`/`__deepcopy__` (`copy.copy`/`copy.deepcopy`, returning a fresh
  instance), `__fspath__` (`os.PathLike`), `__length_hint__`.
- Comparisons: `__eq__` (and `__ne__` derived from it), plus `__lt__`, `__le__`,
  `__gt__`, `__ge__` — define any subset (just `__lt__` enables `sorted()`).
  Defining `__eq__` without `__hash__` makes instances unhashable, as in Python.
- Container / iterator protocols: `__len__`, `__getitem__`, `__setitem__`,
  `__delitem__`, `__contains__`, `__iter__`, `__next__`, `__reversed__` (a type
  with `__next__` is its own iterator; `__getitem__` normalizes negative indices
  when `__len__` is present).
- Operators: `__add__`, `__sub__`, `__mul__`, `__truediv__`, `__floordiv__`,
  `__mod__`, `__pow__`, `__matmul__`, `__divmod__`, bitwise `__and__`/`__or__`/`__xor__`/
  `__lshift__`/`__rshift__`, unary `__neg__`/`__pos__`/`__abs__`/`__invert__`/
  `__bool__`, the matching in-place forms (`__iadd__`, `__imul__`, `__iand__`,
  `__ilshift__`, … — every operator has one), and conversions
  `__int__`/`__float__`/`__index__`. A binary op's second parameter can be the
  same type (`*Self`) or a scalar (e.g. `i64` for `vec * 2`); define
  `__radd__`/`__rsub__`/`__rmul__` for the reflected form (`2 * vec`). Operands
  that don't match yield `NotImplemented`. A result of type `Self` is wrapped
  into a new instance.
- Attributes: `__getattr__(self, name)` (consulted only when normal lookup
  fails) and `__setattr__(self, name, value)` (intercepts every assignment).
- Descriptors: `__get__(self, obj, objtype)`, `__set__(self, obj, value)`,
  `__delete__(self, obj)` — use an instance as a managed attribute on a class.
- Subclass hook: `__init_subclass__(cls)` — fires when a Python subclass is
  created (`cls` is the new subclass).
- Buffer: `__buffer__(self) []const u8` (read-only) or `__buffer_mut__(self)
  []u8` (writable) exposes a zero-copy view to `memoryview`/`bytes`/numpy.

Every class is also subscriptable for type hints — `MyClass[int]` yields a
`types.GenericAlias` (auto `__class_getitem__`).

**Cyclic GC:** a class storing a `?*pz.PyObject` field automatically gets
`Py_TPFLAGS_HAVE_GC` with `tp_traverse`/`tp_clear`, so reference cycles are
collectable. The framework owns one reference per field (incref on set, decref
on clear/dealloc); don't manually decref those fields in `__deinit__`. These GC
classes also support `weakref.ref(obj)` and a managed `__dict__` (arbitrary
Python attributes, GC-traced) — both cleared on dealloc. Value classes (no
PyObject field) have neither, keeping instances minimal.

**Subclassing from Python:** every class is `Py_TPFLAGS_BASETYPE`, so Python code
can `class Sub(MyClass): ...` and inherit fields, methods, and operators —
including classes with `__deinit__` or cyclic GC. Teardown runs in `tp_finalize`,
so CPython's `subtype_dealloc` correctly tears down a subclass's `__dict__`,
weakrefs, and GC; `__deinit__` fires for subclass instances and cycles through
them stay collectable. Wider integers `i65..i128`/`u65..u128` are supported as
arguments and return values (round-tripped through CPython's bigint).

**`PyClass` config:**

```zig
const Vec2Class = pz.PyClass(Vec2, .{
    .doc = "A 2D vector.",   // class docstring (help(Vec2))
    // keyword __init__ with defaults
    .init_args     = &.{ "x", "y" },
    .init_defaults = .{ .y = @as(i64, 0) },
    // keyword __call__ with defaults (when the class defines __call__)
    .call_args     = &.{ "k" },
    .call_defaults = .{ .k = @as(i64, 1) },
    // computed (read-only) properties
    .properties = &.{ .{ .name = "length_sq", .get = vec2_length_sq } },
    .methods = &.{
        pz.wrapMethodNamed(Vec2, "dot", vec2_dot),         // positional method
        pz.wrapMethodKw(Vec2, "scale", scale, .{ .args = &.{"k"} }),  // kwargs method
        pz.staticMethod("dims", vec2_dims),                // @staticmethod
        pz.classMethod(Vec2, "from_pair", vec2_from_pair), // @classmethod / alt constructor
    },
});
```

A `classMethod` whose Zig function returns `T` (or `!T`) is treated as an
**alternative constructor**: the returned struct is wrapped into a fresh
instance, so `Vec2.from_pair(...)` returns a `Vec2`.

**Enums:** expose a Zig `enum` as a real Python `enum.IntEnum` with
`pz.enumClass(MyEnum, "Name")`, then list it in `.classes` alongside your
`PyClass` types — each variant becomes a member (`Color.RED == 0`). (A plain
`enum` used as a function argument or return value converts as an `int`.)

### Releasing the GIL

Wrap a long pure-Zig computation in `pz.allowThreads` to release the GIL while
it runs, so other Python threads make progress:

```zig
fn heavy_sum(n: i64) i64 {
    return pz.allowThreads(compute_sum, .{n});
}
```

### Typed exceptions

Raise a specific built-in (or custom) Python exception, then return any Zig
error — the framework preserves the one you set instead of remapping it:

```zig
fn parse_positive(x: i64) !i64 {
    if (x <= 0) {
        pz.setError(pz.PyExc_ValueError(), "value must be positive");
        return error.NotPositive;
    }
    return x;
}
```

`pz.newException("mymod.MyError", null)` creates a custom exception type.

### Module constants

```zig
const Mod = pz.pyModule("my_extension", .{
    .constants = .{ .VERSION = "1.0", .MAX_ITEMS = @as(i64, 100) },
    .functions = &.{ ... },
    .classes   = &.{ GreeterClass },
});
```

### Error handling and panics

- A Zig **error** (`!T`) becomes a Python exception (mapped by kind: `error.Overflow`
  → `OverflowError`, etc.).
- A Zig **panic** (out-of-bounds, `@panic`, integer overflow in safe builds) would
  normally abort the whole interpreter. Opt into the safety net with
  `pub const panic = pz.panic;` and it becomes a `RuntimeError` instead — the
  interpreter stays alive. (Caveat: the recovery skips `defer`s between the panic
  site and the call boundary, so that window leaks.)

### Type stubs (`.pyi`)

Type hints are generated **at compile time** from your Zig signatures:

```zig
const STUB = pz.moduleStub(.{
    .{ .name = "add", .func = add, .args = &.{ "a", "b" } },
    .{ .name = "greet", .func = greet, .args = &.{"name"} },
}) ++ "\n" ++ pz.classStub(.{
    .name = "Greeter", .type = Greeter, .init = &.{"v"},
    .methods = .{ .{ .name = "greet", .func = greet_method } },
});
fn __pyi__() []const u8 { return STUB; }
// register pz.pyFnNamed("__pyi__", __pyi__)
```

`classStub` emits a `class` block (struct fields as attributes, `__init__`, and
methods) so type checkers see your classes too.

`zig-maturin build` calls `__pyi__()` on native builds and ships the resulting
`my_extension.pyi` inside the wheel, so type checkers see your signatures.

## CLI

| Command | Description |
|---|---|
| `zig-maturin scaffold <name>` | Create a new project (pyproject, build.zig, src/main.zig). |
| `zig-maturin develop` | Build and install into the current environment. |
| `zig-maturin build` | Build a wheel in `dist/`. |
| `zig-maturin sdist` | Build a source distribution. |

`build` / `develop` options: `--target <triple>` (repeatable), `--release`,
`--out <dir>`, and for cross-compilation `--python-include` / `--python-libdir`
/ `--python-lib`.

## Cross-compilation

Zig cross-compiles out of the box. Linux glibc targets are pinned so the
manylinux tag is honest:

```bash
zig-maturin build --target x86_64-linux-gnu --target aarch64-macos
# -> manylinux_2_28_x86_64, macosx_11_0_arm64
```

| Zig target | Wheel tag |
|---|---|
| `x86_64-linux-gnu` (→ `gnu.2.28`) | `manylinux_2_28_x86_64` |
| `aarch64-linux-gnu` | `manylinux_2_28_aarch64` |
| `x86_64-linux-musl` | `musllinux_1_2_x86_64` |
| `aarch64-macos` / `x86_64-macos` | `macosx_11_0_arm64` / `_x86_64` |
| `x86_64-windows` / `aarch64-windows` | `win_amd64` / `win_arm64` |

Cross-compiling needs the **target** Python's headers (and, on Windows, its
`pythonXY.lib`); supply them via `--python-include` / `--python-libdir` /
`--python-lib` or `[tool.zig-maturin]`. Native builds detect them via
`sysconfig` automatically.

## Configuration

```toml
[tool.zig-maturin]
module-name = "my_extension"     # default: project name
zig-source  = "src/main.zig"
# cross-compilation overrides (optional):
# python-include = "..."
# python-libdir  = "..."
# python-lib     = "python312"
```

## Requirements

- Python 3.12+
- Zig 0.14+ (tested with 0.16.0)
- Linux, macOS, or Windows

## License

MIT — [Ricardo Robles Fernández](https://github.com/rroblf01)

## Related

- [Maturin](https://github.com/PyO3/maturin), [PyO3](https://github.com/PyO3/pyo3) — the Rust originals
- [zig-python](https://github.com/dzfranklin/zig-python) — Python C-API bindings for Zig
