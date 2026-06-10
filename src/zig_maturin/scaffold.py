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
    lib.root_module.addIncludePath(getPythonInclude(b));
    lib.root_module.addCSourceFile(.{{
        .file = zm_dep.path("pyo3zig_capi.c"),
        .flags = &.{{}},
    }});

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

fn hello() []const u8 {{
    return "Hello from Zig!";
}}

fn add(a: i64, b: i64) i64 {{
    return a + b;
}}

const Mod = pz.pyModule("{module_name}", .{{
    .functions = &[_]pz.PyMethodDef{{
        pz.pyFnNamed("hello", hello),
        pz.pyFnNamed("add", add),
    }},
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
