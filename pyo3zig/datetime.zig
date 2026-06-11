const std = @import("std");
const zm = @import("zig-maturin");
const interp = @import("interp.zig");

/// A naive calendar date-time, converted to/from Python's `datetime.datetime`.
/// Use it as a function argument or return type. Conversion goes through the
/// `datetime` module's public Python API (not the C-API capsule), so it works
/// under the Limited API / abi3 as well as the full API.
pub const DateTime = struct {
    year: i32,
    month: u8,
    day: u8,
    hour: u8 = 0,
    minute: u8 = 0,
    second: u8 = 0,
    microsecond: u32 = 0,
};

// Cached `datetime.datetime` class, per interpreter (an object belongs to the
// interpreter that imported `datetime`, so it can't be shared across
// sub-interpreters). The GIL serializes the lazy init.
var dt_cache: interp.Cache(16) = .{};

fn datetimeClass() ?*zm.PyObject {
    if (dt_cache.get()) |c| return c;
    const mod = zm.PyImport_ImportModule("datetime") orelse return null;
    defer zm.Py_XDECREF(mod);
    const cls = zm.PyObject_GetAttrString(mod, "datetime") orelse return null;
    dt_cache.put(cls); // permanent (process-lifetime) reference for this interpreter
    return cls;
}

/// Drop the current interpreter's cached datetime class (module teardown). We
/// own this reference (from PyObject_GetAttrString), so release it before
/// clearing — otherwise each torn-down interpreter leaks one class reference.
pub fn clearCache() void {
    if (dt_cache.get()) |c| zm.Py_XDECREF(c);
    dt_cache.clear();
}

fn intAttr(obj: ?*zm.PyObject, name: [*:0]const u8) ?i64 {
    const a = zm.PyObject_GetAttrString(obj, name) orelse return null;
    defer zm.Py_XDECREF(a);
    return zm.PyLong_AsLongLong(a);
}

/// Build a Python `datetime.datetime` from a `DateTime` (null on error, with a
/// Python exception set).
pub fn toPy(dt: DateTime) ?*zm.PyObject {
    const cls = datetimeClass() orelse return null;
    const args = zm.PyTuple_New(7) orelse return null;
    defer zm.Py_XDECREF(args);
    // PyTuple_SetItem steals each reference.
    _ = zm.PyTuple_SetItem(args, 0, zm.PyLong_FromLongLong(@intCast(dt.year)));
    _ = zm.PyTuple_SetItem(args, 1, zm.PyLong_FromLongLong(@intCast(dt.month)));
    _ = zm.PyTuple_SetItem(args, 2, zm.PyLong_FromLongLong(@intCast(dt.day)));
    _ = zm.PyTuple_SetItem(args, 3, zm.PyLong_FromLongLong(@intCast(dt.hour)));
    _ = zm.PyTuple_SetItem(args, 4, zm.PyLong_FromLongLong(@intCast(dt.minute)));
    _ = zm.PyTuple_SetItem(args, 5, zm.PyLong_FromLongLong(@intCast(dt.second)));
    _ = zm.PyTuple_SetItem(args, 6, zm.PyLong_FromLongLong(@intCast(dt.microsecond)));
    return zm.PyObject_CallObject(cls, args);
}

/// Read a `DateTime` from a Python `datetime.datetime`. Returns null (with a
/// Python TypeError set) if the object isn't a datetime.
pub fn fromPy(obj: ?*zm.PyObject) ?DateTime {
    const cls = datetimeClass() orelse return null;
    if (zm.PyObject_IsInstance(obj, cls) != 1) {
        zm.PyErr_SetString(zm.PyExc_TypeError(), "expected datetime.datetime");
        return null;
    }
    return .{
        .year = @intCast(intAttr(obj, "year") orelse return null),
        .month = @intCast(intAttr(obj, "month") orelse return null),
        .day = @intCast(intAttr(obj, "day") orelse return null),
        .hour = @intCast(intAttr(obj, "hour") orelse return null),
        .minute = @intCast(intAttr(obj, "minute") orelse return null),
        .second = @intCast(intAttr(obj, "second") orelse return null),
        .microsecond = @intCast(intAttr(obj, "microsecond") orelse return null),
    };
}
