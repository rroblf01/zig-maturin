from __future__ import annotations

import os
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

    tool_zm = data.get("tool", {}).get("zig-maturin", {})
    cfg.module_name = tool_zm.get("module-name", "")
    cfg.python_source = tool_zm.get("python-source", "src")
    cfg.zig_source = tool_zm.get("zig-source", "src/main.zig")

    if not cfg.module_name:
        cfg.module_name = project.get("name", "my_module")

    return cfg
