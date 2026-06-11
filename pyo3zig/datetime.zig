const std = @import("std");
const zm = @import("zig-maturin");

/// A naive calendar date-time, converted to/from Python's `datetime.datetime`.
/// Use it as a function argument or return type; the framework calls
/// `PyDateTime_IMPORT` once at module init so the C-API capsule is ready.
pub const DateTime = struct {
    year: i32,
    month: u8,
    day: u8,
    hour: u8 = 0,
    minute: u8 = 0,
    second: u8 = 0,
    microsecond: u32 = 0,
};

/// Build a Python `datetime.datetime` from a `DateTime` (null on error, with a
/// Python exception set).
pub fn toPy(dt: DateTime) ?*zm.PyObject {
    return zm.pyo3zig_DateTime_New(
        @as(c_int, @intCast(dt.year)),
        @as(c_int, @intCast(dt.month)),
        @as(c_int, @intCast(dt.day)),
        @as(c_int, @intCast(dt.hour)),
        @as(c_int, @intCast(dt.minute)),
        @as(c_int, @intCast(dt.second)),
        @as(c_int, @intCast(dt.microsecond)),
    );
}

/// Read a `DateTime` from a Python `datetime.datetime`. Returns null (with a
/// Python TypeError set) if the object isn't a datetime.
pub fn fromPy(obj: ?*zm.PyObject) ?DateTime {
    if (zm.pyo3zig_PyDateTime_Check(obj) == 0) {
        zm.PyErr_SetString(zm.PyExc_TypeError(), "expected datetime.datetime");
        return null;
    }
    return .{
        .year = @intCast(zm.pyo3zig_DateTime_year(obj)),
        .month = @intCast(zm.pyo3zig_DateTime_month(obj)),
        .day = @intCast(zm.pyo3zig_DateTime_day(obj)),
        .hour = @intCast(zm.pyo3zig_DateTime_hour(obj)),
        .minute = @intCast(zm.pyo3zig_DateTime_minute(obj)),
        .second = @intCast(zm.pyo3zig_DateTime_second(obj)),
        .microsecond = @intCast(zm.pyo3zig_DateTime_microsecond(obj)),
    };
}
