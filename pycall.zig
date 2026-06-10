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
pub extern fn PyModule_AddFunctions(?*PyObject, ?[*]pytypes.PyMethodDef) callconv(.c) c_int;
pub extern fn PyModuleDef_Init(?*PyModuleDef) callconv(.c) ?*PyObject;

// Reference counting
pub extern fn Py_IncRef(?*PyObject) callconv(.c) void;
pub extern fn Py_DecRef(?*PyObject) callconv(.c) void;

// Python C-API macros implemented as Zig functions (no actual extern symbols)
pub fn Py_INCREF(op: ?*PyObject) callconv(.c) void {
    Py_IncRef(op);
}
pub fn Py_DECREF(op: ?*PyObject) callconv(.c) void {
    Py_DecRef(op);
}
pub fn Py_XINCREF(op: ?*PyObject) callconv(.c) void {
    if (op != null) Py_IncRef(op);
}
pub fn Py_XDECREF(op: ?*PyObject) callconv(.c) void {
    if (op != null) Py_DecRef(op);
}
pub fn Py_NewRef(op: ?*PyObject) callconv(.c) ?*PyObject {
    Py_IncRef(op);
    return op;
}
pub fn Py_XNewRef(op: ?*PyObject) callconv(.c) ?*PyObject {
    if (op != null) return Py_NewRef(op);
    return null;
}

// String functions
pub extern fn PyUnicode_FromString([*:0]const u8) callconv(.c) ?*PyObject;
pub extern fn PyUnicode_FromStringAndSize([*]const u8, isize) callconv(.c) ?*PyObject;
pub extern fn PyUnicode_AsUTF8(?*PyObject) callconv(.c) ?[*:0]const u8;
pub extern fn PyUnicode_DecodeUTF8([*]const u8, isize, ?[*:0]const u8) callconv(.c) ?*PyObject;

// Bytes functions
pub extern fn PyBytes_FromString([*:0]const u8) callconv(.c) ?*PyObject;
pub extern fn PyBytes_FromStringAndSize([*]const u8, isize) callconv(.c) ?*PyObject;
pub extern fn PyBytes_AsString(?*PyObject) callconv(.c) [*]u8;
pub extern fn PyBytes_Size(?*PyObject) callconv(.c) isize;
pub extern fn PyBytes_AsStringAndSize(?*PyObject, *[*]u8, *isize) callconv(.c) c_int;

// Integer functions
pub extern fn PyLong_FromLong(c_long) callconv(.c) ?*PyObject;
pub extern fn PyLong_FromLongLong(i64) callconv(.c) ?*PyObject;
pub extern fn PyLong_FromUnsignedLongLong(u64) callconv(.c) ?*PyObject;
pub extern fn PyLong_AsLong(?*PyObject) callconv(.c) c_long;
pub extern fn PyLong_AsLongLong(?*PyObject) callconv(.c) i64;
pub extern fn PyLong_AsUnsignedLongLong(?*PyObject) callconv(.c) u64;

// Float functions
pub extern fn PyFloat_FromDouble(f64) callconv(.c) ?*PyObject;
pub extern fn PyFloat_AsDouble(?*PyObject) callconv(.c) f64;

// Boolean functions
pub extern fn PyBool_FromLong(c_long) callconv(.c) ?*PyObject;

// None singleton
pub fn Py_RETURN_NONE() callconv(.c) ?*PyObject {
    return Py_NewRef(Py_None);
}

// GIL management
pub extern fn PyGILState_Ensure() callconv(.c) c_int;
pub extern fn PyGILState_Release(c_int) callconv(.c) void;

// Type creation
pub extern fn PyType_FromSpec(?*pytypes.PyType_Spec) callconv(.c) ?*PyObject;
pub extern fn PyType_FromSpecWithBases(?*pytypes.PyType_Spec, ?*PyObject) callconv(.c) ?*PyObject;
pub extern fn PyType_Ready(?*PyObject) callconv(.c) c_int;

// Memory allocation
pub extern fn PyMem_RawMalloc(usize) callconv(.c) ?*anyopaque;
pub extern fn PyMem_RawFree(?*anyopaque) callconv(.c) void;

// Exception handling
pub extern fn PyErr_SetString(?*PyObject, [*:0]const u8) callconv(.c) void;
pub extern fn PyErr_SetObject(?*PyObject, ?*PyObject) callconv(.c) void;
pub extern fn PyErr_Occurred() callconv(.c) ?*PyObject;
pub extern fn PyErr_Clear() callconv(.c) void;
pub extern fn PyErr_Format(?*PyObject, [*:0]const u8, ...) callconv(.c) ?*PyObject;
pub extern fn PyErr_NewException([*:0]const u8, ?*PyObject, ?*PyObject) callconv(.c) ?*PyObject;

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

// Dict functions
pub extern fn PyDict_New() callconv(.c) ?*PyObject;
pub extern fn PyDict_SetItemString(?*PyObject, [*:0]const u8, ?*PyObject) callconv(.c) c_int;
pub extern fn PyDict_GetItemString(?*PyObject, [*:0]const u8) callconv(.c) ?*PyObject;
pub extern fn PyDict_Size(?*PyObject) callconv(.c) isize;

// Tuple functions
pub extern fn PyTuple_New(isize) callconv(.c) ?*PyObject;
pub extern fn PyTuple_Size(?*PyObject) callconv(.c) isize;
pub extern fn PyTuple_GetItem(?*PyObject, isize) callconv(.c) ?*PyObject;
pub extern fn PyTuple_SetItem(?*PyObject, isize, ?*PyObject) callconv(.c) c_int;

// Type utilities
pub extern fn PyType_IsSubtype(?*PyObject, ?*PyObject) callconv(.c) c_int;

// Type object singletons (via C wrappers for correct pointer resolution)
pub extern fn pyo3zig_PyUnicode_Type() callconv(.c) ?*PyObject;
pub extern fn pyo3zig_PyLong_Type() callconv(.c) ?*PyObject;
pub extern fn pyo3zig_PyFloat_Type() callconv(.c) ?*PyObject;
pub extern fn pyo3zig_PyBool_Type() callconv(.c) ?*PyObject;
pub extern fn pyo3zig_PyList_Type() callconv(.c) ?*PyObject;
pub extern fn pyo3zig_PyDict_Type() callconv(.c) ?*PyObject;
pub extern fn pyo3zig_PyTuple_Type() callconv(.c) ?*PyObject;
pub extern fn pyo3zig_PyType_Type() callconv(.c) ?*PyObject;

pub fn PyUnicode_Type() callconv(.c) ?*PyObject { return pyo3zig_PyUnicode_Type(); }
pub fn PyLong_Type() callconv(.c) ?*PyObject { return pyo3zig_PyLong_Type(); }
pub fn PyFloat_Type() callconv(.c) ?*PyObject { return pyo3zig_PyFloat_Type(); }
pub fn PyBool_Type() callconv(.c) ?*PyObject { return pyo3zig_PyBool_Type(); }
pub fn PyList_Type() callconv(.c) ?*PyObject { return pyo3zig_PyList_Type(); }
pub fn PyDict_Type() callconv(.c) ?*PyObject { return pyo3zig_PyDict_Type(); }
pub fn PyTuple_Type() callconv(.c) ?*PyObject { return pyo3zig_PyTuple_Type(); }
pub fn PyType_Type() callconv(.c) ?*PyObject { return pyo3zig_PyType_Type(); }

// Xxx_Check functions (macros in C, implemented as Zig functions via PyObject_IsInstance)
pub fn PyUnicode_Check(op: ?*PyObject) callconv(.c) c_int {
    return PyObject_IsInstance(op, PyUnicode_Type());
}
pub fn PyLong_Check(op: ?*PyObject) callconv(.c) c_int {
    return PyObject_IsInstance(op, PyLong_Type());
}
pub fn PyFloat_Check(op: ?*PyObject) callconv(.c) c_int {
    return PyObject_IsInstance(op, PyFloat_Type());
}
pub fn PyBool_Check(op: ?*PyObject) callconv(.c) c_int {
    return PyObject_IsInstance(op, PyBool_Type());
}
pub fn PyList_Check(op: ?*PyObject) callconv(.c) c_int {
    return PyObject_IsInstance(op, PyList_Type());
}
pub fn PyDict_Check(op: ?*PyObject) callconv(.c) c_int {
    return PyObject_IsInstance(op, PyDict_Type());
}
pub fn PyTuple_Check(op: ?*PyObject) callconv(.c) c_int {
    return PyObject_IsInstance(op, PyTuple_Type());
}
pub fn PyType_Check(op: ?*PyObject) callconv(.c) c_int {
    return PyObject_IsInstance(op, PyType_Type());
}
pub extern fn pyo3zig_PyBytes_Type() callconv(.c) ?*PyObject;
pub fn PyBytes_Type() callconv(.c) ?*PyObject { return pyo3zig_PyBytes_Type(); }
pub fn PyBytes_Check(op: ?*PyObject) callconv(.c) c_int {
    return PyObject_IsInstance(op, PyBytes_Type());
}

// Exception types (via C wrappers for correct pointer resolution)
pub extern fn pyo3zig_PyExc_Exception() callconv(.c) ?*PyObject;
pub extern fn pyo3zig_PyExc_ValueError() callconv(.c) ?*PyObject;
pub extern fn pyo3zig_PyExc_TypeError() callconv(.c) ?*PyObject;
pub extern fn pyo3zig_PyExc_RuntimeError() callconv(.c) ?*PyObject;
pub extern fn pyo3zig_PyExc_StopIteration() callconv(.c) ?*PyObject;
pub extern fn pyo3zig_PyExc_ImportError() callconv(.c) ?*PyObject;
pub extern fn pyo3zig_PyExc_AttributeError() callconv(.c) ?*PyObject;
pub extern fn pyo3zig_PyExc_KeyError() callconv(.c) ?*PyObject;
pub extern fn pyo3zig_PyExc_IndexError() callconv(.c) ?*PyObject;
pub extern fn pyo3zig_PyExc_OSError() callconv(.c) ?*PyObject;
pub extern fn pyo3zig_PyExc_MemoryError() callconv(.c) ?*PyObject;
pub extern fn pyo3zig_PyExc_OverflowError() callconv(.c) ?*PyObject;
pub extern fn pyo3zig_PyExc_NotImplementedError() callconv(.c) ?*PyObject;
pub extern fn pyo3zig_PyExc_SystemError() callconv(.c) ?*PyObject;
pub extern fn pyo3zig_PyExc_ZeroDivisionError() callconv(.c) ?*PyObject;
pub extern fn pyo3zig_Py_None() callconv(.c) ?*PyObject;
pub extern fn pyo3zig_Py_True() callconv(.c) ?*PyObject;
pub extern fn pyo3zig_Py_False() callconv(.c) ?*PyObject;

pub fn PyExc_Exception() callconv(.c) ?*PyObject { return pyo3zig_PyExc_Exception(); }
pub fn PyExc_ValueError() callconv(.c) ?*PyObject { return pyo3zig_PyExc_ValueError(); }
pub fn PyExc_TypeError() callconv(.c) ?*PyObject { return pyo3zig_PyExc_TypeError(); }
pub fn PyExc_RuntimeError() callconv(.c) ?*PyObject { return pyo3zig_PyExc_RuntimeError(); }
pub fn PyExc_StopIteration() callconv(.c) ?*PyObject { return pyo3zig_PyExc_StopIteration(); }
pub fn PyExc_ImportError() callconv(.c) ?*PyObject { return pyo3zig_PyExc_ImportError(); }
pub fn PyExc_AttributeError() callconv(.c) ?*PyObject { return pyo3zig_PyExc_AttributeError(); }
pub fn PyExc_KeyError() callconv(.c) ?*PyObject { return pyo3zig_PyExc_KeyError(); }
pub fn PyExc_IndexError() callconv(.c) ?*PyObject { return pyo3zig_PyExc_IndexError(); }
pub fn PyExc_OSError() callconv(.c) ?*PyObject { return pyo3zig_PyExc_OSError(); }
pub fn PyExc_MemoryError() callconv(.c) ?*PyObject { return pyo3zig_PyExc_MemoryError(); }
pub fn PyExc_OverflowError() callconv(.c) ?*PyObject { return pyo3zig_PyExc_OverflowError(); }
pub fn PyExc_NotImplementedError() callconv(.c) ?*PyObject { return pyo3zig_PyExc_NotImplementedError(); }
pub fn PyExc_SystemError() callconv(.c) ?*PyObject { return pyo3zig_PyExc_SystemError(); }
pub fn PyExc_ZeroDivisionError() callconv(.c) ?*PyObject { return pyo3zig_PyExc_ZeroDivisionError(); }
pub fn Py_None() callconv(.c) ?*PyObject { return pyo3zig_Py_None(); }
pub fn Py_True() callconv(.c) ?*PyObject { return pyo3zig_Py_True(); }
pub fn Py_False() callconv(.c) ?*PyObject { return pyo3zig_Py_False(); }
