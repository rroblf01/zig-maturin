"""Download a Windows ARM64 CPython distribution from NuGet.

Used by CI to cross-compile an aarch64-windows wheel from an x86_64 runner
(zig.exe currently crashes when run natively on Windows/ARM64). The NuGet
`pythonarm64` package ships the headers and import library we need.

Usage:
    python ci/fetch_windows_python.py <minor> <dest_dir>
        <minor>    e.g. "3.12"
        <dest_dir> extraction directory

Prints `include`, `libdir`, and `lib` values as KEY=VALUE lines (suitable for
appending to $GITHUB_OUTPUT).
"""

import json
import sys
import urllib.request
import zipfile
from pathlib import Path

PACKAGE = "pythonarm64"
INDEX = f"https://api.nuget.org/v3-flatcontainer/{PACKAGE}/index.json"


def latest_for_minor(minor: str) -> str:
    with urllib.request.urlopen(INDEX, timeout=60) as resp:
        versions = json.load(resp)["versions"]
    matching = [v for v in versions if v.startswith(f"{minor}.")]
    if not matching:
        raise SystemExit(f"No {PACKAGE} version found for Python {minor}")
    # Sort by numeric (major, minor, patch); ignore pre-release suffixes.
    def key(v: str):
        nums = []
        for part in v.split("-")[0].split("."):
            nums.append(int(part) if part.isdigit() else 0)
        return nums

    return sorted(matching, key=key)[-1]


def main() -> None:
    minor, dest = sys.argv[1], Path(sys.argv[2])
    version = latest_for_minor(minor)
    url = f"https://api.nuget.org/v3-flatcontainer/{PACKAGE}/{version}/{PACKAGE}.{version}.nupkg"

    dest.mkdir(parents=True, exist_ok=True)
    nupkg = dest / "pkg.nupkg"
    print(f"Downloading {url}", file=sys.stderr)
    urllib.request.urlretrieve(url, nupkg)
    with zipfile.ZipFile(nupkg) as zf:
        zf.extractall(dest)

    tools = dest / "tools"
    include = tools / "include"
    libdir = tools / "libs"
    lib = f"python{minor.replace('.', '')}"

    lib_file = libdir / f"{lib}.lib"
    if not include.is_dir() or not lib_file.is_file():
        raise SystemExit(
            f"Expected {include} and {lib_file} in the {PACKAGE} package; got: "
            f"{[p.name for p in tools.iterdir()] if tools.is_dir() else 'no tools/'}"
        )

    print(f"include={include}")
    print(f"libdir={libdir}")
    print(f"lib={lib}")


if __name__ == "__main__":
    main()
