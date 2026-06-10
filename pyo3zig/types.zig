const std = @import("std");
const zm = @import("zig-maturin");
const refcount = @import("refcount.zig");

pub const PyObjectType = enum(c_int) {
    bool,
    int,
    float,
    str,
    list,
    dict,
    tuple,
    bytes,
    none,
    other,
};

pub fn typeOf(obj: ?*zm.PyObject) PyObjectType {
    if (obj == null) return .none;
    if (obj == zm.Py_None) return .none;
    if (zm.PyBool_Check(obj) != 0) return .bool;
    if (zm.PyLong_Check(obj) != 0) return .int;
    if (zm.PyFloat_Check(obj) != 0) return .float;
    if (zm.PyUnicode_Check(obj) != 0) return .str;
    if (zm.PyList_Check(obj) != 0) return .list;
    if (zm.PyDict_Check(obj) != 0) return .dict;
    if (zm.PyTuple_Check(obj) != 0) return .tuple;
    return .other;
}

pub const PyString = struct {
    inner: refcount.PyObjectRef,

    pub fn init(s: []const u8) !PyString {
        const ptr = zm.PyUnicode_FromStringAndSize(s.ptr, @as(isize, @intCast(s.len)));
        if (ptr == null) return error.PythonError;
        return .{ .inner = refcount.PyObjectRef.ref(ptr) };
    }

    pub fn asSlice(self: *const PyString) ![]const u8 {
        const ptr = zm.PyUnicode_AsUTF8(self.inner.borrowShared());
        if (ptr == null) return error.PythonValueError;
        return std.mem.sliceTo(ptr, 0);
    }

    pub fn borrow(self: *const PyString) ?*zm.PyObject {
        return self.inner.borrowShared();
    }

    pub fn deinit(self: *PyString) void {
        self.inner.deinit();
    }
};

pub const PyInt = struct {
    inner: refcount.PyObjectRef,

    pub fn fromLong(val: i64) !PyInt {
        const ptr = zm.PyLong_FromLongLong(val);
        if (ptr == null) return error.PythonError;
        return .{ .inner = refcount.PyObjectRef.ref(ptr) };
    }

    pub fn asSigned(self: *const PyInt) !i64 {
        return zm.PyLong_AsLongLong(self.inner.borrowShared());
    }

    pub fn borrow(self: *const PyInt) ?*zm.PyObject {
        return self.inner.borrowShared();
    }

    pub fn deinit(self: *PyInt) void {
        self.inner.deinit();
    }
};

pub const PyFloat = struct {
    inner: refcount.PyObjectRef,

    pub fn fromDouble(val: f64) !PyFloat {
        const ptr = zm.PyFloat_FromDouble(val);
        if (ptr == null) return error.PythonError;
        return .{ .inner = refcount.PyObjectRef.ref(ptr) };
    }

    pub fn asDouble(self: *const PyFloat) f64 {
        return zm.PyFloat_AsDouble(self.inner.borrowShared());
    }

    pub fn borrow(self: *const PyFloat) ?*zm.PyObject {
        return self.inner.borrowShared();
    }

    pub fn deinit(self: *PyFloat) void {
        self.inner.deinit();
    }
};

pub const PyBool = struct {
    inner: refcount.PyObjectRef,

    pub fn fromBool(val: bool) PyBool {
        const ptr = zm.PyBool_FromLong(if (val) 1 else 0);
        return .{ .inner = refcount.PyObjectRef.ref(ptr) };
    }

    pub fn asBool(self: *const PyBool) bool {
        return zm.PyObject_IsTrue(self.inner.borrowShared()) != 0;
    }

    pub fn borrow(self: *const PyBool) ?*zm.PyObject {
        return self.inner.borrowShared();
    }

    pub fn deinit(self: *PyBool) void {
        self.inner.deinit();
    }
};

pub const PyList = struct {
    inner: refcount.PyObjectRef,

    pub fn new() !PyList {
        const ptr = zm.PyList_New(0);
        if (ptr == null) return error.PythonError;
        return .{ .inner = refcount.PyObjectRef.ref(ptr) };
    }

    pub fn withSize(size: isize) !PyList {
        const ptr = zm.PyList_New(size);
        if (ptr == null) return error.PythonError;
        return .{ .inner = refcount.PyObjectRef.ref(ptr) };
    }

    pub fn len(self: *const PyList) isize {
        return zm.PyList_Size(self.inner.borrowShared());
    }

    pub fn get(self: *const PyList, index: isize) ?*zm.PyObject {
        return zm.PyList_GetItem(self.inner.borrowShared(), index);
    }

    pub fn append(self: *const PyList, item: ?*zm.PyObject) !void {
        if (zm.PyList_Append(self.inner.borrowShared(), item) != 0) {
            return error.PythonError;
        }
    }

    pub fn borrow(self: *const PyList) ?*zm.PyObject {
        return self.inner.borrowShared();
    }

    pub fn deinit(self: *PyList) void {
        self.inner.deinit();
    }
};

pub const PyDict = struct {
    inner: refcount.PyObjectRef,

    pub fn new() !PyDict {
        const ptr = zm.PyDict_New();
        if (ptr == null) return error.PythonError;
        return .{ .inner = refcount.PyObjectRef.ref(ptr) };
    }

    pub fn setString(self: *const PyDict, key: [*:0]const u8, value: ?*zm.PyObject) !void {
        if (zm.PyDict_SetItemString(self.inner.borrowShared(), key, value) != 0) {
            return error.PythonError;
        }
    }

    pub fn getString(self: *const PyDict, key: [*:0]const u8) ?*zm.PyObject {
        return zm.PyDict_GetItemString(self.inner.borrowShared(), key);
    }

    pub fn len(self: *const PyDict) isize {
        return zm.PyDict_Size(self.inner.borrowShared());
    }

    pub fn borrow(self: *const PyDict) ?*zm.PyObject {
        return self.inner.borrowShared();
    }

    pub fn deinit(self: *PyDict) void {
        self.inner.deinit();
    }
};

pub const PyTuple = struct {
    inner: refcount.PyObjectRef,

    pub fn new(size: isize) !PyTuple {
        const ptr = zm.PyTuple_New(size);
        if (ptr == null) return error.PythonError;
        return .{ .inner = refcount.PyObjectRef.ref(ptr) };
    }

    pub fn len(self: *const PyTuple) isize {
        return zm.PyTuple_Size(self.inner.borrowShared());
    }

    pub fn get(self: *const PyTuple, index: isize) ?*zm.PyObject {
        return zm.PyTuple_GetItem(self.inner.borrowShared(), index);
    }

    pub fn borrow(self: *const PyTuple) ?*zm.PyObject {
        return self.inner.borrowShared();
    }

    pub fn deinit(self: *PyTuple) void {
        self.inner.deinit();
    }
};
