const pytypes = @import("pytypes.zig");

pub const PyObject = pytypes.PyObject;
pub const PyModuleDef = pytypes.PyModuleDef;

// Module creation
pub extern fn PyModule_Create2(?*PyModuleDef, c_int) callconv(.c) ?*PyObject;
pub fn PyModule_Create(def: ?*PyModuleDef) ?*PyObject {
    return PyModule_Create2(def, 3);
}

pub extern fn PyModule_New([*:0]const u8) callconv(.c) ?*PyObject;
pub extern fn PyModule_AddObject(?*PyObject, [*:0]const u8, ?*PyObject) callconv(.c) c_int;
pub extern fn PyModule_AddIntConstant(?*PyObject, [*:0]const u8, c_long) callconv(.c) c_int;
pub extern fn PyModule_AddStringConstant(?*PyObject, [*:0]const u8, [*:0]const u8) callconv(.c) c_int;

// Reference counting
pub extern fn Py_INCREF(?*PyObject) callconv(.c) void;
pub extern fn Py_DECREF(?*PyObject) callconv(.c) void;
pub extern fn Py_XINCREF(?*PyObject) callconv(.c) void;
pub extern fn Py_XDECREF(?*PyObject) callconv(.c) void;
pub extern fn Py_NewRef(?*PyObject) callconv(.c) ?*PyObject;
pub extern fn Py_XNewRef(?*PyObject) callconv(.c) ?*PyObject;
pub extern fn Py_IncRef(?*PyObject) callconv(.c) void;
pub extern fn Py_DecRef(?*PyObject) callconv(.c) void;

// String functions
pub extern fn PyUnicode_FromString([*:0]const u8) callconv(.c) ?*PyObject;
pub extern fn PyUnicode_FromStringAndSize([*]const u8, isize) callconv(.c) ?*PyObject;
pub extern fn PyUnicode_AsUTF8(?*PyObject) callconv(.c) [*:0]const u8;
pub extern fn PyUnicode_Check(?*PyObject) callconv(.c) c_int;

// Integer functions
pub extern fn PyLong_FromLong(c_long) callconv(.c) ?*PyObject;
pub extern fn PyLong_FromLongLong(i64) callconv(.c) ?*PyObject;
pub extern fn PyLong_FromUnsignedLongLong(u64) callconv(.c) ?*PyObject;
pub extern fn PyLong_AsLong(?*PyObject) callconv(.c) c_long;
pub extern fn PyLong_AsLongLong(?*PyObject) callconv(.c) i64;
pub extern fn PyLong_Check(?*PyObject) callconv(.c) c_int;

// Float functions
pub extern fn PyFloat_FromDouble(f64) callconv(.c) ?*PyObject;
pub extern fn PyFloat_AsDouble(?*PyObject) callconv(.c) f64;
pub extern fn PyFloat_Check(?*PyObject) callconv(.c) c_int;

// Boolean functions
pub extern fn PyBool_FromLong(c_long) callconv(.c) ?*PyObject;
pub extern fn PyBool_Check(?*PyObject) callconv(.c) c_int;

// None singleton
pub fn Py_RETURN_NONE() callconv(.c) ?*PyObject {
    return Py_NewRef(Py_None);
}

// Exception handling
pub extern fn PyErr_SetString(?*PyObject, [*:0]const u8) callconv(.c) void;
pub extern fn PyErr_SetObject(?*PyObject, ?*PyObject) callconv(.c) void;
pub extern fn PyErr_Occurred() callconv(.c) ?*PyObject;
pub extern fn PyErr_Clear() callconv(.c) void;
pub extern fn PyErr_Format(?*PyObject, [*:0]const u8, ...) callconv(.c) ?*PyObject;

// Object utilities
pub extern fn PyObject_GetAttrString(?*PyObject, [*:0]const u8) callconv(.c) ?*PyObject;
pub extern fn PyObject_SetAttrString(?*PyObject, [*:0]const u8, ?*PyObject) callconv(.c) c_int;
pub extern fn PyObject_CallObject(?*PyObject, ?*PyObject) callconv(.c) ?*PyObject;
pub extern fn PyObject_CallFunction(?*PyObject, [*:0]const u8, ...) callconv(.c) ?*PyObject;
pub extern fn PyObject_Str(?*PyObject) callconv(.c) ?*PyObject;
pub extern fn PyObject_Repr(?*PyObject) callconv(.c) ?*PyObject;
pub extern fn PyObject_Type(?*PyObject) callconv(.c) ?*PyObject;
pub extern fn PyObject_IsInstance(?*PyObject, ?*PyObject) callconv(.c) c_int;
pub extern fn PyObject_IsTrue(?*PyObject) callconv(.c) c_int;

// Argument parsing
pub extern fn PyArg_ParseTuple(?*PyObject, [*:0]const u8, ...) callconv(.c) c_int;

// Build value
pub extern fn Py_BuildValue([*:0]const u8, ...) callconv(.c) ?*PyObject;

// List functions
pub extern fn PyList_New(isize) callconv(.c) ?*PyObject;
pub extern fn PyList_Size(?*PyObject) callconv(.c) isize;
pub extern fn PyList_GetItem(?*PyObject, isize) callconv(.c) ?*PyObject;
pub extern fn PyList_SetItem(?*PyObject, isize, ?*PyObject) callconv(.c) c_int;
pub extern fn PyList_Append(?*PyObject, ?*PyObject) callconv(.c) c_int;
pub extern fn PyList_Check(?*PyObject) callconv(.c) c_int;

// Dict functions
pub extern fn PyDict_New() callconv(.c) ?*PyObject;
pub extern fn PyDict_SetItemString(?*PyObject, [*:0]const u8, ?*PyObject) callconv(.c) c_int;
pub extern fn PyDict_GetItemString(?*PyObject, [*:0]const u8) callconv(.c) ?*PyObject;
pub extern fn PyDict_Size(?*PyObject) callconv(.c) isize;
pub extern fn PyDict_Check(?*PyObject) callconv(.c) c_int;

// Tuple functions
pub extern fn PyTuple_New(isize) callconv(.c) ?*PyObject;
pub extern fn PyTuple_Size(?*PyObject) callconv(.c) isize;
pub extern fn PyTuple_GetItem(?*PyObject, isize) callconv(.c) ?*PyObject;
pub extern fn PyTuple_SetItem(?*PyObject, isize, ?*PyObject) callconv(.c) c_int;

// Type utilities
pub extern fn PyType_Check(?*PyObject) callconv(.c) c_int;
pub extern fn PyType_IsSubtype(?*PyObject, ?*PyObject) callconv(.c) c_int;

// Exception types (singletons declared in Python C-API)
pub const PyExc_Exception = @extern(?*PyObject, .{ .name = "PyExc_Exception" });
pub const PyExc_ValueError = @extern(?*PyObject, .{ .name = "PyExc_ValueError" });
pub const PyExc_TypeError = @extern(?*PyObject, .{ .name = "PyExc_TypeError" });
pub const PyExc_RuntimeError = @extern(?*PyObject, .{ .name = "PyExc_RuntimeError" });
pub const PyExc_StopIteration = @extern(?*PyObject, .{ .name = "PyExc_StopIteration" });
pub const PyExc_ImportError = @extern(?*PyObject, .{ .name = "PyExc_ImportError" });
pub const PyExc_AttributeError = @extern(?*PyObject, .{ .name = "PyExc_AttributeError" });
pub const PyExc_KeyError = @extern(?*PyObject, .{ .name = "PyExc_KeyError" });
pub const PyExc_IndexError = @extern(?*PyObject, .{ .name = "PyExc_IndexError" });
pub const PyExc_OSError = @extern(?*PyObject, .{ .name = "PyExc_OSError" });

// Singletons
pub const Py_None = @extern(?*PyObject, .{ .name = "_Py_NoneStruct" });
pub const Py_True = @extern(?*PyObject, .{ .name = "_Py_TrueStruct" });
pub const Py_False = @extern(?*PyObject, .{ .name = "_Py_FalseStruct" });
