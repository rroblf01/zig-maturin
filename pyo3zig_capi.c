#include <Python.h>
#include <datetime.h>
#include <setjmp.h>
#include <string.h>

/* --- datetime C-API -------------------------------------------------------
 * PyDateTime_* are macros over a capsule pointer that must be initialized once
 * with PyDateTime_IMPORT before any use. The module init calls the import. */
int pyo3zig_PyDateTime_Import(void) { PyDateTime_IMPORT; return PyDateTimeAPI ? 0 : -1; }
int pyo3zig_PyDateTime_Check(PyObject* o) { return PyDateTime_Check(o); }
PyObject* pyo3zig_DateTime_New(int y, int mo, int d, int h, int mi, int s, int us) {
    return PyDateTime_FromDateAndTime(y, mo, d, h, mi, s, us);
}
int pyo3zig_DateTime_year(PyObject* o) { return PyDateTime_GET_YEAR(o); }
int pyo3zig_DateTime_month(PyObject* o) { return PyDateTime_GET_MONTH(o); }
int pyo3zig_DateTime_day(PyObject* o) { return PyDateTime_GET_DAY(o); }
int pyo3zig_DateTime_hour(PyObject* o) { return PyDateTime_DATE_GET_HOUR(o); }
int pyo3zig_DateTime_minute(PyObject* o) { return PyDateTime_DATE_GET_MINUTE(o); }
int pyo3zig_DateTime_second(PyObject* o) { return PyDateTime_DATE_GET_SECOND(o); }
int pyo3zig_DateTime_microsecond(PyObject* o) { return PyDateTime_DATE_GET_MICROSECOND(o); }

/* --- Ready awaitable ------------------------------------------------------
 * A one-shot awaitable iterator: the first iteration raises StopIteration with
 * the carried value, so `await obj` resolves to it immediately. CPython has no
 * public helper for this, so we ship a tiny iterator type. The Zig am_await
 * wrapper builds one from the user's __await__ return value. */
typedef struct {
    PyObject_HEAD
    PyObject* value;
    int is_stop; /* 1 -> raise StopAsyncIteration instead of returning value */
} PzReadyAwaitable;

static PyObject* pzra_iternext(PyObject* self) {
    PzReadyAwaitable* a = (PzReadyAwaitable*)self;
    if (a->is_stop) {
        PyErr_SetNone(PyExc_StopAsyncIteration);
        return NULL;
    }
    PyErr_SetObject(PyExc_StopIteration, a->value ? a->value : Py_None);
    return NULL;
}
static PyObject* pzra_iter(PyObject* self) { Py_INCREF(self); return self; }
static void pzra_dealloc(PyObject* self) {
    Py_XDECREF(((PzReadyAwaitable*)self)->value);
    Py_TYPE(self)->tp_free(self);
}
/* Being its own awaitable (am_await -> self) lets it be the value returned by
 * __anext__ and then `await`ed by the async-for machinery. */
static PyAsyncMethods pzra_as_async = { .am_await = pzra_iter };
static PyTypeObject PzReadyAwaitable_Type = {
    PyVarObject_HEAD_INIT(NULL, 0)
    .tp_name = "pyo3zig._ReadyAwaitable",
    .tp_basicsize = sizeof(PzReadyAwaitable),
    .tp_flags = Py_TPFLAGS_DEFAULT,
    .tp_iter = pzra_iter,
    .tp_iternext = pzra_iternext,
    .tp_as_async = &pzra_as_async,
    .tp_dealloc = pzra_dealloc,
};

static PyObject* pzra_new(PyObject* value, int is_stop) {
    if (PyType_Ready(&PzReadyAwaitable_Type) < 0) return NULL;
    PzReadyAwaitable* a = PyObject_New(PzReadyAwaitable, &PzReadyAwaitable_Type);
    if (!a) return NULL;
    Py_XINCREF(value);
    a->value = value;
    a->is_stop = is_stop;
    return (PyObject*)a;
}

/* Awaitable that resolves immediately to `value` (takes its own reference). */
PyObject* pyo3zig_make_ready_awaitable(PyObject* value) { return pzra_new(value, 0); }

/* Awaitable that raises StopAsyncIteration (ends an `async for`). */
PyObject* pyo3zig_make_stop_async_awaitable(void) { return pzra_new(NULL, 1); }

/* __class_getitem__: build a types.GenericAlias so classes are subscriptable in
 * type hints (e.g. Stack[int]). origin is the class, item the subscript. */
PyObject* pyo3zig_GenericAlias(PyObject* origin, PyObject* item) {
    return Py_GenericAlias(origin, item);
}

/* Managed __dict__ helpers. The public PyObject_*ManagedDict names landed in
 * 3.13; 3.12 has the underscore-prefixed variants. */
int pyo3zig_VisitManagedDict(PyObject* o, visitproc v, void* a) {
#if PY_VERSION_HEX >= 0x030D0000
    return PyObject_VisitManagedDict(o, v, a);
#else
    return _PyObject_VisitManagedDict(o, v, a);
#endif
}
void pyo3zig_ClearManagedDict(PyObject* o) {
#if PY_VERSION_HEX >= 0x030D0000
    PyObject_ClearManagedDict(o);
#else
    _PyObject_ClearManagedDict(o);
#endif
}

/* --- Panic safety net -----------------------------------------------------
 * Zig has no stack unwinding, so a panic would normally abort the whole
 * interpreter. pz_guard() runs the extension body inside a setjmp frame; the
 * Zig panic handler calls pz_panic_longjmp() to jump back here and return NULL
 * (with a Python exception already set) instead of crashing. setjmp must live
 * in a frame that stays alive while the body runs, hence the callback shape.
 * Nested calls are supported by save/restore of the jump buffer.
 */
static _Thread_local jmp_buf pz_jmp;
static _Thread_local int pz_jmp_active = 0;

PyObject* pz_guard(PyObject* (*fn)(void*), void* ctx) {
    jmp_buf saved;
    int saved_active = pz_jmp_active;
    memcpy(&saved, &pz_jmp, sizeof(jmp_buf));
    pz_jmp_active = 1;
    PyObject* result;
    if (setjmp(pz_jmp)) {
        result = NULL; /* arrived via longjmp; exception already set */
    } else {
        result = fn(ctx);
    }
    pz_jmp_active = saved_active;
    memcpy(&pz_jmp, &saved, sizeof(jmp_buf));
    return result;
}

/* Integer-returning variants for slots whose C signature returns Py_ssize_t
 * (__len__) or int (__setitem__, __contains__). They share the same jmp_buf
 * stack as pz_guard and return -1 (CPython's error sentinel) on longjmp; the
 * panic handler has already set a Python exception before jumping. */
Py_ssize_t pz_guard_ssize(Py_ssize_t (*fn)(void*), void* ctx) {
    jmp_buf saved;
    int saved_active = pz_jmp_active;
    memcpy(&saved, &pz_jmp, sizeof(jmp_buf));
    pz_jmp_active = 1;
    Py_ssize_t result;
    if (setjmp(pz_jmp)) {
        result = -1;
    } else {
        result = fn(ctx);
    }
    pz_jmp_active = saved_active;
    memcpy(&pz_jmp, &saved, sizeof(jmp_buf));
    return result;
}

int pz_guard_int(int (*fn)(void*), void* ctx) {
    jmp_buf saved;
    int saved_active = pz_jmp_active;
    memcpy(&saved, &pz_jmp, sizeof(jmp_buf));
    pz_jmp_active = 1;
    int result;
    if (setjmp(pz_jmp)) {
        result = -1;
    } else {
        result = fn(ctx);
    }
    pz_jmp_active = saved_active;
    memcpy(&pz_jmp, &saved, sizeof(jmp_buf));
    return result;
}

int pz_guard_active(void) { return pz_jmp_active; }

void pz_panic_longjmp(void) { longjmp(pz_jmp, 1); }

/* tp_name of an object's type — used to build precise TypeError messages
 * ("expected int, got str") without reproducing the PyTypeObject layout. */
const char* pz_type_name(PyObject* o) { return Py_TYPE(o)->tp_name; }

PyObject* pyo3zig_PyExc_TypeError(void) { return PyExc_TypeError; }
PyObject* pyo3zig_PyExc_ValueError(void) { return PyExc_ValueError; }
PyObject* pyo3zig_PyExc_RuntimeError(void) { return PyExc_RuntimeError; }
PyObject* pyo3zig_PyExc_StopIteration(void) { return PyExc_StopIteration; }
PyObject* pyo3zig_PyExc_ImportError(void) { return PyExc_ImportError; }
PyObject* pyo3zig_PyExc_AttributeError(void) { return PyExc_AttributeError; }
PyObject* pyo3zig_PyExc_KeyError(void) { return PyExc_KeyError; }
PyObject* pyo3zig_PyExc_IndexError(void) { return PyExc_IndexError; }
PyObject* pyo3zig_PyExc_OSError(void) { return PyExc_OSError; }
PyObject* pyo3zig_PyExc_MemoryError(void) { return PyExc_MemoryError; }
PyObject* pyo3zig_PyExc_OverflowError(void) { return PyExc_OverflowError; }
PyObject* pyo3zig_PyExc_NotImplementedError(void) { return PyExc_NotImplementedError; }
PyObject* pyo3zig_PyExc_SystemError(void) { return PyExc_SystemError; }
PyObject* pyo3zig_PyExc_ZeroDivisionError(void) { return PyExc_ZeroDivisionError; }
PyObject* pyo3zig_PyExc_Exception(void) { return PyExc_Exception; }

PyObject* pyo3zig_Py_None(void) { return Py_None; }
PyObject* pyo3zig_Py_True(void) { return Py_True; }
PyObject* pyo3zig_Py_False(void) { return Py_False; }
PyObject* pyo3zig_Py_NotImplemented(void) { return Py_NotImplemented; }

PyObject* pyo3zig_PyLong_Type(void) { return (PyObject*)&PyLong_Type; }
PyObject* pyo3zig_PyFloat_Type(void) { return (PyObject*)&PyFloat_Type; }
PyObject* pyo3zig_PyBool_Type(void) { return (PyObject*)&PyBool_Type; }
PyObject* pyo3zig_PyUnicode_Type(void) { return (PyObject*)&PyUnicode_Type; }
PyObject* pyo3zig_PyList_Type(void) { return (PyObject*)&PyList_Type; }
PyObject* pyo3zig_PyDict_Type(void) { return (PyObject*)&PyDict_Type; }
PyObject* pyo3zig_PyTuple_Type(void) { return (PyObject*)&PyTuple_Type; }
PyObject* pyo3zig_PyType_Type(void) { return (PyObject*)&PyType_Type; }
PyObject* pyo3zig_PyBytes_Type(void) { return (PyObject*)&PyBytes_Type; }
PyObject* pyo3zig_PyByteArray_Type(void) { return (PyObject*)&PyByteArray_Type; }

/* The canonical "this type is unhashable" hash function. CPython special-cases
 * this exact pointer in tp_hash to expose __hash__ as None (the semantics of a
 * class that defines __eq__ but no __hash__). */
void* pyo3zig_HashNotImplemented(void) { return (void*)PyObject_HashNotImplemented; }
