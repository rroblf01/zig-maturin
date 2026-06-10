from __future__ import annotations

import hashlib
import os
import zipfile
from pathlib import Path


def build_wheel(
    module_name: str,
    version: str,
    description: str,
    authors: list[dict[str, str]],
    so_path: Path,
    python_tag: str,
    abi_tag: str,
    platform_tag: str,
    so_suffix: str,
    output_dir: str = "dist",
) -> Path:
    wheel_dir = Path(output_dir)
    wheel_dir.mkdir(parents=True, exist_ok=True)

    wheel_name = f"{module_name}-{version}-{python_tag}-{abi_tag}-{platform_tag}.whl"
    wheel_path = wheel_dir / wheel_name

    if so_path.suffix == ".pyd":
        so_name = f"{module_name}.pyd"
    else:
        so_name = f"{module_name}.so"

    dist_info = f"{module_name}-{version}.dist-info"
    records: list[str] = []

    with zipfile.ZipFile(wheel_path, "w", zipfile.ZIP_DEFLATED) as zf:
        zf.writestr(f"{dist_info}/WHEEL", generate_wheel_metadata())
        records.append((f"{dist_info}/WHEEL", True))

        metadata = generate_metadata(module_name, version, description, authors)
        zf.writestr(f"{dist_info}/METADATA", metadata)
        records.append((f"{dist_info}/METADATA", True))

        entry_points = generate_entry_points(module_name)
        if entry_points:
            zf.writestr(f"{dist_info}/entry_points.txt", entry_points)
            records.append((f"{dist_info}/entry_points.txt", True))

        so_data = so_path.read_bytes()
        zf.writestr(f"{module_name}/{so_name}", so_data)
        so_hash = hashlib.sha256(so_data).hexdigest()
        so_len = len(so_data)
        records.append((f"{module_name}/{so_name}", False, so_hash, so_len))

        record_lines = []
        for entry in records:
            if entry[1] is True:
                record_lines.append(f"{entry[0]},,")
            else:
                record_lines.append(
                    f"{entry[0]},sha256={entry[2]},{entry[3]}"
                )
        record_content = "\n".join(record_lines) + "\n"

        record_hash = hashlib.sha256(record_content.encode()).hexdigest()
        record_len = len(record_content.encode())
        record_lines.append(
            f"{dist_info}/RECORD,sha256={record_hash},{record_len}"
        )
        zf.writestr(f"{dist_info}/RECORD", "\n".join(record_lines) + "\n")

    return wheel_path


def generate_wheel_metadata() -> str:
    return """Wheel-Version: 1.0
Generator: zig-maturin 0.1.0
Root-Is-Purelib: false
Tag: {python_tag}-{abi_tag}-{platform_tag}
"""


def generate_metadata(
    module_name: str,
    version: str,
    description: str,
    authors: list[dict[str, str]],
) -> str:
    lines = [
        "Metadata-Version: 2.4",
        f"Name: {module_name}",
        f"Version: {version}",
        f"Summary: {description or ''}",
    ]
    for author in authors:
        name = author.get("name", "")
        email = author.get("email", "")
        if email:
            lines.append(f"Author-Email: {name} <{email}>")
        else:
            lines.append(f"Author: {name}")
    return "\n".join(lines) + "\n"


def generate_entry_points(module_name: str) -> str | None:
    return None
