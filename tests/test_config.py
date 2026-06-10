from __future__ import annotations

import os
import tempfile
from pathlib import Path

from zig_maturin.config import find_project_root, read_config


def test_find_project_root():
    original = Path.cwd()
    try:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp) / "myproject"
            root.mkdir()
            (root / "pyproject.toml").write_text("[project]\nname = \"test\"\n")

            sub = root / "subdir"
            sub.mkdir()
            os.chdir(str(sub))
            result = find_project_root()
            assert result == root.resolve()
    finally:
        os.chdir(str(original))


def test_read_config_defaults():
    original = Path.cwd()
    try:
        with tempfile.TemporaryDirectory() as tmp:
            (Path(tmp) / "pyproject.toml").write_text("""\
[project]
name = "mymod"
version = "0.2.0"
description = "Test module"

[tool.zig-maturin]
module-name = "mymod"
zig-source = "src/main.zig"
""")
            os.chdir(tmp)
            config = read_config()
            assert config.module_name == "mymod"
            assert config.module_path == "mymod"
            assert config.version == "0.2.0"
            assert config.description == "Test module"
            assert config.zig_source == "src/main.zig"
    finally:
        os.chdir(str(original))
