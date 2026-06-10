from __future__ import annotations

import os
import platform
import subprocess
import sys
from pathlib import Path

from .config import ZigMaturinConfig, find_project_root
from .wheel import build_wheel, generate_metadata


def get_host_target() -> str:
    machine = platform.machine().lower()
    system = platform.system().lower()

    arch_map = {
        "x86_64": "x86_64",
        "amd64": "x86_64",
        "aarch64": "aarch64",
        "arm64": "aarch64",
        "i386": "x86",
        "i686": "x86",
    }

    os_map = {
        "linux": "linux",
        "darwin": "macos",
        "windows": "windows",
    }

    arch = arch_map.get(machine, machine)
    os_name = os_map.get(system, system)

    if os_name == "linux":
        return f"{arch}-linux-gnu"
    elif os_name == "macos":
        return f"{arch}-macos"
    elif os_name == "windows":
        return f"{arch}-windows"
    return f"{arch}-{os_name}"


def target_to_platform_tag(target: str) -> str:
    parts = target.split("-")
    arch = parts[0]
    os_part = parts[1] if len(parts) > 1 else "linux"

    arch_map = {
        "x86_64": "x86_64",
        "aarch64": "aarch64",
        "arm64": "aarch64",
        "x86": "i686",
        "i686": "i686",
    }
    plat_arch = arch_map.get(arch, arch)

    if os_part == "macos":
        mac_arch = {"x86_64": "x86_64", "aarch64": "arm64"}.get(arch, arch)
        return f"macosx_11_0_{mac_arch}"
    elif os_part == "windows":
        arch_tag = {"x86_64": "amd64", "aarch64": "arm64"}.get(arch, arch)
        return f"win_{arch_tag}"
    else:
        if "musl" in target:
            return f"musllinux_1_2_{plat_arch}"
        return f"manylinux_2_28_{plat_arch}"


def target_to_so_suffix(target: str) -> str:
    parts = target.split("-")
    os_part = parts[1] if len(parts) > 1 else "linux"

    if os_part == "windows":
        return ".pyd"
    elif os_part == "macos":
        return ".so"
    return ".so"


def build_project(
    config: ZigMaturinConfig,
    targets: list[str],
    release: bool,
    out: str = "dist",
    develop: bool = False,
) -> list[Path]:
    root = find_project_root()

    if not targets:
        targets = [get_host_target()]

    python_version = f"cp{sys.version_info.major}{sys.version_info.minor}"
    wheels: list[Path] = []

    os.makedirs(out, exist_ok=True)

    for target in targets:
        optimize = "ReleaseSafe" if release else "Debug"

        print(f"Building for target: {target}")
        cmd = [
            "zig",
            "build",
            f"-Dtarget={target}",
            f"-Doptimize={optimize}",
        ]

        result = subprocess.run(
            cmd,
            cwd=root,
            capture_output=True,
            text=True,
        )

        if result.returncode != 0:
            print(f"Build failed for target {target}:")
            print(result.stderr)
            if result.stdout:
                print(result.stdout)
            raise SystemExit(1)

        print(result.stdout)
        if result.stderr:
            print(result.stderr, file=sys.stderr)

        lib_dir = root / "zig-out" / "lib"
        mod_name = config.module_path

        so_name_candidates = [
            f"lib{mod_name}.so",
            f"lib{mod_name}.dylib",
            f"{mod_name}.dll",
            f"lib{mod_name}.pdb",
        ]

        built_so = None
        for candidate in so_name_candidates:
            candidate_path = lib_dir / candidate
            if candidate_path.exists():
                built_so = candidate_path
                break

        if built_so is None:
            print(
                f"Warning: Could not find compiled shared library in {lib_dir}"
            )
            print("Contents of zig-out/lib:")
            if lib_dir.exists():
                for f in lib_dir.iterdir():
                    print(f"  {f.name}")
            continue

        platform_tag = target_to_platform_tag(target)
        so_suffix = target_to_so_suffix(target)
        abi_tag = python_version

        wheel_path = build_wheel(
            module_name=mod_name,
            version=config.version,
            description=config.description,
            authors=config.authors,
            so_path=built_so,
            python_tag=python_version,
            abi_tag=abi_tag,
            platform_tag=platform_tag,
            so_suffix=so_suffix,
            output_dir=out,
            requires_python=config.requires_python,
            license=config.license,
            classifiers=config.classifiers,
        )
        wheels.append(wheel_path)
        print(f"Created wheel: {wheel_path}")

        if develop:
            install_wheel_develop(wheel_path, mod_name, built_so, so_suffix)

    return wheels


def build_sdist(config: ZigMaturinConfig, out: str = "dist") -> Path:
    """Build a PEP 517 source distribution (.tar.gz) for `pip` source builds."""
    import tarfile

    root = find_project_root()
    mod_name = config.module_path
    os.makedirs(out, exist_ok=True)

    base = f"{mod_name}-{config.version}"
    sdist_path = Path(out) / f"{base}.tar.gz"

    # Files/dirs that make the project buildable from source.
    candidates = [
        "pyproject.toml",
        "build.zig",
        "build.zig.zon",
        "README.md",
        "LICENSE",
        config.python_source,
        str(Path(config.zig_source).parent),
    ]
    seen: set[str] = set()

    pkg_info = generate_metadata(
        mod_name,
        config.version,
        config.description,
        config.authors,
        requires_python=config.requires_python,
        license=config.license,
        classifiers=config.classifiers,
    )

    def _exclude(info: "tarfile.TarInfo") -> "tarfile.TarInfo | None":
        parts = Path(info.name).parts
        if "__pycache__" in parts or info.name.endswith((".pyc", ".pyo")):
            return None
        if "zig-out" in parts or ".zig-cache" in parts:
            return None
        return info

    with tarfile.open(sdist_path, "w:gz") as tar:
        for rel in candidates:
            src = root / rel
            if not src.exists() or rel in seen:
                continue
            seen.add(rel)
            tar.add(src, arcname=f"{base}/{rel}", filter=_exclude)

        info = tarfile.TarInfo(name=f"{base}/PKG-INFO")
        data = pkg_info.encode()
        info.size = len(data)
        import io

        tar.addfile(info, io.BytesIO(data))

    print(f"Created sdist: {sdist_path}")
    return sdist_path


def install_wheel_develop(
    wheel_path: Path, mod_name: str, so_path: Path, so_suffix: str = ".so"
) -> None:
    site_packages = Path(
        subprocess.check_output(
            [sys.executable, "-c", "import site; print(site.getsitepackages()[0])"],
            text=True,
        ).strip()
    )

    dest = site_packages / f"{mod_name}{so_suffix}"
    import shutil

    shutil.copy2(so_path, dest)
    print(f"Installed {so_path.name} -> {dest}")
