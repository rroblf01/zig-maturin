from __future__ import annotations

import shutil

import pytest

from zig_maturin.builder import get_host_target, target_to_platform_tag, zig_command


def test_zig_command_prefers_path_zig(monkeypatch):
    monkeypatch.setattr(shutil, "which", lambda name: "/usr/bin/zig")
    assert zig_command() == ["zig"]


def test_zig_command_falls_back_to_ziglang(monkeypatch):
    import sys

    monkeypatch.setattr(shutil, "which", lambda name: None)
    pytest.importorskip("ziglang")
    assert zig_command() == [sys.executable, "-m", "ziglang"]


def test_zig_command_errors_without_toolchain(monkeypatch):
    monkeypatch.setattr(shutil, "which", lambda name: None)
    monkeypatch.setitem(__import__("sys").modules, "ziglang", None)
    # With ziglang import forced to fail, expect a clear SystemExit.
    import builtins

    real_import = builtins.__import__

    def fake_import(name, *a, **k):
        if name == "ziglang":
            raise ImportError("no ziglang")
        return real_import(name, *a, **k)

    monkeypatch.setattr(builtins, "__import__", fake_import)
    with pytest.raises(SystemExit):
        zig_command()


def test_build_requires_ziglang_when_no_system_zig(monkeypatch):
    from zig_maturin import buildapi

    monkeypatch.setattr(shutil, "which", lambda name: None)
    reqs = buildapi.get_requires_for_build_wheel()
    assert any("ziglang" in r for r in reqs)

    monkeypatch.setattr(shutil, "which", lambda name: "/usr/bin/zig")
    assert buildapi.get_requires_for_build_wheel() == []


def test_get_host_target():
    target = get_host_target()
    assert target is not None
    assert len(target.split("-")) >= 2


def test_target_to_platform_tag_linux():
    tag = target_to_platform_tag("x86_64-linux-gnu")
    assert "manylinux" in tag
    assert "x86_64" in tag


def test_target_to_platform_tag_macos():
    tag = target_to_platform_tag("aarch64-macos")
    assert "macosx" in tag
    assert "arm64" in tag


def test_target_to_platform_tag_windows():
    tag = target_to_platform_tag("x86_64-windows")
    assert "win" in tag
    assert "amd64" in tag


def test_target_to_platform_tag_arm_windows():
    tag = target_to_platform_tag("aarch64-windows")
    assert "win_arm64" in tag


def test_so_suffix_full_api():
    from zig_maturin.builder import target_to_so_suffix

    assert target_to_so_suffix("x86_64-linux-gnu") == ".so"
    assert target_to_so_suffix("aarch64-macos") == ".so"
    assert target_to_so_suffix("x86_64-windows") == ".pyd"


def test_so_suffix_abi3():
    from zig_maturin.builder import target_to_so_suffix

    # Stable-ABI naming: single file picked on any compatible CPython.
    assert target_to_so_suffix("x86_64-linux-gnu", abi3=True) == ".abi3.so"
    assert target_to_so_suffix("aarch64-macos", abi3=True) == ".abi3.so"
    # Windows extensions stay .pyd; the wheel's abi3 tag marks them.
    assert target_to_so_suffix("x86_64-windows", abi3=True) == ".pyd"


def test_pep517_backend_hooks_present():
    from zig_maturin import buildapi

    for hook in (
        "build_wheel",
        "build_sdist",
        "get_requires_for_build_wheel",
        "get_requires_for_build_sdist",
        "prepare_metadata_for_build_wheel",
    ):
        assert callable(getattr(buildapi, hook))


def test_config_reads_abi3(tmp_path, monkeypatch):
    from zig_maturin.config import read_config

    (tmp_path / "pyproject.toml").write_text(
        '[project]\nname = "demo"\nversion = "0.1.0"\n'
        '[tool.zig-maturin]\nmodule-name = "demo"\nabi3 = "3.12"\n'
    )
    monkeypatch.chdir(tmp_path)
    cfg = read_config()
    assert cfg.abi3 == "3.12"
