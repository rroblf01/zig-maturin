from __future__ import annotations

import os
from pathlib import Path

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

    const lib = b.addLibrary(.{{
        .name = "{module_name}",
        .linkage = .dynamic,
        .root_module = b.createModule(.{{
            .root_source_file = b.path("{zig_source}"),
            .target = target,
            .optimize = optimize,
        }}),
    }});

    const zm_dep = b.dependency("zig-maturin", .{{
        .target = target,
        .optimize = optimize,
    }});
    lib.root_module.addImport("zig-maturin", zm_dep.module("zig-maturin"));

    b.installArtifact(lib);
}}
'''

BUILD_ZIG_ZON_TEMPLATE = '''\
.{{
    .name = "{module_name}",
    .version = "0.1.0",
    .minimum_zig_version = "0.14.0",
    .fingerprint = 0x0000000000000000,
    .dependencies = .{{
        .@"zig-maturin" = .{{
            .url = "https://github.com/rroblf01/zig-maturin/archive/refs/tags/v0.1.0.tar.gz",
            .hash = "00000000000000000000000000000000000000000000000000000000000000000000",
        }},
    }},
    .paths = .{{
        "build.zig",
        "build.zig.zon",
        "src",
    }},
}}
'''

MAIN_ZIG_TEMPLATE = '''\
const std = @import("std");
const zm = @import("zig-maturin");

fn hello(self: ?*zm.PyObject, args: ?*zm.PyObject) callconv(.c) ?*zm.PyObject {{
    _ = self;
    _ = args;
    return zm.PyUnicode_FromString("Hello from Zig!");
}}

pub export fn PyInit_{module_name}() callconv(.c) ?*zm.PyObject {{
    const methods = [_]zm.PyMethodDef{{
        zm.method("hello", &hello, zm.METH_NOARGS, "Say hello"),
        .{{ .ml_name = null, .ml_meth = null, .ml_flags = 0, .ml_doc = null }},
    }};
    var mod = zm.PyModuleDef{{
        .m_base = zm.PyModuleDef_HEAD_INIT,
        .m_name = "{module_name}",
        .m_doc = "A Python module written in Zig",
        .m_size = -1,
        .m_methods = @as(?[*]zm.PyMethodDef, @ptrCast(@constCast(&methods))),
        .m_slots = null,
        .m_traverse = null,
        .m_clear = null,
        .m_free = null,
    }};
    return zm.PyModule_Create(&mod);
}}
'''


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

    build_zon = BUILD_ZIG_ZON_TEMPLATE.format(module_name=module_path)
    (root / "build.zig.zon").write_text(build_zon)

    main_zig = MAIN_ZIG_TEMPLATE.format(module_name=module_path)
    (root / "src" / "main.zig").write_text(main_zig)

    print(f"Created project: {root}")
    print(f"  {root / 'pyproject.toml'}")
    print(f"  {root / 'build.zig'}")
    print(f"  {root / 'build.zig.zon'}")
    print(f"  {root / 'src' / 'main.zig'}")
    print()
    print("To build:")
    print(f"  cd {project_name} && zig-maturin build")
