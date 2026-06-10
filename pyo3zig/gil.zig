const zm = @import("zig-maturin");

pub const GILGuard = struct {
    state: c_int,

    pub fn ensure() GILGuard {
        return .{ .state = zm.PyGILState_Ensure() };
    }

    pub fn deinit(self: *GILGuard) void {
        zm.PyGILState_Release(self.state);
    }
};

/// Release the GIL while running a pure-Zig computation, then reacquire it.
/// The callback MUST NOT touch any Python C-API while the GIL is released.
///
///     fn heavy(n: i64) i64 { return pz.allowThreads(compute, .{n}); }
pub fn allowThreads(comptime func: anytype, args: anytype) @typeInfo(@TypeOf(func)).@"fn".return_type.? {
    const tstate = zm.PyEval_SaveThread();
    defer zm.PyEval_RestoreThread(tstate);
    return @call(.auto, func, args);
}
