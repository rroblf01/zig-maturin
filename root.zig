const std = @import("std");
const pytypes = @import("pytypes.zig");
const pycall = @import("pycall.zig");

pub const PyObject = pytypes.PyObject;
pub const PyMethodDef = pytypes.PyMethodDef;
pub const PyModuleDef = pytypes.PyModuleDef;
pub const PyModuleDef_HEAD_INIT = pytypes.PyModuleDef_HEAD_INIT;
pub const PyObjectHeader = pytypes.PyObjectHeader;
pub const PyGetSetDef = pytypes.PyGetSetDef;
pub const PyType_Slot = pytypes.PyType_Slot;
pub const PyType_Spec = pytypes.PyType_Spec;
pub const METH_NOARGS = pytypes.METH_NOARGS;
pub const METH_VARARGS = pytypes.METH_VARARGS;
pub const METH_KEYWORDS = pytypes.METH_KEYWORDS;
pub const METH_O = pytypes.METH_O;

pub const PyModule_Create = pycall.PyModule_Create;
pub const PyModule_New = pycall.PyModule_New;
pub const PyModule_AddObject = pycall.PyModule_AddObject;
pub const PyModule_AddIntConstant = pycall.PyModule_AddIntConstant;
pub const PyModule_AddStringConstant = pycall.PyModule_AddStringConstant;

pub const Py_INCREF = pycall.Py_INCREF;
pub const Py_DECREF = pycall.Py_DECREF;
pub const Py_XINCREF = pycall.Py_XINCREF;
pub const Py_XDECREF = pycall.Py_XDECREF;
pub const Py_NewRef = pycall.Py_NewRef;
pub const Py_IncRef = pycall.Py_IncRef;
pub const Py_DecRef = pycall.Py_DecRef;

pub const PyUnicode_FromString = pycall.PyUnicode_FromString;
pub const PyUnicode_FromStringAndSize = pycall.PyUnicode_FromStringAndSize;
pub const PyUnicode_AsUTF8 = pycall.PyUnicode_AsUTF8;
pub const PyUnicode_Check = pycall.PyUnicode_Check;

pub const PyBytes_FromStringAndSize = pycall.PyBytes_FromStringAndSize;
pub const PyBytes_AsStringAndSize = pycall.PyBytes_AsStringAndSize;
pub const PyBytes_Size = pycall.PyBytes_Size;
pub const PyBytes_Check = pycall.PyBytes_Check;

pub const PyLong_FromLong = pycall.PyLong_FromLong;
pub const PyLong_FromLongLong = pycall.PyLong_FromLongLong;
pub const PyLong_FromUnsignedLongLong = pycall.PyLong_FromUnsignedLongLong;
pub const PyLong_AsLong = pycall.PyLong_AsLong;
pub const PyLong_AsLongLong = pycall.PyLong_AsLongLong;
pub const PyLong_AsUnsignedLongLong = pycall.PyLong_AsUnsignedLongLong;
pub const PyLong_Check = pycall.PyLong_Check;

pub const PyFloat_FromDouble = pycall.PyFloat_FromDouble;
pub const PyFloat_AsDouble = pycall.PyFloat_AsDouble;
pub const PyFloat_Check = pycall.PyFloat_Check;

pub const PyBool_FromLong = pycall.PyBool_FromLong;
pub const PyBool_Check = pycall.PyBool_Check;

pub const Py_RETURN_NONE = pycall.Py_RETURN_NONE;

pub const PyErr_SetString = pycall.PyErr_SetString;
pub const PyErr_SetObject = pycall.PyErr_SetObject;
pub const PyErr_Occurred = pycall.PyErr_Occurred;
pub const PyErr_Clear = pycall.PyErr_Clear;

pub const PyObject_GetAttrString = pycall.PyObject_GetAttrString;
pub const PyObject_SetAttrString = pycall.PyObject_SetAttrString;
pub const PyObject_CallObject = pycall.PyObject_CallObject;
pub const PyObject_Str = pycall.PyObject_Str;
pub const PyObject_IsTrue = pycall.PyObject_IsTrue;

pub const PyArg_ParseTuple = pycall.PyArg_ParseTuple;
pub const Py_BuildValue = pycall.Py_BuildValue;

pub const PyList_New = pycall.PyList_New;
pub const PyList_Size = pycall.PyList_Size;
pub const PyList_GetItem = pycall.PyList_GetItem;
pub const PyList_SetItem = pycall.PyList_SetItem;
pub const PyList_Append = pycall.PyList_Append;
pub const PyList_Check = pycall.PyList_Check;

pub const PyDict_New = pycall.PyDict_New;
pub const PyDict_SetItemString = pycall.PyDict_SetItemString;
pub const PyDict_GetItemString = pycall.PyDict_GetItemString;
pub const PyDict_Size = pycall.PyDict_Size;
pub const PyDict_Check = pycall.PyDict_Check;

pub const PyTuple_New = pycall.PyTuple_New;
pub const PyTuple_Size = pycall.PyTuple_Size;
pub const PyTuple_GetItem = pycall.PyTuple_GetItem;
pub const PyTuple_SetItem = pycall.PyTuple_SetItem;

pub const PyExc_Exception = pycall.PyExc_Exception;
pub const PyExc_ValueError = pycall.PyExc_ValueError;
pub const PyExc_TypeError = pycall.PyExc_TypeError;
pub const PyExc_RuntimeError = pycall.PyExc_RuntimeError;
pub const PyExc_StopIteration = pycall.PyExc_StopIteration;
pub const PyExc_ImportError = pycall.PyExc_ImportError;
pub const PyExc_AttributeError = pycall.PyExc_AttributeError;
pub const PyExc_KeyError = pycall.PyExc_KeyError;
pub const PyExc_IndexError = pycall.PyExc_IndexError;
pub const PyExc_OSError = pycall.PyExc_OSError;
pub const PyExc_MemoryError = pycall.PyExc_MemoryError;
pub const PyExc_OverflowError = pycall.PyExc_OverflowError;
pub const PyExc_NotImplementedError = pycall.PyExc_NotImplementedError;
pub const PyExc_SystemError = pycall.PyExc_SystemError;
pub const PyExc_ZeroDivisionError = pycall.PyExc_ZeroDivisionError;

pub const Py_None = pycall.Py_None;
pub const Py_True = pycall.Py_True;
pub const Py_False = pycall.Py_False;
pub const Py_NotImplemented = pycall.Py_NotImplemented;

pub const PyMem_RawMalloc = pycall.PyMem_RawMalloc;
pub const PyMem_RawFree = pycall.PyMem_RawFree;

pub const pz_guard = pycall.pz_guard;
pub const pz_guard_active = pycall.pz_guard_active;
pub const pz_panic_longjmp = pycall.pz_panic_longjmp;

pub const PyType_FromSpec = pycall.PyType_FromSpec;
pub const PyType_FromSpecWithBases = pycall.PyType_FromSpecWithBases;
pub const PyType_Ready = pycall.PyType_Ready;
pub const PyType_Check = pycall.PyType_Check;
pub const PyType_IsSubtype = pycall.PyType_IsSubtype;

pub const PyErr_Format = pycall.PyErr_Format;
pub const PyErr_NewException = pycall.PyErr_NewException;

pub const PyObject_Repr = pycall.PyObject_Repr;
pub const PyObject_Type = pycall.PyObject_Type;
pub const PyObject_IsInstance = pycall.PyObject_IsInstance;
pub const PyObject_CallFunction = pycall.PyObject_CallFunction;

pub const PyGILState_Ensure = pycall.PyGILState_Ensure;
pub const PyGILState_Release = pycall.PyGILState_Release;

pub const PyUnicode_DecodeUTF8 = pycall.PyUnicode_DecodeUTF8;

pub const PyBytes_FromString = pycall.PyBytes_FromString;
pub const PyBytes_AsString = pycall.PyBytes_AsString;

pub const Py_XNewRef = pycall.Py_XNewRef;

pub const PyModuleDef_Init = pycall.PyModuleDef_Init;
pub const PyModule_AddFunctions = pycall.PyModule_AddFunctions;

pub const Py_tp_dealloc = pytypes.Py_tp_dealloc;
pub const Py_tp_new = pytypes.Py_tp_new;
pub const Py_tp_getset = pytypes.Py_tp_getset;
pub const Py_tp_methods = pytypes.Py_tp_methods;
pub const Py_tp_str = pytypes.Py_tp_str;
pub const Py_tp_repr = pytypes.Py_tp_repr;
pub const Py_tp_hash = pytypes.Py_tp_hash;
pub const Py_tp_richcompare = pytypes.Py_tp_richcompare;
pub const Py_TPFLAGS_DEFAULT = pytypes.Py_TPFLAGS_DEFAULT;
pub const Py_TPFLAGS_HEAPTYPE = pytypes.Py_TPFLAGS_HEAPTYPE;

pub fn method(
    comptime name: [:0]const u8,
    comptime func: anytype,
    comptime flags: c_int,
    comptime doc: [:0]const u8,
) PyMethodDef {
    return .{
        .ml_name = @as(?[*:0]const u8, @ptrCast(name.ptr)),
        .ml_meth = @ptrCast(func),
        .ml_flags = flags,
        .ml_doc = @as(?[*:0]const u8, @ptrCast(doc.ptr)),
    };
}
