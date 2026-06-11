const std = @import("std");
const zm = @import("zig-maturin");
const refcount = @import("refcount.zig");
const pycell = @import("pycell.zig");

pub const ConversionError = error{
    PythonTypeError,
    PythonValueError,
    Overflow,
    MemoryError,
    NotImplemented,
};

/// Python type-hint spelling for a Zig type, used in error messages.
fn expectedName(comptime T: type) []const u8 {
    if (T == ?*zm.PyObject or T == *zm.PyObject) return "object";
    return switch (@typeInfo(T)) {
        .int => "int",
        .float => "float",
        .bool => "bool",
        .@"enum" => "int",
        .optional => |o| expectedName(o.child),
        .pointer => |p| if (p.size == .slice and p.child == u8) "str or bytes" else if (p.size == .slice) "list or tuple" else shortName(p.child),
        .array => "list or tuple",
        .@"struct" => |s| if (s.is_tuple) "tuple" else "dict",
        else => shortName(T),
    };
}

/// Short (unqualified) name of a type: "pkg.Vec2" -> "Vec2".
fn shortName(comptime T: type) []const u8 {
    const full = @typeName(T);
    const dot = std.mem.lastIndexOfScalar(u8, full, '.');
    return if (dot) |d| full[d + 1 ..] else full;
}

/// Optional argument label (e.g. "base") prepended to type-error messages. Set
/// by the keyword-argument binder around each conversion; the GIL serializes
/// access. Reset to null after use.
threadlocal var arg_context: ?[]const u8 = null;

pub fn setArgContext(name: ?[]const u8) void {
    arg_context = name;
}

/// Set a precise TypeError: "expected <wanted>, got <actual python type>",
/// prefixed with the argument name when one is in context.
fn raiseTypeError(comptime T: type, obj: ?*zm.PyObject) void {
    const actual = std.mem.span(zm.pz_type_name(obj));
    var buf: [224]u8 = undefined;
    const m = if (arg_context) |name|
        std.fmt.bufPrint(&buf, "argument '{s}': expected {s}, got {s}", .{ name, expectedName(T), actual })
    else
        std.fmt.bufPrint(&buf, "expected {s}, got {s}", .{ expectedName(T), actual });
    const msg = m catch {
        zm.PyErr_SetString(zm.PyExc_TypeError(), "type error");
        return;
    };
    buf[@min(msg.len, buf.len - 1)] = 0;
    zm.PyErr_SetString(zm.PyExc_TypeError(), @as([*:0]const u8, @ptrCast(&buf)));
}

/// Integers wider than 64 bits are round-tripped through their decimal string
/// (CPython's int is arbitrary-precision; there is no fixed-width C path).
fn bigIntToPy(comptime T: type, value: T) ConversionError!?*zm.PyObject {
    var buf: [48]u8 = undefined;
    const s = std.fmt.bufPrint(&buf, "{d}", .{value}) catch return error.Overflow;
    buf[s.len] = 0;
    return zm.PyLong_FromString(@as([*:0]const u8, @ptrCast(&buf)), null, 10);
}

fn bigIntFromPy(comptime T: type, obj: ?*zm.PyObject) ConversionError!T {
    if (zm.PyLong_Check(obj) == 0) {
        raiseTypeError(T, obj);
        return error.PythonTypeError;
    }
    const str_obj = zm.PyObject_Str(obj) orelse return error.PythonValueError;
    defer zm.Py_XDECREF(str_obj);
    const c = zm.PyUnicode_AsUTF8(str_obj) orelse return error.PythonValueError;
    return std.fmt.parseInt(T, std.mem.sliceTo(c, 0), 10) catch error.Overflow;
}

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
                return bigIntToPy(T, value);
            } else {
                if (info.bits <= 64) {
                    return zm.PyLong_FromUnsignedLongLong(value);
                }
                return bigIntToPy(T, value);
            }
        },
        .float => {
            return zm.PyFloat_FromDouble(value);
        },
        .bool => {
            return zm.PyBool_FromLong(if (value) 1 else 0);
        },
        .@"enum" => {
            // A Zig enum surfaces as its integer value.
            return toPyObject(@intFromEnum(value));
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
            // String literal: *const [N:0]u8 -> str.
            if (info.size == .one) {
                const child_info = @typeInfo(info.child);
                if (child_info == .array and child_info.array.child == u8) {
                    const s: []const u8 = value;
                    return zm.PyUnicode_FromStringAndSize(s.ptr, @as(isize, @intCast(s.len)));
                }
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

/// Length of a Python sequence (list or tuple), or null if it is neither.
fn seqLen(obj: ?*zm.PyObject) ?isize {
    if (zm.PyList_Check(obj) != 0) return zm.PyList_Size(obj);
    if (zm.PyTuple_Check(obj) != 0) return zm.PyTuple_Size(obj);
    return null;
}

/// Borrowed item from a Python list/tuple at index i.
fn seqItem(obj: ?*zm.PyObject, i: isize) ?*zm.PyObject {
    if (zm.PyList_Check(obj) != 0) return zm.PyList_GetItem(obj, i);
    return zm.PyTuple_GetItem(obj, i);
}

/// Convert a Python object to a Zig value. `allocator` backs container
/// conversions (list -> []T, dict -> struct); pass a per-call arena so the
/// result lives for the duration of the call and is freed afterwards. Scalar
/// and borrowed conversions ignore it.
pub fn fromPyObject(comptime T: type, obj: ?*zm.PyObject, allocator: std.mem.Allocator) ConversionError!T {
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
                        raiseTypeError(T, obj);
                        return error.PythonTypeError;
                    }
                    return @intCast(val);
                }
                if (info.bits <= 64) {
                    const val = zm.PyLong_AsLongLong(obj);
                    if (val == -1 and zm.PyErr_Occurred() != null) {
                        zm.PyErr_Clear();
                        raiseTypeError(T, obj);
                        return error.PythonTypeError;
                    }
                    return @intCast(val);
                }
                return bigIntFromPy(T, obj);
            } else {
                if (info.bits <= 64) {
                    const val = zm.PyLong_AsUnsignedLongLong(obj);
                    if (val == std.math.maxInt(u64) and zm.PyErr_Occurred() != null) {
                        zm.PyErr_Clear();
                        raiseTypeError(T, obj);
                        return error.PythonTypeError;
                    }
                    return @intCast(val);
                }
                return bigIntFromPy(T, obj);
            }
        },
        .float => {
            const val = zm.PyFloat_AsDouble(obj);
            if (val == -1.0 and zm.PyErr_Occurred() != null) {
                zm.PyErr_Clear();
                raiseTypeError(T, obj);
                return error.PythonTypeError;
            }
            return val;
        },
        .bool => {
            return zm.PyObject_IsTrue(obj) != 0;
        },
        .@"enum" => |info| {
            // Accept a Python int, validated against the enum's variants.
            const tag = try fromPyObject(info.tag_type, obj, allocator);
            inline for (info.fields) |f| {
                if (f.value == tag) return @enumFromInt(tag);
            }
            const msg = comptime std.fmt.comptimePrint("invalid value for {s}", .{shortName(T)});
            zm.PyErr_SetString(zm.PyExc_ValueError(), msg);
            return error.PythonValueError;
        },
        .optional => |info| {
            if (obj == zm.Py_None()) {
                return null;
            }
            return try fromPyObject(info.child, obj, allocator);
        },
        .pointer => |info| {
            if (info.size == .slice) {
                if (info.child == u8) {
                    // Borrow the underlying buffer — valid for the duration of
                    // the call (the argument keeps the object alive). No copy.
                    if (zm.PyUnicode_Check(obj) != 0) {
                        const c_str_opt = zm.PyUnicode_AsUTF8(obj);
                        if (c_str_opt) |c_str| return std.mem.sliceTo(c_str, 0);
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
                    // bytearray: borrow its mutable buffer (valid for the call).
                    if (zm.PyByteArray_Check(obj) != 0) {
                        const buf = zm.PyByteArray_AsString(obj) orelse return error.PythonValueError;
                        const size = zm.PyByteArray_Size(obj);
                        return buf[0..@as(usize, @intCast(size))];
                    }
                    raiseTypeError(T, obj);
                    return error.PythonTypeError;
                }
                // list/tuple -> []child (allocated in the per-call arena).
                const n = seqLen(obj) orelse {
                    raiseTypeError(T, obj);
                    return error.PythonTypeError;
                };
                const out = allocator.alloc(info.child, @as(usize, @intCast(n))) catch return error.MemoryError;
                var i: isize = 0;
                while (i < n) : (i += 1) {
                    const item = seqItem(obj, i) orelse return error.PythonValueError;
                    out[@as(usize, @intCast(i))] = try fromPyObject(info.child, item, allocator);
                }
                return out;
            }
            // *T (single pointer) where T is a class struct: borrow the Zig data
            // backing a live instance of that class. The instance keeps it alive
            // for the duration of the call.
            if (info.size == .one) {
                const ci = @typeInfo(info.child);
                if (ci == .@"struct" and !@hasDecl(info.child, "borrow")) {
                    const expected = comptime shortName(info.child);
                    const actual = std.mem.span(zm.pz_type_name(obj));
                    if (!std.mem.eql(u8, expected, actual)) {
                        raiseTypeError(T, obj);
                        return error.PythonTypeError;
                    }
                    return pycell.PyCell(info.child).ptrFromObj(obj);
                }
            }
            return error.NotImplemented;
        },
        .array => |info| {
            const n = seqLen(obj) orelse {
                raiseTypeError(T, obj);
                return error.PythonTypeError;
            };
            if (n != info.len) return error.PythonValueError;
            var out: T = undefined;
            inline for (0..info.len) |i| {
                const item = seqItem(obj, @as(isize, @intCast(i))) orelse return error.PythonValueError;
                out[i] = try fromPyObject(info.child, item, allocator);
            }
            return out;
        },
        .@"struct" => |info| {
            if (@hasDecl(T, "borrow")) return error.NotImplemented; // wrapper types not accepted as args
            if (info.is_tuple) {
                const n = seqLen(obj) orelse {
                    raiseTypeError(T, obj);
                    return error.PythonTypeError;
                };
                if (n != info.fields.len) return error.PythonValueError;
                var out: T = undefined;
                inline for (info.fields, 0..) |field, i| {
                    const item = seqItem(obj, @as(isize, @intCast(i))) orelse return error.PythonValueError;
                    @field(out, field.name) = try fromPyObject(field.type, item, allocator);
                }
                return out;
            }
            // dict -> struct keyed by field name; missing keys use struct defaults.
            if (zm.PyDict_Check(obj) == 0) {
                raiseTypeError(T, obj);
                return error.PythonTypeError;
            }
            var out: T = undefined;
            inline for (info.fields) |field| {
                const key = @as([*:0]const u8, @ptrCast(field.name.ptr));
                const item = zm.PyDict_GetItemString(obj, key);
                if (item) |it| {
                    @field(out, field.name) = try fromPyObject(field.type, it, allocator);
                } else if (field.default_value_ptr) |dv| {
                    @field(out, field.name) = @as(*const field.type, @ptrCast(@alignCast(dv))).*;
                } else {
                    return error.PythonValueError;
                }
            }
            return out;
        },
        else => {
            @compileError("Cannot convert Python object to " ++ @typeName(T));
        },
    }
}
