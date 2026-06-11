"""PEP 517 build backend for Zig-powered Python extensions.

Set in a project's pyproject.toml so `pip install .`, `pip wheel .`, and
`python -m build` work without invoking the `zig-maturin` CLI directly:

    [build-system]
    requires = ["zig-maturin"]
    build-backend = "zig_maturin.buildapi"

`zig` must be on PATH at build time. abi3 can be requested either in
`[tool.zig-maturin] abi3 = "3.12"` or via a config setting
(`--config-setting=abi3=3.12`).
"""

from __future__ import annotations

from pathlib import Path

from .builder import build_project
from .builder import build_sdist as _build_sdist
from .config import read_config


def _apply_config_settings(config, config_settings: dict | None) -> None:
    """Let `pip`/`build` pass `--config-setting key=value` overrides."""
    if not config_settings:
        return
    abi3 = config_settings.get("abi3")
    if abi3:
        config.abi3 = abi3 if isinstance(abi3, str) else "3.12"


# --- Mandatory hooks ------------------------------------------------------


def build_wheel(
    wheel_directory: str,
    config_settings: dict | None = None,
    metadata_directory: str | None = None,
) -> str:
    """Build a wheel for the running interpreter into `wheel_directory`."""
    config = read_config()
    _apply_config_settings(config, config_settings)
    wheels = build_project(config, [], release=True, out=wheel_directory)
    if not wheels:
        raise RuntimeError("zig-maturin: build produced no wheel")
    return Path(wheels[0]).name


def build_sdist(
    sdist_directory: str,
    config_settings: dict | None = None,
) -> str:
    """Build a source distribution into `sdist_directory`."""
    config = read_config()
    path = _build_sdist(config, out=sdist_directory)
    return Path(path).name


# --- Optional hooks -------------------------------------------------------


def get_requires_for_build_wheel(config_settings: dict | None = None) -> list[str]:
    # The Zig toolchain is a non-Python system dependency (must be on PATH);
    # there are no extra Python build requirements beyond zig-maturin itself.
    return []


def get_requires_for_build_sdist(config_settings: dict | None = None) -> list[str]:
    return []


def prepare_metadata_for_build_wheel(
    metadata_directory: str,
    config_settings: dict | None = None,
) -> str:
    """Write a `.dist-info` with just METADATA/WHEEL ahead of the full build."""
    from .wheel import generate_metadata, generate_wheel_metadata

    config = read_config()
    _apply_config_settings(config, config_settings)
    name = config.module_path
    dist_info = Path(metadata_directory) / f"{name}-{config.version}.dist-info"
    dist_info.mkdir(parents=True, exist_ok=True)
    (dist_info / "METADATA").write_text(
        generate_metadata(
            name,
            config.version,
            config.description,
            config.authors,
            requires_python=config.requires_python,
            license=config.license,
            classifiers=config.classifiers,
        )
    )
    # A placeholder tag; the real wheel records its precise tag.
    (dist_info / "WHEEL").write_text(
        generate_wheel_metadata("py3", "none", "any")
    )
    return dist_info.name
