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
| `[]const u8` | `str` / `bytes` (borrowed) | `str` |
| `?T` | `T` or `None` | `T` or `None` |
| `[]T`, `[N]T` | — | `list` |
| tuple struct | — | `tuple` |
| plain struct | — | `dict` (by field name) |
| `?*pz.PyObject` | any object | any object (passthrough) |

Container **arguments** (`list` → `[]T`) are on the roadmap; accept `?*pz.PyObject`
for now and convert manually.

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

Register the class in the module's `.classes` field. Supported hooks: `init`,
`__deinit__`, `__str__`, `__repr__`, `__hash__`, `__eq__`.

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
});
fn __pyi__() []const u8 { return STUB; }
// register pz.pyFnNamed("__pyi__", __pyi__)
```

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
