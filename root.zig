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
pub const PyObject_GenericGetAttr = pycall.PyObject_GenericGetAttr;
pub const PyObject_GenericSetAttr = pycall.PyObject_GenericSetAttr;
pub const PyObject_GenericGetDict = pycall.PyObject_GenericGetDict;
pub const PyObject_GenericSetDict = pycall.PyObject_GenericSetDict;
pub const PyLong_FromString = pycall.PyLong_FromString;
pub const PyBuffer_FillInfo = pycall.PyBuffer_FillInfo;
pub const Py_bf_getbuffer = pytypes.Py_bf_getbuffer;
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

pub const PyComplex_FromDoubles = pycall.PyComplex_FromDoubles;
pub const PyComplex_RealAsDouble = pycall.PyComplex_RealAsDouble;
pub const PyComplex_ImagAsDouble = pycall.PyComplex_ImagAsDouble;
pub fn PyComplex_Check(o: ?*pytypes.PyObject) c_int {
    return pycall.pyo3zig_PyComplex_Check(o);
}

pub const PyDict_New = pycall.PyDict_New;
pub const PyDict_SetItemString = pycall.PyDict_SetItemString;
pub const PyDict_GetItemString = pycall.PyDict_GetItemString;
pub const PyDict_Size = pycall.PyDict_Size;
pub const PyDict_Check = pycall.PyDict_Check;

pub const PyTuple_New = pycall.PyTuple_New;
pub const PyTuple_Size = pycall.PyTuple_Size;
pub const PyTuple_GetItem = pycall.PyTuple_GetItem;
pub const PyTuple_SetItem = pycall.PyTuple_SetItem;
pub const PyTuple_Check = pycall.PyTuple_Check;

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

pub const visitproc = pycall.visitproc;
pub const PyType_GenericAlloc = pycall.PyType_GenericAlloc;
pub const PyObject_Free = pycall.PyObject_Free;
pub const PyObject_GC_UnTrack = pycall.PyObject_GC_UnTrack;
pub const PyObject_GC_Del = pycall.PyObject_GC_Del;

pub const pz_guard = pycall.pz_guard;
pub const pz_guard_ssize = pycall.pz_guard_ssize;
pub const pz_guard_int = pycall.pz_guard_int;
pub const pz_guard_active = pycall.pz_guard_active;
pub const pz_panic_longjmp = pycall.pz_panic_longjmp;
pub const pz_type_name = pycall.pz_type_name;

pub const PyType_FromSpec = pycall.PyType_FromSpec;
pub const PyType_FromSpecWithBases = pycall.PyType_FromSpecWithBases;
pub const PyType_Ready = pycall.PyType_Ready;
pub const PyType_Check = pycall.PyType_Check;
pub const PyType_IsSubtype = pycall.PyType_IsSubtype;

pub const PyErr_Format = pycall.PyErr_Format;
pub const PyErr_NewException = pycall.PyErr_NewException;
pub const PyErr_ExceptionMatches = pycall.PyErr_ExceptionMatches;

pub const PyObject_Repr = pycall.PyObject_Repr;
pub const PyImport_ImportModule = pycall.PyImport_ImportModule;
pub const PyImport_GetModuleDict = pycall.PyImport_GetModuleDict;
pub const PyObject_Type = pycall.PyObject_Type;
pub const PyObject_IsInstance = pycall.PyObject_IsInstance;
pub const PyObject_CallFunction = pycall.PyObject_CallFunction;

pub const PyGILState_Ensure = pycall.PyGILState_Ensure;
pub const PyGILState_Release = pycall.PyGILState_Release;
pub const PyThreadState = pycall.PyThreadState;
pub const PyEval_SaveThread = pycall.PyEval_SaveThread;
pub const PyEval_RestoreThread = pycall.PyEval_RestoreThread;

pub const PyUnicode_DecodeUTF8 = pycall.PyUnicode_DecodeUTF8;

pub const PyBytes_FromString = pycall.PyBytes_FromString;
pub const PyBytes_AsString = pycall.PyBytes_AsString;

pub const PyByteArray_Check = pycall.PyByteArray_Check;
pub const PyByteArray_AsString = pycall.PyByteArray_AsString;
pub const PyByteArray_Size = pycall.PyByteArray_Size;
pub const HashNotImplemented = pycall.HashNotImplemented;
pub const PyObject_ClearWeakRefs = pycall.PyObject_ClearWeakRefs;
pub const pyo3zig_make_ready_awaitable = pycall.pyo3zig_make_ready_awaitable;
pub const pyo3zig_make_stop_async_awaitable = pycall.pyo3zig_make_stop_async_awaitable;
pub const pyo3zig_get_await_iter = pycall.pyo3zig_get_await_iter;
pub const pyo3zig_module_declare_no_gil = pycall.pyo3zig_module_declare_no_gil;
pub const pyo3zig_GenericAlias = pycall.pyo3zig_GenericAlias;
pub const pyo3zig_VisitManagedDict = pycall.pyo3zig_VisitManagedDict;
pub const pyo3zig_ClearManagedDict = pycall.pyo3zig_ClearManagedDict;
pub const Py_am_await = pytypes.Py_am_await;
pub const Py_am_aiter = pytypes.Py_am_aiter;
pub const Py_am_anext = pytypes.Py_am_anext;


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
pub const Py_tp_iter = pytypes.Py_tp_iter;
pub const Py_tp_iternext = pytypes.Py_tp_iternext;
pub const Py_sq_length = pytypes.Py_sq_length;
pub const Py_sq_contains = pytypes.Py_sq_contains;
pub const Py_mp_subscript = pytypes.Py_mp_subscript;
pub const Py_mp_ass_subscript = pytypes.Py_mp_ass_subscript;
pub const Py_tp_doc = pytypes.Py_tp_doc;
pub const Py_tp_call = pytypes.Py_tp_call;
pub const Py_tp_traverse = pytypes.Py_tp_traverse;
pub const Py_tp_clear = pytypes.Py_tp_clear;
pub const Py_tp_finalize = pytypes.Py_tp_finalize;
pub const Py_nb_add = pytypes.Py_nb_add;
pub const Py_nb_true_divide = pytypes.Py_nb_true_divide;
pub const Py_nb_floor_divide = pytypes.Py_nb_floor_divide;
pub const Py_nb_remainder = pytypes.Py_nb_remainder;
pub const Py_nb_power = pytypes.Py_nb_power;
pub const Py_nb_matrix_multiply = pytypes.Py_nb_matrix_multiply;
pub const Py_nb_subtract = pytypes.Py_nb_subtract;
pub const Py_nb_multiply = pytypes.Py_nb_multiply;
pub const Py_nb_negative = pytypes.Py_nb_negative;
pub const Py_nb_bool = pytypes.Py_nb_bool;
pub const Py_nb_int = pytypes.Py_nb_int;
pub const Py_nb_float = pytypes.Py_nb_float;
pub const Py_nb_index = pytypes.Py_nb_index;
pub const Py_nb_inplace_add = pytypes.Py_nb_inplace_add;
pub const Py_nb_inplace_subtract = pytypes.Py_nb_inplace_subtract;
pub const Py_nb_inplace_multiply = pytypes.Py_nb_inplace_multiply;
pub const Py_nb_absolute = pytypes.Py_nb_absolute;
pub const Py_nb_positive = pytypes.Py_nb_positive;
pub const Py_nb_invert = pytypes.Py_nb_invert;
pub const Py_nb_and = pytypes.Py_nb_and;
pub const Py_nb_or = pytypes.Py_nb_or;
pub const Py_nb_xor = pytypes.Py_nb_xor;
pub const Py_nb_lshift = pytypes.Py_nb_lshift;
pub const Py_nb_rshift = pytypes.Py_nb_rshift;
pub const Py_nb_inplace_true_divide = pytypes.Py_nb_inplace_true_divide;
pub const Py_nb_inplace_floor_divide = pytypes.Py_nb_inplace_floor_divide;
pub const Py_nb_inplace_remainder = pytypes.Py_nb_inplace_remainder;
pub const Py_nb_inplace_power = pytypes.Py_nb_inplace_power;
pub const Py_nb_inplace_matrix_multiply = pytypes.Py_nb_inplace_matrix_multiply;
pub const Py_nb_inplace_and = pytypes.Py_nb_inplace_and;
pub const Py_nb_inplace_or = pytypes.Py_nb_inplace_or;
pub const Py_nb_inplace_xor = pytypes.Py_nb_inplace_xor;
pub const Py_nb_inplace_lshift = pytypes.Py_nb_inplace_lshift;
pub const Py_nb_inplace_rshift = pytypes.Py_nb_inplace_rshift;
pub const Py_tp_getattro = pytypes.Py_tp_getattro;
pub const Py_tp_setattro = pytypes.Py_tp_setattro;
pub const Py_tp_descr_get = pytypes.Py_tp_descr_get;
pub const Py_tp_descr_set = pytypes.Py_tp_descr_set;
pub const Py_TPFLAGS_DEFAULT = pytypes.Py_TPFLAGS_DEFAULT;
pub const Py_TPFLAGS_HEAPTYPE = pytypes.Py_TPFLAGS_HEAPTYPE;
pub const Py_TPFLAGS_BASETYPE = pytypes.Py_TPFLAGS_BASETYPE;
pub const Py_TPFLAGS_HAVE_GC = pytypes.Py_TPFLAGS_HAVE_GC;
pub const Py_TPFLAGS_MANAGED_WEAKREF = pytypes.Py_TPFLAGS_MANAGED_WEAKREF;
pub const Py_TPFLAGS_MANAGED_DICT = pytypes.Py_TPFLAGS_MANAGED_DICT;
pub const Py_nb_divmod = pytypes.Py_nb_divmod;

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
