const std = @import("std");
const zm = @import("zig-maturin");

pub fn zigErrorToPyException(err: anyerror) ?*zm.PyObject {
    switch (err) {
        error.OutOfMemory => return zm.PyExc_MemoryError,
        error.Overflow => return zm.PyExc_OverflowError,
        error.AccessDenied,
        error.ReadOnlyFile,
        error.Locked,
        error.FileSystem,
        error.FileNotFound,
        error.NameTooLong,
        error.PathAlreadyExists,
        error.SystemResources,
        error.ConnectionRefused,
        error.ConnectionResetByPeer,
        error.BrokenPipe,
        error.UnexpectedEndOfFile,
        error.NotOpenForReading,
        error.NotOpenForWriting,
        => return zm.PyExc_OSError,
        error.InvalidParam,
        error.BadValue,
        error.InvalidCharacter,
        error.UnsupportedCType,
        error.InvalidUtf8,
        => return zm.PyExc_ValueError,
        error.ZeroDivision => return zm.PyExc_ZeroDivisionError,
        error.NotImplemented => return zm.PyExc_NotImplementedError,
        error.NoSpaceLeft => return zm.PyExc_MemoryError,
        error.Unexpected,
        else => return zm.PyExc_RuntimeError,
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
