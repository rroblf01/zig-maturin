const std = @import("std");
const zm = @import("zig-maturin");

/// Panic handler that turns a Zig panic into a Python exception when invoked
/// inside an extension call (i.e. under a pz_guard frame), instead of aborting
/// the interpreter. Outside a guarded call it falls back to the default panic.
///
/// Opt in from your module's root source file:
///     pub const panic = @import("pyo3zig").panic;
///
/// Caveat: the jump skips `defer`/`errdefer` between the panic site and the
/// call boundary, so resources allocated in that window leak. Panics are
/// exceptional; this trades a leak for keeping the interpreter alive.
pub fn panicFn(msg: []const u8, first_trace_addr: ?usize) noreturn {
    if (zm.pz_guard_active() != 0) {
        var buf: [256]u8 = undefined;
        const n = @min(msg.len, buf.len - 1);
        @memcpy(buf[0..n], msg[0..n]);
        buf[n] = 0;
        zm.PyErr_SetString(zm.PyExc_RuntimeError(), @as([*:0]const u8, @ptrCast(&buf)));
        zm.pz_panic_longjmp();
    }
    std.debug.defaultPanic(msg, first_trace_addr);
}

pub const panic = std.debug.FullPanic(panicFn);
