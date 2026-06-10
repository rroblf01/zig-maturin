import sys
import click

from . import __version__
from .scaffold import scaffold_project
from .builder import build_project, build_sdist
from .config import read_config


@click.group()
@click.version_option(version=__version__, prog_name="zig-maturin")
def main():
    """Build and publish Zig-powered Python extensions."""


@main.command()
@click.argument("project_name")
@click.option(
    "--path",
    default=".",
    help="Directory to create the project in (default: current directory)",
)
def scaffold(project_name, path):
    """Create a new Zig Python extension project."""
    scaffold_project(project_name, path)


@main.command()
@click.option(
    "--target",
    default=None,
    multiple=True,
    help="Cross-compilation target (e.g. aarch64-macos). Can be specified multiple times.",
)
@click.option("--release", is_flag=True, default=False, help="Build in release mode")
@click.option(
    "--out",
    default="dist",
    help="Output directory for wheel files (default: dist)",
)
def build(target, release, out):
    """Build the Zig extension and package it into a wheel."""
    config = read_config()
    build_project(config, target, release, out)


@main.command()
@click.option(
    "--out",
    default="dist",
    help="Output directory for the sdist (default: dist)",
)
def sdist(out):
    """Build a source distribution (.tar.gz)."""
    config = read_config()
    build_sdist(config, out)


@main.command()
@click.option(
    "--target",
    default=None,
    help="Cross-compilation target (default: host native)",
)
@click.option("--release", is_flag=True, default=False, help="Build in release mode")
def develop(target, release):
    """Build and install the extension into the current Python environment."""
    config = read_config()
    build_project(config, [target] if target else [], release, develop=True)


if __name__ == "__main__":
    main()
