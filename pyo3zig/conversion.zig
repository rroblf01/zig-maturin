const std = @import("std");
const zm = @import("zig-maturin");
const refcount = @import("refcount.zig");

pub const ConversionError = error{
    PythonTypeError,
    PythonValueError,
    Overflow,
    NotImplemented,
};

pub fn toPyObject(value: anytype) ConversionError!?*zm.PyObject {
    const T = @TypeOf(value);
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
            if (info.size == .slice and info.child == u8) {
                return zm.PyUnicode_FromStringAndSize(value.ptr, @as(isize, @intCast(value.len)));
            }
            return error.NotImplemented;
        },
        else => {
            if (@hasDecl(T, "borrow")) {
                return zm.Py_NewRef(value.borrow());
            }
            @compileError("Cannot convert " ++ @typeName(T) ++ " to Python object");
        },
    }
}

pub fn fromPyObject(comptime T: type, obj: ?*zm.PyObject) ConversionError!T {
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
                if (zm.PyUnicode_Check(obj) != 0) {
                    const c_str_opt = zm.PyUnicode_AsUTF8(obj);
                    if (c_str_opt) |c_str| {
                        const len = std.mem.len(c_str);
                        return c_str[0..len];
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
