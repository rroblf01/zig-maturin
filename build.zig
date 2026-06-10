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

    const pyo3zig_example_mod = b.createModule(.{
        .root_source_file = b.path("pyo3zig_example.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "zig-maturin", .module = zm_mod },
            .{ .name = "pyo3zig", .module = pz_mod },
        },
    });

    const pyo3zig_lib = b.addLibrary(.{
        .name = "pyo3zig_demo",
        .linkage = .dynamic,
        .root_module = pyo3zig_example_mod,
    });
    pyo3zig_lib.root_module.link_libc = true;

    const python_include = getPythonInclude(b);
    pyo3zig_lib.root_module.addIncludePath(python_include);
    pyo3zig_lib.root_module.addCSourceFile(.{ .file = b.path("pyo3zig_capi.c"), .flags = &.{} });

    b.installArtifact(pyo3zig_lib);

    const test_step = b.step("test", "Run Python tests");
    const run_tests = b.addSystemCommand(&.{ "sh", "-c", "cp zig-out/lib/libpyo3zig_demo.so pyo3zig_demo.so && python3 tests/run_tests.py" });
    run_tests.step.dependOn(b.getInstallStep());
    test_step.dependOn(&run_tests.step);
}

fn getPythonInclude(b: *std.Build) std.Build.LazyPath {
    var exit_code: u8 = 0;
    const result = b.runAllowFail(&.{ "python3-config", "--includes" }, &exit_code, .inherit) catch {
        @panic("Failed to detect Python configuration: python3-config not found or failed");
    };
    const output = std.mem.trim(u8, result, " \n\r");
    var iter = std.mem.tokenizeScalar(u8, output, ' ');
    while (iter.next()) |flag| {
        if (std.mem.startsWith(u8, flag, "-I")) {
            const path = flag[2..];
            if (path.len > 0) {
                return .{ .cwd_relative = b.pathFromRoot(path) };
            }
        }
    }
    @panic("Could not find Python include path: python3-config returned no -I flag");
}
