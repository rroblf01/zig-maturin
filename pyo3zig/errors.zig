const std = @import("std");
const zm = @import("zig-maturin");

pub fn zigErrorToPyException(err: anyerror) ?*zm.PyObject {
    switch (err) {
        error.OutOfMemory => return zm.PyExc_MemoryError(),
        error.Overflow => return zm.PyExc_OverflowError(),
        error.ZeroDivision => return zm.PyExc_ZeroDivisionError(),
        error.NotImplemented => return zm.PyExc_NotImplementedError(),
        error.InvalidParam,
        error.BadValue,
        error.InvalidCharacter,
        error.UnsupportedCType,
        error.InvalidUtf8,
        => return zm.PyExc_ValueError(),
        error.AccessDenied,
        error.FileNotFound,
        error.NameTooLong,
        error.PathAlreadyExists,
        error.SystemResources,
        error.ConnectionRefused,
        error.ConnectionResetByPeer,
        error.BrokenPipe,
        error.NotOpenForReading,
        error.NotOpenForWriting,
        error.FileSystem,
        error.Locked,
        error.ReadOnlyFile,
        error.UnexpectedEndOfFile,
        => return zm.PyExc_OSError(),
        else => return zm.PyExc_RuntimeError(),
    }
}

pub fn setPyException(err: anyerror) void {
    const exc_type = zigErrorToPyException(err);
    const name = @errorName(err);
    var buf: [256]u8 = undefined;
    const len = @min(name.len, buf.len - 1);
    @memcpy(buf[0..len], name[0..len]);
    buf[len] = 0;
    zm.PyErr_SetString(exc_type, @as([*:0]const u8, @ptrCast(&buf)));
}

/// Set a Python exception from a Zig error, but only if the caller hasn't
/// already set one. This lets user code raise a specific (or custom) exception
/// via `setError` / `PyErr_SetString` and then `return error.Whatever`, without
/// the generic error mapping clobbering it.
pub fn setPyExceptionIfNeeded(err: anyerror) void {
    if (zm.PyErr_Occurred() != null) return;
    setPyException(err);
}

/// Raise a Python exception with an explicit type and message. Pass a builtin
/// (e.g. `zm.PyExc_ValueError()`) or a custom type created with `newException`.
/// After calling this, return any Zig error and it will be preserved.
pub fn setError(exc_type: ?*zm.PyObject, msg: []const u8) void {
    var buf: [512]u8 = undefined;
    const len = @min(msg.len, buf.len - 1);
    @memcpy(buf[0..len], msg[0..len]);
    buf[len] = 0;
    zm.PyErr_SetString(exc_type, @as([*:0]const u8, @ptrCast(&buf)));
}

/// Create a new Python exception type, e.g. "my_module.MyError". Add it to the
/// module (PyModule_AddObject) so it's importable, and keep the pointer to
/// raise it later via `setError`.
pub fn newException(name: [*:0]const u8, base: ?*zm.PyObject) ?*zm.PyObject {
    return zm.PyErr_NewException(name, base, null);
}
