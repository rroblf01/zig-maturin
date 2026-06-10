const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const zm_mod = b.addModule("zig-maturin", .{
        .root_source_file = b.path("root.zig"),
        .target = target,
        .optimize = optimize,
    });

    const pz_mod = b.addModule("pyo3zig", .{
        .root_source_file = b.path("pyo3zig/root.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "zig-maturin", .module = zm_mod },
        },
    });

    const example_mod = b.createModule(.{
        .root_source_file = b.path("example.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "zig-maturin", .module = zm_mod },
            .{ .name = "pyo3zig", .module = pz_mod },
        },
    });

    const lib = b.addLibrary(.{
        .name = "ziggreet",
        .linkage = .dynamic,
        .root_module = example_mod,
    });

    b.installArtifact(lib);

    const pyo3zig_example_mod = b.createModule(.{
        .root_source_file = b.path("pyo3zig_example.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "pyo3zig", .module = pz_mod },
        },
    });

    const pyo3zig_lib = b.addLibrary(.{
        .name = "pyo3zig_demo",
        .linkage = .dynamic,
        .root_module = pyo3zig_example_mod,
    });
    pyo3zig_lib.root_module.link_libc = true;
    pyo3zig_lib.root_module.addIncludePath(.{ .cwd_relative = "/usr/include/python3.14" });
    pyo3zig_lib.root_module.addCSourceFile(.{ .file = b.path("pyo3zig_capi.c"), .flags = &.{} });

    b.installArtifact(pyo3zig_lib);
}
