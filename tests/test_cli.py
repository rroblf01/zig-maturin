from __future__ import annotations

import subprocess
import sys
import tempfile
from pathlib import Path


ZIG_MATURIN = [sys.executable, "-m", "zig_maturin"]


def test_cli_help():
    result = subprocess.run(
        [*ZIG_MATURIN, "--help"],
        capture_output=True,
        text=True,
    )
    assert result.returncode == 0
    assert "Build and publish" in result.stdout
    assert "scaffold" in result.stdout
    assert "build" in result.stdout


def test_cli_version():
    result = subprocess.run(
        [*ZIG_MATURIN, "--version"],
        capture_output=True,
        text=True,
    )
    assert result.returncode == 0
    assert "zig-maturin" in result.stdout


def test_cli_build_exposes_abi3_flag():
    result = subprocess.run(
        [*ZIG_MATURIN, "build", "--help"],
        capture_output=True,
        text=True,
    )
    assert result.returncode == 0
    assert "--abi3" in result.stdout
    assert "stable-ABI" in result.stdout


def test_generate_ci_workflow_is_valid_yaml():
    from zig_maturin.ci_template import generate_wheels_workflow

    pytest = __import__("pytest")
    yaml = pytest.importorskip("yaml")
    content = generate_wheels_workflow("mypkg")
    doc = yaml.safe_load(content)
    assert set(doc["jobs"]) == {"wheels", "sdist", "publish"}
    assert "${{" in content  # GitHub Actions expressions preserved
    assert "{project}" not in content  # template fully rendered
    assert "mypkg" in content


def test_scaffold_creates_project():
    with tempfile.TemporaryDirectory() as tmp:
        result = subprocess.run(
            [*ZIG_MATURIN, "scaffold", "test_project", "--path", tmp],
            capture_output=True,
            text=True,
        )
        assert result.returncode == 0

        project_dir = Path(tmp) / "test_project"
        assert (project_dir / "pyproject.toml").exists()
        assert (project_dir / "build.zig").exists()
        assert (project_dir / "build.zig.zon").exists()
        assert (project_dir / "src" / "main.zig").exists()

        pyproject = (project_dir / "pyproject.toml").read_text()
        assert "test_project" in pyproject

        main_zig = (project_dir / "src" / "main.zig").read_text()
        assert 'pz.pyModule("test_project"' in main_zig
        assert "pz.exportModule" in main_zig


def test_scaffold_fails_on_existing():
    with tempfile.TemporaryDirectory() as tmp:
        project_dir = Path(tmp) / "existing"
        project_dir.mkdir()
        result = subprocess.run(
            [*ZIG_MATURIN, "scaffold", "existing", "--path", tmp],
            capture_output=True,
            text=True,
        )
        assert result.returncode != 0


def test_scaffold_project_name_with_hyphen():
    with tempfile.TemporaryDirectory() as tmp:
        result = subprocess.run(
            [*ZIG_MATURIN, "scaffold", "my-zig-mod", "--path", tmp],
            capture_output=True,
            text=True,
        )
        assert result.returncode == 0
        project_dir = Path(tmp) / "my-zig-mod"
        assert (project_dir / "src" / "main.zig").exists()
        main_zig = (project_dir / "src" / "main.zig").read_text()
        assert 'pz.pyModule("my_zig_mod"' in main_zig
