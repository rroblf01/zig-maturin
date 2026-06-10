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
