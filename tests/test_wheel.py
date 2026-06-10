from __future__ import annotations

import tempfile
import zipfile
from pathlib import Path

from zig_maturin.wheel import build_wheel, generate_metadata, generate_wheel_metadata


def test_generate_metadata():
    meta = generate_metadata("testmod", "0.1.0", "A test module", [{"name": "Test Author", "email": "test@example.com"}])
    assert "Name: testmod" in meta
    assert "Version: 0.1.0" in meta
    assert "Summary: A test module" in meta
    assert "Test Author" in meta


def test_generate_wheel_metadata():
    meta = generate_wheel_metadata("cp314", "cp314", "manylinux_2_28_x86_64")
    assert "Wheel-Version: 1.0" in meta
    assert "zig-maturin" in meta
    assert "Tag: cp314-cp314-manylinux_2_28_x86_64" in meta
    assert "{python_tag}" not in meta


def test_build_wheel(tmp_path):
    so_content = b"\x7fELF\x00\x00\x00\x00\x00\x00\x00\x00\x00"
    so_path = tmp_path / "testmod.so"
    so_path.write_bytes(so_content)

    output_dir = tmp_path / "dist"
    wheel_path = build_wheel(
        module_name="testmod",
        version="0.1.0",
        description="Test",
        authors=[{"name": "Author"}],
        so_path=so_path,
        python_tag="cp312",
        abi_tag="cp312",
        platform_tag="manylinux_2_28_x86_64",
        so_suffix=".so",
        output_dir=str(output_dir),
    )

    assert wheel_path.exists()
    assert "testmod-0.1.0-cp312-cp312-manylinux_2_28_x86_64" in wheel_path.name

    with zipfile.ZipFile(wheel_path, "r") as zf:
        names = zf.namelist()
        # Extension lives at the archive root so `import testmod` loads it.
        assert "testmod.so" in names
        assert "testmod/testmod.so" not in names
        assert "testmod-0.1.0.dist-info/METADATA" in names
        assert "testmod-0.1.0.dist-info/WHEEL" in names
        assert "testmod-0.1.0.dist-info/RECORD" in names


def test_build_wheel_for_different_platforms(tmp_path):
    so_content = b"dummy"
    so_path = tmp_path / "mod.so"
    so_path.write_bytes(so_content)

    for (platform, suffix) in [
        ("manylinux_2_28_aarch64", ".so"),
        ("macosx_11_0_arm64", ".so"),
        ("win_amd64", ".pyd"),
    ]:
        wheel_path = build_wheel(
            module_name="mymod",
            version="0.1.0",
            description="",
            authors=[],
            so_path=so_path,
            python_tag="cp314",
            abi_tag="cp314",
            platform_tag=platform,
            so_suffix=suffix,
            output_dir=str(tmp_path / "dist"),
        )
        assert platform in wheel_path.name
