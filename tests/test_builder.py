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
