const std = @import("std");
const zm = @import("zig-maturin");
const refcount = @import("refcount.zig");

pub const ConversionError = error{
    PythonTypeError,
    PythonValueError,
    Overflow,
    MemoryError,
    NotImplemented,
};

pub fn toPyObject(value: anytype) ConversionError!?*zm.PyObject {
    const T = @TypeOf(value);
    // Raw object passthrough: the returned reference is transferred to the
    // caller as-is (the producer is expected to hand over a new reference).
    if (T == ?*zm.PyObject or T == *zm.PyObject) {
        return value;
    }
    switch (@typeInfo(T)) {
        .int => {
            const info = @typeInfo(T).int;
            if (info.signedness == .signed) {
                if (info.bits <= 32) {
                    return zm.PyLong_FromLong(@intCast(value));
                }
                if (info.bits <= 64) {
                    return zm.PyLong_FromLongLong(value);
                }
                return error.Overflow;
            } else {
                if (info.bits <= 64) {
                    return zm.PyLong_FromUnsignedLongLong(value);
                }
                return error.Overflow;
            }
        },
        .float => {
            return zm.PyFloat_FromDouble(value);
        },
        .bool => {
            return zm.PyBool_FromLong(if (value) 1 else 0);
        },
        .null => {
            return zm.Py_NewRef(zm.Py_None());
        },
        .optional => {
            if (value) |v| {
                return try toPyObject(v);
            }
            return zm.Py_NewRef(zm.Py_None());
        },
        .pointer => |info| {
            if (info.size == .slice) {
                if (info.child == u8) {
                    return zm.PyUnicode_FromStringAndSize(value.ptr, @as(isize, @intCast(value.len)));
                }
                // []T (T != u8) -> Python list.
                return sliceToList(value);
            }
            return error.NotImplemented;
        },
        .array => {
            // [N]T -> Python list (a string array [N]u8 is treated as a list of
            // ints; use a slice for text).
            return sliceToList(value[0..]);
        },
        .@"struct" => |info| {
            // Wrapper types (PyString, PyList, ...) own a reference and expose
            // `borrow`; they must transfer it, not be serialized field-by-field.
            if (@hasDecl(T, "borrow")) return value.borrow();
            if (info.is_tuple) return tupleToPyTuple(value);
            return structToDict(value);
        },
        else => {
            if (@hasDecl(T, "borrow")) {
                // Wrapper types own exactly one reference (created via noRef).
                // Returning transfers that ownership to the caller — no extra
                // incref, and the temporary is not deinit'd.
                return value.borrow();
            }
            @compileError("Cannot convert " ++ @typeName(T) ++ " to Python object");
        },
    }
}

fn sliceToList(value: anytype) ConversionError!?*zm.PyObject {
    const list = zm.PyList_New(@as(isize, @intCast(value.len))) orelse return error.MemoryError;
    errdefer zm.Py_XDECREF(list);
    for (value, 0..) |elem, i| {
        const py_elem = try toPyObject(elem);
        // PyList_SetItem steals the reference to py_elem.
        _ = zm.PyList_SetItem(list, @as(isize, @intCast(i)), py_elem);
    }
    return list;
}

fn tupleToPyTuple(value: anytype) ConversionError!?*zm.PyObject {
    const fields = std.meta.fields(@TypeOf(value));
    const tup = zm.PyTuple_New(@as(isize, @intCast(fields.len))) orelse return error.MemoryError;
    errdefer zm.Py_XDECREF(tup);
    inline for (fields, 0..) |field, i| {
        const py_elem = try toPyObject(@field(value, field.name));
        // PyTuple_SetItem steals the reference.
        _ = zm.PyTuple_SetItem(tup, @as(isize, @intCast(i)), py_elem);
    }
    return tup;
}

fn structToDict(value: anytype) ConversionError!?*zm.PyObject {
    const dict = zm.PyDict_New() orelse return error.MemoryError;
    errdefer zm.Py_XDECREF(dict);
    inline for (std.meta.fields(@TypeOf(value))) |field| {
        const py_val = try toPyObject(@field(value, field.name));
        // PyDict_SetItemString does NOT steal; it keeps its own reference.
        defer zm.Py_XDECREF(py_val);
        const key = @as([*:0]const u8, @ptrCast(field.name.ptr));
        if (zm.PyDict_SetItemString(dict, key, py_val) != 0) return error.PythonValueError;
    }
    return dict;
}

pub fn fromPyObject(comptime T: type, obj: ?*zm.PyObject) ConversionError!T {
    // Raw object passthrough: borrow the argument as-is (valid for the call).
    if (T == ?*zm.PyObject) return obj;
    if (T == *zm.PyObject) {
        if (obj) |o| return o;
        return error.PythonValueError;
    }

    if (obj == null) return error.PythonValueError;

    switch (@typeInfo(T)) {
        .int => |info| {
            if (info.signedness == .signed) {
                if (info.bits <= 32) {
                    const val = zm.PyLong_AsLong(obj);
                    if (val == -1 and zm.PyErr_Occurred() != null) {
                        zm.PyErr_Clear();
                        return error.PythonTypeError;
                    }
                    return @intCast(val);
                }
                if (info.bits <= 64) {
                    const val = zm.PyLong_AsLongLong(obj);
                    if (val == -1 and zm.PyErr_Occurred() != null) {
                        zm.PyErr_Clear();
                        return error.PythonTypeError;
                    }
                    return @intCast(val);
                }
                return error.Overflow;
            } else {
                if (info.bits <= 64) {
                    const val = zm.PyLong_AsUnsignedLongLong(obj);
                    if (val == std.math.maxInt(u64) and zm.PyErr_Occurred() != null) {
                        zm.PyErr_Clear();
                        return error.PythonTypeError;
                    }
                    return @intCast(val);
                }
                return error.Overflow;
            }
        },
        .float => {
            const val = zm.PyFloat_AsDouble(obj);
            if (val == -1.0 and zm.PyErr_Occurred() != null) {
                zm.PyErr_Clear();
                return error.PythonTypeError;
            }
            return val;
        },
        .bool => {
            return zm.PyObject_IsTrue(obj) != 0;
        },
        .optional => |info| {
            if (obj == zm.Py_None()) {
                return null;
            }
            return try fromPyObject(info.child, obj);
        },
        .pointer => |info| {
            if (info.size == .slice and info.child == u8) {
                // Borrow the underlying buffer — valid for the duration of the
                // call (the argument tuple keeps the object alive). No copy, no
                // free. Do NOT retain the slice past the call.
                if (zm.PyUnicode_Check(obj) != 0) {
                    const c_str_opt = zm.PyUnicode_AsUTF8(obj);
                    if (c_str_opt) |c_str| {
                        return std.mem.sliceTo(c_str, 0);
                    }
                    return error.PythonValueError;
                }
                if (zm.PyBytes_Check(obj) != 0) {
                    var buf: [*]u8 = undefined;
                    var size: isize = undefined;
                    if (zm.PyBytes_AsStringAndSize(obj, &buf, &size) != 0) {
                        return error.PythonValueError;
                    }
                    return buf[0..@as(usize, @intCast(size))];
                }
                return error.PythonTypeError;
            }
            return error.NotImplemented;
        },
        else => {
            @compileError("Cannot convert Python object to " ++ @typeName(T));
        },
    }
}
