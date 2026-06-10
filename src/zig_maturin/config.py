from __future__ import annotations

import tomllib
from dataclasses import dataclass, field
from pathlib import Path


@dataclass
class ZigMaturinConfig:
    module_name: str = ""
    python_source: str = "src"
    zig_source: str = "src/main.zig"
    version: str = "0.1.0"
    description: str = ""
    authors: list[dict[str, str]] = field(default_factory=list)
    requires_python: str = ""
    license: str = ""
    classifiers: list[str] = field(default_factory=list)
    readme: str = ""
    python_include: str = ""
    python_libdir: str = ""
    python_lib: str = ""

    @property
    def module_path(self) -> str:
        return self.module_name.replace("-", "_")


def find_project_root() -> Path:
    cwd = Path.cwd().resolve()
    for parent in [cwd] + list(cwd.parents):
        if (parent / "pyproject.toml").exists():
            return parent
    msg = "No pyproject.toml found in current or parent directories"
    raise FileNotFoundError(msg)


def read_config() -> ZigMaturinConfig:
    root = find_project_root()
    pyproject_path = root / "pyproject.toml"

    with open(pyproject_path, "rb") as f:
        data = tomllib.load(f)

    cfg = ZigMaturinConfig()

    project = data.get("project", {})
    cfg.version = project.get("version", "0.1.0")
    cfg.description = project.get("description", "")
    cfg.authors = project.get("authors", [])
    cfg.requires_python = project.get("requires-python", "")
    cfg.classifiers = project.get("classifiers", [])

    # license may be a string (PEP 639) or a {text=...}/{file=...} table.
    lic = project.get("license", "")
    if isinstance(lic, dict):
        cfg.license = lic.get("text", "")
    else:
        cfg.license = lic

    readme = project.get("readme", "")
    if isinstance(readme, dict):
        cfg.readme = readme.get("text", "")
    else:
        cfg.readme = readme

    tool_zm = data.get("tool", {}).get("zig-maturin", {})
    cfg.module_name = tool_zm.get("module-name", "")
    cfg.python_source = tool_zm.get("python-source", "src")
    cfg.zig_source = tool_zm.get("zig-source", "src/main.zig")
    # Optional target-Python overrides (needed for cross-compilation).
    cfg.python_include = tool_zm.get("python-include", "")
    cfg.python_libdir = tool_zm.get("python-libdir", "")
    cfg.python_lib = tool_zm.get("python-lib", "")

    if not cfg.module_name:
        cfg.module_name = project.get("name", "my_module")

    return cfg
