from __future__ import annotations

import hashlib
import shutil
import subprocess
from pathlib import Path

# URL of the zig-maturin Zig package, fetched as a Zig dependency.
ZIG_MATURIN_URL = "git+https://github.com/rroblf01/zig-maturin"

PYPROJECT_TEMPLATE = '''\
[project]
name = "{module_name}"
version = "0.1.0"
description = "A Python extension written in Zig"
requires-python = ">=3.12"
dependencies = []
license = {{ text = "MIT" }}

[build-system]
requires = ["uv_build>=0.11.15,<0.12.0"]
build-backend = "uv_build"

[tool.zig-maturin]
module-name = "{module_name}"
zig-source = "src/main.zig"
'''

BUILD_ZIG_TEMPLATE = '''\
const std = @import("std");

pub fn build(b: *std.Build) void {{
    const target = b.standardTargetOptions(.{{}});
    const optimize = b.standardOptimizeOption(.{{}});

    const zm_dep = b.dependency("zig-maturin", .{{
        .target = target,
        .optimize = optimize,
    }});

    const mod = b.createModule(.{{
        .root_source_file = b.path("{zig_source}"),
        .target = target,
        .optimize = optimize,
        .imports = &.{{
            .{{ .name = "zig-maturin", .module = zm_dep.module("zig-maturin") }},
            .{{ .name = "pyo3zig", .module = zm_dep.module("pyo3zig") }},
        }},
    }});

    const lib = b.addLibrary(.{{
        .name = "{module_name}",
        .linkage = .dynamic,
        .root_module = mod,
    }});

    // The high-level pyo3zig layer needs libc, the Python headers, and the
    // C shim that exposes Python's static symbols (PyExc_*, Py_None, ...).
    lib.root_module.link_libc = true;

    // zig-maturin passes these so the *target* Python's paths are used (it
    // knows them via sysconfig); fall back to python3-config on the host.
    const py_include = b.option([]const u8, "python-include", "Python include directory");
    const py_libdir = b.option([]const u8, "python-libdir", "Python library directory (Windows)");
    const py_lib = b.option([]const u8, "python-lib", "Python import library name (Windows)");

    const include: std.Build.LazyPath = if (py_include) |p|
        .{{ .cwd_relative = p }}
    else
        getPythonInclude(b);
    lib.root_module.addIncludePath(include);
    lib.root_module.addCSourceFile(.{{
        .file = zm_dep.path("pyo3zig_capi.c"),
        .flags = &.{{}},
    }});

    // CPython symbols are resolved against the interpreter at import time, so
    // they must be left undefined at link time (mandatory on macOS Mach-O).
    lib.linker_allow_shlib_undefined = true;
    if (target.result.os.tag == .windows) {{
        // PE cannot leave symbols undefined; link the Python import library.
        if (py_libdir) |d| lib.root_module.addLibraryPath(.{{ .cwd_relative = d }});
        if (py_lib) |l| lib.root_module.linkSystemLibrary(l, .{{}});
    }}

    b.installArtifact(lib);
}}

fn getPythonInclude(b: *std.Build) std.Build.LazyPath {{
    var exit_code: u8 = 0;
    const result = b.runAllowFail(&.{{ "python3-config", "--includes" }}, &exit_code, .inherit) catch {{
        @panic("python3-config not found or failed; is Python installed?");
    }};
    const output = std.mem.trim(u8, result, " \\n\\r");
    var iter = std.mem.tokenizeScalar(u8, output, ' ');
    while (iter.next()) |flag| {{
        if (std.mem.startsWith(u8, flag, "-I")) {{
            const path = flag[2..];
            if (path.len > 0) {{
                return .{{ .cwd_relative = b.pathFromRoot(path) }};
            }}
        }}
    }}
    @panic("python3-config returned no -I flag");
}}
'''

# Written without a `.dependencies` block; `zig fetch --save` populates it with
# the correct hash after scaffolding (see _add_dependency).
BUILD_ZIG_ZON_TEMPLATE = '''\
.{{
    .name = .{module_name},
    .version = "0.1.0",
    .minimum_zig_version = "0.14.0",
    .fingerprint = {fingerprint},
    .dependencies = .{{}},
    .paths = .{{
        "build.zig",
        "build.zig.zon",
        "src",
    }},
}}
'''

MAIN_ZIG_TEMPLATE = '''\
const std = @import("std");
const pz = @import("pyo3zig");

// Opt into the panic safety net: a Zig panic becomes a Python exception
// instead of aborting the interpreter.
pub const panic = pz.panic;

fn hello() []const u8 {{
    return "Hello from Zig!";
}}

fn add(a: i64, b: i64) i64 {{
    return a + b;
}}

// Returning `!T` makes a Zig error surface as a Python exception. Raise a
// specific one with pz.setError before returning the error.
fn divide(a: i64, b: i64) !i64 {{
    if (b == 0) {{
        pz.setError(pz.PyExc_ZeroDivisionError(), "division by zero");
        return error.DivByZero;
    }}
    return @divTrunc(a, b);
}}

// An `extern struct` becomes a Python class. Fields are attributes; `init` is
// the constructor.
const Counter = extern struct {{
    value: i64,

    pub fn init(start: i64) Counter {{
        return .{{ .value = start }};
    }}
}};

fn counter_incr(self: *Counter, by: i64) i64 {{
    self.value += by;
    return self.value;
}}

const CounterClass = pz.PyClass(Counter, .{{
    .init_args = &.{{"start"}},
    .methods = &[_]pz.PyMethodDef{{
        pz.wrapMethodNamed(Counter, "incr", counter_incr),
    }},
}});

// Compile-time type stubs shipped as `{module_name}.pyi` for IDEs/type checkers.
const STUB = pz.moduleStub(.{{
    .{{ .name = "hello", .func = hello }},
    .{{ .name = "add", .func = add, .args = &.{{ "a", "b" }} }},
    .{{ .name = "divide", .func = divide, .args = &.{{ "a", "b" }} }},
}}) ++ "\\n" ++ pz.classStub(.{{
    .name = "Counter",
    .type = Counter,
    .init = &.{{"start"}},
    .methods = .{{ .{{ .name = "incr", .func = counter_incr, .args = &.{{"by"}} }} }},
}});

fn __pyi__() []const u8 {{
    return STUB;
}}

const Mod = pz.pyModule("{module_name}", .{{
    .functions = &[_]pz.PyMethodDef{{
        pz.pyFnNamed("hello", hello),
        pz.pyFnNamed("add", add),
        pz.pyFnNamed("divide", divide),
        pz.pyFnNamed("__pyi__", __pyi__),
    }},
    .classes = &[_]type{{CounterClass}},
}});

comptime {{
    pz.exportModule(Mod);
}}
'''


def _fingerprint(name: str) -> str:
    """Derive a stable, non-zero Zig package fingerprint from the module name."""
    digest = int.from_bytes(hashlib.sha256(name.encode()).digest()[:8], "big")
    # Avoid the reserved 0x0 / all-ones values Zig rejects.
    if digest in (0x0, 0xFFFFFFFFFFFFFFFF):
        digest = 0x1
    return f"0x{digest:016x}"


def _add_dependency(root: Path) -> bool:
    """Populate the zig-maturin dependency (with hash) via `zig fetch --save`."""
    if shutil.which("zig") is None:
        return False
    result = subprocess.run(
        ["zig", "fetch", "--save=zig-maturin", ZIG_MATURIN_URL],
        cwd=root,
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        print("Warning: `zig fetch` failed; add the dependency manually:")
        print(f"  cd {root} && zig fetch --save=zig-maturin {ZIG_MATURIN_URL}")
        if result.stderr.strip():
            print(result.stderr.strip())
        return False
    return True


def scaffold_project(project_name: str, path: str = ".") -> None:
    root = Path(path).resolve() / project_name
    module_path = project_name.replace("-", "_")

    if root.exists():
        print(f"Error: Directory {root} already exists")
        raise SystemExit(1)

    src_dir = root / "src"
    src_dir.mkdir(parents=True, exist_ok=True)

    pyproject = PYPROJECT_TEMPLATE.format(module_name=module_path)
    (root / "pyproject.toml").write_text(pyproject)

    build_zig = BUILD_ZIG_TEMPLATE.format(
        module_name=module_path,
        zig_source="src/main.zig",
    )
    (root / "build.zig").write_text(build_zig)

    build_zon = BUILD_ZIG_ZON_TEMPLATE.format(
        module_name=module_path,
        fingerprint=_fingerprint(module_path),
    )
    (root / "build.zig.zon").write_text(build_zon)

    main_zig = MAIN_ZIG_TEMPLATE.format(module_name=module_path)
    (root / "src" / "main.zig").write_text(main_zig)

    fetched = _add_dependency(root)

    print(f"Created project: {root}")
    print(f"  {root / 'pyproject.toml'}")
    print(f"  {root / 'build.zig'}")
    print(f"  {root / 'build.zig.zon'}")
    print(f"  {root / 'src' / 'main.zig'}")
    print()
    print("To build:")
    if not fetched:
        print(f"  cd {project_name} && zig fetch --save=zig-maturin {ZIG_MATURIN_URL}")
        print("  zig-maturin build")
    else:
        print(f"  cd {project_name} && zig-maturin build")
