const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const zm_mod = b.addModule("zig-maturin", .{
        .root_source_file = b.path("root.zig"),
        .target = target,
        .optimize = optimize,
    });

    // abi3 / Limited API: a CPython min version like "3.12" builds against the
    // stable ABI. Empty = full API (per-version).
    const abi3 = b.option([]const u8, "abi3", "Limited API minimum version, e.g. 3.12") orelse "";
    const build_options = b.addOptions();
    build_options.addOption(bool, "abi3", abi3.len > 0);
    const build_options_mod = build_options.createModule();

    const pz_mod = b.addModule("pyo3zig", .{
        .root_source_file = b.path("pyo3zig/root.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "zig-maturin", .module = zm_mod },
            .{ .name = "build_options", .module = build_options_mod },
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

    // Optional overrides so the Python tooling (which knows its own sysconfig
    // paths on every OS) can supply target-correct include/lib locations.
    // Falls back to `python3-config` on the host when not provided.
    const py_include = b.option([]const u8, "python-include", "Python include directory");
    const py_libdir = b.option([]const u8, "python-libdir", "Python library directory (for Windows linking)");
    const py_lib = b.option([]const u8, "python-lib", "Python import library name, e.g. python312 (Windows)");

    configurePythonLinkage(pyo3zig_lib, target, py_libdir, py_lib);

    const python_include: std.Build.LazyPath = if (py_include) |p|
        .{ .cwd_relative = p }
    else
        getPythonInclude(b);
    pyo3zig_lib.root_module.addIncludePath(python_include);
    // Under abi3, compile the C shim against the Limited API so the wheel is
    // forward-compatible. "3.12" -> -DPy_LIMITED_API=0x030c0000.
    const capi_flags: []const []const u8 = if (abi3.len > 0)
        &.{b.fmt("-DPy_LIMITED_API={s}", .{limitedApiHex(b, abi3)})}
    else
        &.{};
    pyo3zig_lib.root_module.addCSourceFile(.{ .file = b.path("pyo3zig_capi.c"), .flags = capi_flags });

    b.installArtifact(pyo3zig_lib);

    const test_step = b.step("test", "Run Python tests");
    const is_macos = target.result.os.tag == .macos;
    // Source artifact is .dylib on macOS, .so elsewhere; the import target is
    // always pyo3zig_demo.so (Python loads .so on macOS too).
    const src_ext: []const u8 = if (is_macos) "dylib" else "so";
    const copy_cmd = std.fmt.allocPrint(b.allocator, "cp zig-out/lib/libpyo3zig_demo.{s} pyo3zig_demo.so && python3 tests/test_pyo3zig.py && python3 tests/test_subinterp.py", .{src_ext}) catch "cp_failed";
    const run_tests = b.addSystemCommand(&.{ "sh", "-c", copy_cmd });
    run_tests.step.dependOn(b.getInstallStep());
    test_step.dependOn(&run_tests.step);
}

/// Python extension modules resolve CPython's symbols (PyExc_*, PyLong_*, ...)
/// against the interpreter at import time. The linker must therefore be told to
/// leave those symbols undefined:
///   - ELF (Linux): allowed by default, but make it explicit.
///   - Mach-O (macOS): requires `-undefined dynamic_lookup`.
///   - Windows: PE has no dynamic-lookup equivalent; a `pythonXY.lib` import
///     library must be linked. Cross-linking that is out of scope here, so we
///     surface a clear note instead of failing cryptically.
fn configurePythonLinkage(
    lib: *std.Build.Step.Compile,
    target: std.Build.ResolvedTarget,
    py_libdir: ?[]const u8,
    py_lib: ?[]const u8,
) void {
    lib.linker_allow_shlib_undefined = true;
    if (target.result.os.tag == .windows) {
        // PE cannot leave CPython symbols undefined; link the import library.
        if (py_libdir) |d| lib.root_module.addLibraryPath(.{ .cwd_relative = d });
        if (py_lib) |l| {
            lib.root_module.linkSystemLibrary(l, .{});
        } else {
            std.log.warn(
                "Windows target without -Dpython-lib; pass e.g. -Dpython-lib=python312 -Dpython-libdir=<libs>.",
                .{},
            );
        }
    }
}

/// "3.12" -> "0x030c0000" (PY_VERSION_HEX form for Py_LIMITED_API).
fn limitedApiHex(b: *std.Build, ver: []const u8) []const u8 {
    var it = std.mem.splitScalar(u8, ver, '.');
    const major = std.fmt.parseInt(u8, it.next() orelse "3", 10) catch 3;
    const minor = std.fmt.parseInt(u8, it.next() orelse "12", 10) catch 12;
    return b.fmt("0x{x:0>2}{x:0>2}0000", .{ major, minor });
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
