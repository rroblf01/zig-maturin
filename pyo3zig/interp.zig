const zm = @import("zig-maturin");

/// A tiny per-interpreter cache of a single process-lifetime PyObject (a type,
/// a class, etc.). Keyed by interpreter so an object created in one
/// (sub-)interpreter is never handed to another — which would be a hard error.
/// Access is serialized by the (shared) GIL; see the module's multi-phase slots.
pub fn Cache(comptime N: usize) type {
    return struct {
        const Entry = struct { interp: ?*anyopaque = null, obj: ?*zm.PyObject = null };
        entries: [N]Entry = .{Entry{}} ** N,

        pub fn get(self: *@This()) ?*zm.PyObject {
            const cur = zm.PyInterpreterState_Get();
            for (&self.entries) |*e| {
                if (e.interp == cur) return e.obj;
            }
            return null;
        }

        pub fn put(self: *@This(), o: ?*zm.PyObject) void {
            const cur = zm.PyInterpreterState_Get();
            for (&self.entries) |*e| {
                if (e.interp == null or e.interp == cur) {
                    e.* = .{ .interp = cur, .obj = o };
                    return;
                }
            }
            self.entries[0] = .{ .interp = cur, .obj = o };
        }
    };
}
