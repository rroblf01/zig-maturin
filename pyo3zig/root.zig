const zm = @import("zig-maturin");

pub const errors = @import("errors.zig");
pub const refcount = @import("refcount.zig");
pub const gil = @import("gil.zig");
pub const conversion = @import("conversion.zig");
pub const types = @import("types.zig");
pub const args = @import("args.zig");
pub const funcwrap = @import("funcwrap.zig");
pub const module = @import("module.zig");
pub const pycell = @import("pycell.zig");
pub const pyclass = @import("pyclass.zig");

pub const panic = @import("panic.zig").panic;
pub const panicFn = @import("panic.zig").panicFn;

pub const stubgen = @import("stubgen.zig");
pub const pyType = stubgen.pyType;
pub const funcStub = stubgen.funcStub;
pub const moduleStub = stubgen.moduleStub;
pub const methodStub = stubgen.methodStub;
pub const classStub = stubgen.classStub;

pub const pyModule = module.pyModule;
pub const exportModule = module.exportModule;
pub const PyClass = pyclass.PyClass;
pub const enumClass = pyclass.enumClass;
pub const exceptionClass = pyclass.exceptionClass;
pub const PyCell = pycell.PyCell;
pub const pyFn = funcwrap.pyFn;
pub const pyFnNamed = funcwrap.pyFnNamed;
pub const pyFnKw = funcwrap.pyFnKw;
pub const pyFnRaw = funcwrap.pyFnRaw;
pub const wrap = funcwrap.wrap;
pub const wrapNamed = funcwrap.wrapNamed;
pub const wrapMethodNamed = pyclass.wrapMethodNamed;
pub const wrapMethodKw = pyclass.wrapMethodKw;
pub const staticMethod = pyclass.staticMethod;
pub const classMethod = pyclass.classMethod;

pub const PyString = types.PyString;
pub const PyInt = types.PyInt;
pub const PyFloat = types.PyFloat;
pub const PyBool = types.PyBool;
pub const PyList = types.PyList;
pub const PyDict = types.PyDict;
pub const PyTuple = types.PyTuple;
pub const PyBytes = types.PyBytes;
pub const datetime = @import("datetime.zig");
pub const DateTime = datetime.DateTime;

pub const setError = errors.setError;
pub const newException = errors.newException;
pub const PyExc_ValueError = zm.PyExc_ValueError;
pub const PyExc_TypeError = zm.PyExc_TypeError;
pub const PyExc_KeyError = zm.PyExc_KeyError;
pub const PyExc_IndexError = zm.PyExc_IndexError;
pub const PyExc_RuntimeError = zm.PyExc_RuntimeError;
pub const PyExc_OverflowError = zm.PyExc_OverflowError;
pub const PyExc_ZeroDivisionError = zm.PyExc_ZeroDivisionError;
pub const PyExc_AttributeError = zm.PyExc_AttributeError;
pub const PyExc_NotImplementedError = zm.PyExc_NotImplementedError;
pub const PyExc_OSError = zm.PyExc_OSError;
pub const PyExc_MemoryError = zm.PyExc_MemoryError;
pub const PyExc_Exception = zm.PyExc_Exception;

pub const GILGuard = gil.GILGuard;
pub const allowThreads = gil.allowThreads;
pub const PyObjectRef = refcount.PyObjectRef;
pub const toPyObject = conversion.toPyObject;
pub const fromPyObject = conversion.fromPyObject;

pub const Py_NewRef = zm.Py_NewRef;
pub const Py_INCREF = zm.Py_INCREF;
pub const Py_DECREF = zm.Py_DECREF;
pub const Py_XINCREF = zm.Py_XINCREF;
pub const Py_XDECREF = zm.Py_XDECREF;
pub const Py_None = zm.Py_None;

// Raw container/scalar accessors, for `pyFnRaw` variadic functions that walk the
// argument tuple / keyword dict directly.
pub const PyTuple_Size = zm.PyTuple_Size;
pub const PyTuple_GetItem = zm.PyTuple_GetItem;
pub const PyDict_GetItemString = zm.PyDict_GetItemString;
pub const PyLong_FromLongLong = zm.PyLong_FromLongLong;
pub const PyLong_AsLongLong = zm.PyLong_AsLongLong;

pub const PyObject = zm.PyObject;
pub const PyMethodDef = zm.PyMethodDef;
pub const PyModuleDef = zm.PyModuleDef;
pub const PyModuleDef_HEAD_INIT = zm.PyModuleDef_HEAD_INIT;
pub const METH_NOARGS = zm.METH_NOARGS;
pub const METH_VARARGS = zm.METH_VARARGS;
pub const METH_KEYWORDS = zm.METH_KEYWORDS;
