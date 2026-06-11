from __future__ import annotations

import os
import platform
import subprocess
import sys
import sysconfig
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
        # Use the GNU (mingw) ABI bundled with Zig; the default Windows ABI can
        # be MSVC, which needs an MSVC toolchain that isn't present.
        return f"{arch}-windows-gnu"
    return f"{arch}-{os_name}"


# manylinux floor used when a glibc-pinned Linux target doesn't specify one.
# glibc 2.28 == manylinux_2_28 (RHEL 8 / Debian 10 era) — broad compatibility.
DEFAULT_GLIBC = "2.28"


def normalize_target(target: str) -> str:
    """Pin glibc on Linux glibc targets so the wheel is portable and its
    manylinux tag is truthful. Building against a specific glibc (Zig's
    `gnu.X.Y` syntax) guarantees the binary needs no newer symbols than that
    floor. musl and non-Linux targets are left untouched.
    """
    if "linux" in target and "gnu" in target and "gnu." not in target:
        return f"{target}.{DEFAULT_GLIBC}"
    return target


def _glibc_from_target(target: str) -> str:
    for part in target.split("-"):
        if part.startswith("gnu."):
            return part[len("gnu."):]
    return DEFAULT_GLIBC


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
        # Derive the manylinux tag from the pinned glibc version so the tag
        # reflects what the binary actually requires.
        glibc_tag = _glibc_from_target(target).replace(".", "_")
        return f"manylinux_{glibc_tag}_{plat_arch}"


def python_build_options(config: ZigMaturinConfig, target: str) -> list[str]:
    """`-D` flags telling build.zig where the *target* Python's headers/libs are.

    For a native build (target OS == host OS), `sysconfig` is authoritative on
    every platform — including Windows, where `python3-config` does not exist.
    For cross-compilation, the target Python paths must be supplied explicitly
    via [tool.zig-maturin] (python-include / python-libdir / python-lib).
    """
    opts: list[str] = []
    is_windows_target = "windows" in target

    include = config.python_include or sysconfig.get_paths().get("include", "")
    if include:
        opts.append(f"-Dpython-include={include}")

    if is_windows_target:
        libdir = config.python_libdir
        lib = config.python_lib
        if not libdir and sys.platform == "win32":
            # On Windows, the import library lives in <base>/libs/pythonXY.lib.
            libdir = str(Path(sys.base_prefix) / "libs")
        if not lib and sys.platform == "win32":
            lib = f"python{sys.version_info.major}{sys.version_info.minor}"
        if libdir:
            opts.append(f"-Dpython-libdir={libdir}")
            if lib:
                lib_file = Path(libdir) / f"{lib}.lib"
                if not lib_file.exists():
                    print(
                        f"Warning: expected import library not found: {lib_file}. "
                        "Linking will fail; check the target Python ships its .lib."
                    )
        if lib:
            opts.append(f"-Dpython-lib={lib}")
        elif not config.python_lib:
            print(
                "Warning: Windows target without python-lib; set "
                "[tool.zig-maturin] python-libdir/python-lib for cross builds."
            )

    return opts


def target_to_so_suffix(target: str, abi3: bool = False) -> str:
    parts = target.split("-")
    os_part = parts[1] if len(parts) > 1 else "linux"

    if os_part == "windows":
        # Windows extensions are .pyd regardless; the wheel's abi3 tag marks it.
        return ".pyd"
    # The `.abi3.so` suffix makes the loader pick this single file on any
    # compatible CPython (the stable-ABI naming convention).
    return ".abi3.so" if abi3 else ".so"


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

    # abi3: one stable-ABI wheel tagged at the configured minimum version.
    abi3 = bool(config.abi3)
    if abi3:
        abi3_minor = config.abi3.split(".")[1] if "." in config.abi3 else "12"
        abi3_python_tag = f"cp3{abi3_minor}"

    os.makedirs(out, exist_ok=True)

    for target in targets:
        target = normalize_target(target)
        optimize = "ReleaseSafe" if release else "Debug"

        print(f"Building for target: {target}")
        cmd = [
            "zig",
            "build",
            f"-Dtarget={target}",
            f"-Doptimize={optimize}",
            *(["-Dabi3=" + config.abi3] if abi3 else []),
            *python_build_options(config, target),
        ]
        print(f"  $ {' '.join(cmd)}")

        result = subprocess.run(
            cmd,
            cwd=root,
            capture_output=True,
            text=True,
        )

        if result.returncode != 0:
            print(f"Build failed for target {target} (exit {result.returncode}):")
            print(f"--- zig stdout ---\n{result.stdout or '(empty)'}")
            print(f"--- zig stderr ---\n{result.stderr or '(empty)'}")
            raise SystemExit(1)

        print(result.stdout)
        if result.stderr:
            print(result.stderr, file=sys.stderr)

        mod_name = config.module_path
        lib_dir = root / "zig-out" / "lib"
        bin_dir = root / "zig-out" / "bin"

        # Pick the artifact that matches THIS target, not a stale one from a
        # previous build of a different platform. Zig emits the Windows .dll
        # under bin/, shared objects under lib/.
        if "windows" in target:
            candidates = [bin_dir / f"{mod_name}.dll"]
        elif "macos" in target or "darwin" in target:
            candidates = [lib_dir / f"lib{mod_name}.dylib"]
        else:
            candidates = [lib_dir / f"lib{mod_name}.so"]

        built_so = next((c for c in candidates if c.exists()), None)

        if built_so is None:
            print(
                f"Warning: Could not find compiled artifact for {target}. "
                f"Looked for: {', '.join(str(c) for c in candidates)}"
            )
            for d in (bin_dir, lib_dir):
                if d.exists():
                    print(f"Contents of {d}:")
                    for f in d.iterdir():
                        print(f"  {f.name}")
            continue

        platform_tag = target_to_platform_tag(target)
        so_suffix = target_to_so_suffix(target, abi3=abi3)
        if abi3:
            python_tag = abi3_python_tag
            abi_tag = "abi3"
        else:
            python_tag = python_version
            abi_tag = python_version

        # Native builds: embed the comptime-generated type stub. Cross builds
        # can't import the artifact, so this returns None and is skipped.
        pyi = extract_stub(built_so, mod_name, so_suffix)

        wheel_path = build_wheel(
            module_name=mod_name,
            version=config.version,
            description=config.description,
            authors=config.authors,
            so_path=built_so,
            python_tag=python_tag,
            abi_tag=abi_tag,
            platform_tag=platform_tag,
            so_suffix=so_suffix,
            output_dir=out,
            requires_python=config.requires_python,
            license=config.license,
            classifiers=config.classifiers,
            pyi=pyi,
        )
        wheels.append(wheel_path)
        print(f"Created wheel: {wheel_path}")

        if develop:
            install_wheel_develop(wheel_path, mod_name, built_so, so_suffix)

    return wheels


def extract_stub(so_path: Path, module_name: str, so_suffix: str) -> str | None:
    """Import the freshly-built module and read its comptime `__pyi__()` stub.

    Only works for native builds (the artifact must be importable on this host);
    cross-built artifacts fail to import and are skipped silently.
    """
    import shutil
    import tempfile

    tmp = Path(tempfile.mkdtemp())
    dest = tmp / f"{module_name}{so_suffix if so_suffix != '.pyd' else '.so'}"
    try:
        shutil.copy2(so_path, dest)
        code = (
            f"import sys; sys.path.insert(0, {str(tmp)!r}); import {module_name} as m; "
            f"print(m.__pyi__(), end='') if hasattr(m, '__pyi__') else None"
        )
        result = subprocess.run(
            [sys.executable, "-c", code], capture_output=True, text=True
        )
        if result.returncode == 0 and result.stdout.strip():
            return result.stdout
    except Exception:
        pass
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
    return None


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
