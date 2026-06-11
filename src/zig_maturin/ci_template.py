"""Generate a GitHub Actions workflow that builds and publishes wheels for a
zig-maturin extension project across Linux / macOS / Windows."""

from __future__ import annotations

WHEELS_WORKFLOW = """\
name: Wheels

on:
  push:
    branches: [main]
    tags: ["v*.*.*"]
  pull_request:
  workflow_dispatch:

permissions:
  contents: read

jobs:
  wheels:
    name: ${{{{ matrix.os }}}} / py${{{{ matrix.python-version }}}}
    strategy:
      fail-fast: false
      matrix:
        os: [ubuntu-latest, macos-latest, windows-latest]
        python-version: ["3.12", "3.13", "3.14"]
    runs-on: ${{{{ matrix.os }}}}
    steps:
      - uses: actions/checkout@v6
      - uses: actions/setup-python@v6
        with:
          python-version: ${{{{ matrix.python-version }}}}
      # No system Zig needed: zig-maturin pulls in the `ziglang` wheel.
      - name: Build wheel
        run: |
          pip install zig-maturin
          zig-maturin build --release --out dist
      - uses: actions/upload-artifact@v7
        with:
          name: wheels-${{{{ matrix.os }}}}-py${{{{ matrix.python-version }}}}
          path: dist/*.whl

  sdist:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v6
      - uses: actions/setup-python@v6
        with:
          python-version: "3.12"
      - name: Build sdist
        run: |
          pip install zig-maturin
          zig-maturin sdist --out dist
      - uses: actions/upload-artifact@v7
        with:
          name: sdist
          path: dist/*.tar.gz

  publish:
    name: Publish to PyPI
    if: startsWith(github.ref, 'refs/tags/v')
    needs: [wheels, sdist]
    runs-on: ubuntu-latest
    environment:
      name: pypi
      url: https://pypi.org/project/{project}/
    permissions:
      id-token: write   # PyPI Trusted Publishing (OIDC); no token needed
    steps:
      - uses: actions/download-artifact@v8
        with:
          path: dist
          merge-multiple: true
      - uses: pypa/gh-action-pypi-publish@release/v1
        with:
          packages-dir: dist
"""


def generate_wheels_workflow(project: str) -> str:
    """Render the wheels workflow for `project` (the PyPI distribution name)."""
    return WHEELS_WORKFLOW.format(project=project)
