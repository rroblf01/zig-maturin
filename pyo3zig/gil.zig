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
