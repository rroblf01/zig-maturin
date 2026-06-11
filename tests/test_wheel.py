from __future__ import annotations

import zipfile

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


def test_build_wheel_mixed_layout(tmp_path):
    # A `<module_name>/` package nests the extension and ships the pure-Python
    # files alongside it.
    pkg = tmp_path / "mymod"
    pkg.mkdir()
    (pkg / "__init__.py").write_text("from .mymod import *\n")
    (pkg / "helpers.py").write_text("def util():\n    return 42\n")
    sub = pkg / "sub"
    sub.mkdir()
    (sub / "__init__.py").write_text("")

    so_path = tmp_path / "build.so"
    so_path.write_bytes(b"\x7fELF fake")

    wheel_path = build_wheel(
        module_name="mymod",
        version="0.1.0",
        description="",
        authors=[],
        so_path=so_path,
        python_tag="cp314",
        abi_tag="cp314",
        platform_tag="manylinux_2_28_x86_64",
        so_suffix=".so",
        output_dir=str(tmp_path / "dist"),
        pyi="x: int",
        py_package=pkg,
    )

    with zipfile.ZipFile(wheel_path, "r") as zf:
        names = zf.namelist()
        # Extension nested inside the package; not at the archive root.
        assert "mymod/mymod.so" in names
        assert "mymod.so" not in names
        assert "mymod/__init__.py" in names
        assert "mymod/helpers.py" in names
        assert "mymod/sub/__init__.py" in names
        assert "mymod/mymod.pyi" in names
        record = zf.read("mymod-0.1.0.dist-info/RECORD").decode()
        assert "mymod/mymod.so,sha256=" in record
        assert "mymod/helpers.py,sha256=" in record


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
