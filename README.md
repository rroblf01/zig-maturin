# zig-maturin

**Build and publish Zig-powered Python extensions with native cross-compilation.**

`zig-maturin` is a tool that compiles Zig code into Python native extensions and packages them as `.whl` (wheel) files — ready for `pip install`. Think of it as [Maturin](https://github.com/PyO3/maturin) for Zig.

## Why Zig?

| Feature | Rust + Maturin | Zig + zig-maturin |
|---|---|---|
| Cross-compilation | Complex: needs external linkers, toolchains, or Docker | **Built-in**: `zig build -Dtarget=aarch64-macos` works out of the box |
| Toolchain size | Gigabytes (rustc + LLVM) | A few megabytes (single Zig binary) |
| C ABI | Via `#[no_mangle]` and `extern "C"` | Native: Zig compiles directly to C-compatible shared libraries |

Zig's built-in cross-compilation lets you build wheels for **all platforms** from a single machine — no Docker, no extra toolchains, no linker setup.

## Quick Start

```bash
# Install zig-maturin
pip install zig-maturin

# Scaffold a new project
zig-maturin scaffold my_extension
cd my_extension

# Build and install in development mode
zig-maturin develop

# Test it
python -c "import my_extension; print(my_extension.hello())"
# → Hello from Zig!

# Build a wheel for distribution
zig-maturin build
# → dist/my_extension-0.1.0-cp314-cp314-manylinux_2_28_x86_64.whl

# Cross-compile for other platforms (no extra setup needed!)
zig-maturin build --target aarch64-macos --target x86_64-windows
# → dist/my_extension-0.1.0-cp314-cp314-macosx_11_0_arm64.whl
# → dist/my_extension-0.1.0-cp314-cp314-win_amd64.whl
```

## How it Works

1. **Write Zig code** — use the `zig-maturin` Zig package to access the Python C-API
2. **`zig-maturin build`** — compiles with `zig build` and packages the `.so` into a wheel
3. **`zig-maturin develop`** — compiles and installs directly into the current Python environment
4. **Cross-compile** — pass `--target <triple>` to build for any supported platform

## Writing a Python Extension in Zig

The `zig-maturin` Zig package provides low-level Python C-API bindings. Functions are exposed via the standard Python C extension pattern:

```zig
const zm = @import("zig-maturin");

fn hello(self: ?*zm.PyObject, args: ?*zm.PyObject) callconv(.c) ?*zm.PyObject {
    _ = self;
    _ = args;
    return zm.PyUnicode_FromString("Hello from Zig!");
}

pub export fn PyInit_my_extension() callconv(.c) ?*zm.PyObject {
    const methods = [_]zm.PyMethodDef{
        zm.method("hello", &hello, zm.METH_NOARGS, "Say hello"),
        .{ .ml_name = null, .ml_meth = null, .ml_flags = 0, .ml_doc = null },
    };
    var mod = zm.PyModuleDef{
        .m_base = zm.PyModuleDef_HEAD_INIT,
        .m_name = "my_extension",
        .m_doc = "A Python module written in Zig",
        .m_size = -1,
        .m_methods = @as(?[*]zm.PyMethodDef, @ptrCast(@constCast(&methods))),
        .m_slots = null,
        .m_traverse = null,
        .m_clear = null,
        .m_free = null,
    };
    return zm.PyModule_Create(&mod);
}
```

> **Note**: The `zig-maturin` package exposes the raw Python C-API as Zig extern functions. A higher-level "PyO3 for Zig" layer is planned for future releases.

## Available C-API Bindings

The Zig package wraps a comprehensive subset of the Python C-API:

| Category | Functions |
|---|---|
| **Module** | `PyModule_Create`, `PyModule_New`, `PyModule_AddObject`, `PyModule_AddIntConstant`, `PyModule_AddStringConstant` |
| **Ref counting** | `Py_INCREF`, `Py_DECREF`, `Py_XINCREF`, `Py_XDECREF`, `Py_NewRef`, `Py_IncRef`, `Py_DecRef` |
| **Strings** | `PyUnicode_FromString`, `PyUnicode_FromStringAndSize`, `PyUnicode_AsUTF8`, `PyUnicode_Check` |
| **Integers** | `PyLong_FromLong`, `PyLong_FromLongLong`, `PyLong_FromUnsignedLongLong`, `PyLong_AsLong`, `PyLong_AsLongLong`, `PyLong_Check` |
| **Floats** | `PyFloat_FromDouble`, `PyFloat_AsDouble`, `PyFloat_Check` |
| **Booleans** | `PyBool_FromLong`, `PyBool_Check` |
| **Exceptions** | `PyErr_SetString`, `PyErr_SetObject`, `PyErr_Occurred`, `PyErr_Clear` |
| **Objects** | `PyObject_GetAttrString`, `PyObject_SetAttrString`, `PyObject_CallObject`, `PyObject_Str`, `PyObject_IsTrue` |
| **Args** | `PyArg_ParseTuple`, `Py_BuildValue` |
| **Lists** | `PyList_New`, `PyList_Size`, `PyList_GetItem`, `PyList_SetItem`, `PyList_Append`, `PyList_Check` |
| **Dicts** | `PyDict_New`, `PyDict_SetItemString`, `PyDict_GetItemString`, `PyDict_Size`, `PyDict_Check` |
| **Tuples** | `PyTuple_New`, `PyTuple_Size`, `PyTuple_GetItem`, `PyTuple_SetItem` |

## Commands

### `zig-maturin scaffold <name>`

Creates a new project with:
- `pyproject.toml` — Python project configuration
- `build.zig` / `build.zig.zon` — Zig build configuration with `zig-maturin` dependency
- `src/main.zig` — Template module with a hello function

### `zig-maturin build`

Builds the extension and creates a `.whl` file.

- `--target <triple>` — cross-compile target (can be specified multiple times for multi-platform builds)
- `--release` — build in release mode
- `--out <dir>` — output directory (default: `dist`)

### `zig-maturin develop`

Builds the extension and installs it into the current Python environment's `site-packages`.

- `--target <triple>` — cross-compilation target (default: host native)
- `--release` — build in release mode

## Configuration

`zig-maturin` reads `[tool.zig-maturin]` from `pyproject.toml`:

```toml
[tool.zig-maturin]
module-name = "my_extension"      # Python module name (default: project name)
zig-source = "src/main.zig"       # Path to Zig source file
```

## Cross-Compilation Targets

`zig-maturin` maps Zig targets to Python wheel platform tags:

| Zig Target | Wheel Tag |
|---|---|
| `x86_64-linux-gnu` | `manylinux_2_28_x86_64` |
| `aarch64-linux-gnu` | `manylinux_2_28_aarch64` |
| `x86_64-linux-musl` | `musllinux_1_2_x86_64` |
| `aarch64-macos` | `macosx_11_0_arm64` |
| `x86_64-macos` | `macosx_11_0_x86_64` |
| `x86_64-windows` | `win_amd64` |
| `aarch64-windows` | `win_arm64` |

## Project Structure

```
my_extension/
├── pyproject.toml       # Python project config with [tool.zig-maturin]
├── build.zig            # Zig build file
├── build.zig.zon        # Zig package manifest
├── src/
│   └── main.zig         # Your Zig extension code
└── dist/                # Built wheels (after zig-maturin build)
```

## Requirements

- Python 3.12+
- Zig 0.14+ (tested with 0.16.0)
- Linux, macOS, or Windows

## License

MIT — [Ricardo Robles Fernández](https://github.com/rroblf01)

## Related Projects

- [Maturin](https://github.com/PyO3/maturin) — Build and publish Rust-powered Python extensions
- [PyO3](https://github.com/PyO3/pyo3) — Rust bindings for Python
- [zig-python](https://github.com/dzfranklin/zig-python) — Python C-API bindings for Zig
