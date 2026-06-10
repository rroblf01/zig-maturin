const zm = @import("zig-maturin");

pub const PyObjectRef = struct {
    ptr: ?*zm.PyObject,

    pub fn ref(obj: ?*zm.PyObject) PyObjectRef {
        return .{ .ptr = zm.Py_NewRef(obj) };
    }

    pub fn noRef(obj: ?*zm.PyObject) PyObjectRef {
        return .{ .ptr = obj };
    }

    pub fn clone(self: PyObjectRef) PyObjectRef {
        return .{ .ptr = zm.Py_NewRef(self.ptr) };
    }

    pub fn deinit(self: *PyObjectRef) void {
        zm.Py_XDECREF(self.ptr);
        self.ptr = null;
    }

    pub fn borrow(self: PyObjectRef) ?*zm.PyObject {
        return self.ptr;
    }

    pub fn borrowShared(self: *const PyObjectRef) ?*zm.PyObject {
        return self.ptr;
    }
};
