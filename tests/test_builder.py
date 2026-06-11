from __future__ import annotations

from zig_maturin.builder import get_host_target, target_to_platform_tag


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
