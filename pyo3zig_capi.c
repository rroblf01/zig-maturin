#include <Python.h>
#include <setjmp.h>
#include <string.h>

/* --- Ready awaitable ------------------------------------------------------
 * A one-shot awaitable iterator: the first iteration raises StopIteration with
 * the carried value, so `await obj` resolves to it immediately. CPython has no
 * public helper for this, so we ship a tiny iterator type built via
 * PyType_FromSpec (so it compiles under the Limited API too). The Zig am_await
 * wrapper builds one from the user's __await__ return value. */
typedef struct {
    PyObject ob_base;
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
    freefunc tp_free = (freefunc)PyType_GetSlot(Py_TYPE(self), Py_tp_free);
    tp_free(self);
}
/* am_await -> self lets it be the value returned by __anext__ and then
 * `await`ed by the async-for machinery. */
static PyType_Slot pzra_slots[] = {
    {Py_tp_iter, pzra_iter},
    {Py_tp_iternext, pzra_iternext},
    {Py_am_await, pzra_iter},
    {Py_tp_dealloc, pzra_dealloc},
    {0, NULL},
};
static PyType_Spec pzra_spec = {
    .name = "pyo3zig._ReadyAwaitable",
    .basicsize = sizeof(PzReadyAwaitable),
    .flags = Py_TPFLAGS_DEFAULT,
    .slots = pzra_slots,
};
/* The awaitable type is cached PER INTERPRETER: a heap type belongs to the
 * interpreter that created it, so it must not be shared across sub-interpreters.
 * Keyed by PyInterpreterState*; the (shared) GIL serializes access, and the
 * mutex additionally guards a free-threaded build. */
typedef struct { PyInterpreterState* interp; PyObject* type; } PzraEntry;
static PzraEntry pzra_entries[16];

#ifdef Py_GIL_DISABLED
static PyMutex pzra_lock = {0};
#endif

static PyObject* pzra_get_type(void) {
    PyInterpreterState* cur = PyInterpreterState_Get();
    for (int i = 0; i < 16; i++) {
        if (pzra_entries[i].interp == cur) return pzra_entries[i].type;
    }
#ifdef Py_GIL_DISABLED
    PyMutex_Lock(&pzra_lock);
    for (int i = 0; i < 16; i++) {
        if (pzra_entries[i].interp == cur) { PyMutex_Unlock(&pzra_lock); return pzra_entries[i].type; }
    }
#endif
    PyObject* t = PyType_FromSpec(&pzra_spec);
    if (t) {
        int placed = 0;
        for (int i = 0; i < 16; i++) {
            if (pzra_entries[i].interp == NULL) { pzra_entries[i].interp = cur; pzra_entries[i].type = t; placed = 1; break; }
        }
        if (!placed) { pzra_entries[0].interp = cur; pzra_entries[0].type = t; }
    }
#ifdef Py_GIL_DISABLED
    PyMutex_Unlock(&pzra_lock);
#endif
    return t;
}

/* Drop the current interpreter's awaitable type on module teardown, so a later
 * interpreter reusing the freed PyInterpreterState address never reads a stale
 * type pointer. */
void pyo3zig_clear_awaitable_cache(void) {
    PyInterpreterState* cur = PyInterpreterState_Get();
    for (int i = 0; i < 16; i++) {
        if (pzra_entries[i].interp == cur) {
            /* We own this type (PyType_FromSpec); release it so a torn-down
             * interpreter doesn't leak its awaitable type. */
            Py_XDECREF(pzra_entries[i].type);
            pzra_entries[i].interp = NULL;
            pzra_entries[i].type = NULL;
        }
    }
}

static PyObject* pzra_new(PyObject* value, int is_stop) {
    PyObject* pzra_type = pzra_get_type();
    if (!pzra_type) return NULL;
    PzReadyAwaitable* a =
        (PzReadyAwaitable*)PyType_GenericAlloc((PyTypeObject*)pzra_type, 0);
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

/* Declare that this single-phase module is safe to run without the GIL. On a
 * free-threaded interpreter, modules that do not opt in force the GIL back on
 * for the whole process; opting in keeps the no-GIL benefit. No-op on a regular
 * build (and under the Limited API, which has no free-threaded ABI). The shim
 * already uses out-of-line refcounting and per-thread state, and the lazy caches
 * are mutex-guarded, so the extension is free-threading clean. */
void pyo3zig_module_declare_no_gil(PyObject* module) {
#if defined(Py_GIL_DISABLED) && !defined(Py_LIMITED_API)
    PyUnstable_Module_SetGIL(module, Py_MOD_GIL_NOT_USED);
#else
    (void)module;
#endif
}

/* Return the await-iterator of an arbitrary awaitable (coroutine, Future, or an
 * object with __await__). Every awaitable exposes __await__, so calling it is
 * uniform and Limited-API-safe. Used to delegate a class's __await__ to a real
 * awaitable so `await obj` truly suspends. */
PyObject* pyo3zig_get_await_iter(PyObject* awaitable) {
    return PyObject_CallMethod(awaitable, "__await__", NULL);
}

/* __class_getitem__: build a types.GenericAlias so classes are subscriptable in
 * type hints (e.g. Stack[int]). origin is the class, item the subscript. */
PyObject* pyo3zig_GenericAlias(PyObject* origin, PyObject* item) {
    return Py_GenericAlias(origin, item);
}

/* Managed __dict__ helpers. Not part of the stable ABI, so under the Limited
 * API they are no-ops (the Zig side does not enable a managed dict in that
 * mode). The public PyObject_*ManagedDict names landed in 3.13; 3.12 has the
 * underscore-prefixed variants. */
#ifdef Py_LIMITED_API
int pyo3zig_VisitManagedDict(PyObject* o, visitproc v, void* a) {
    (void)o; (void)v; (void)a; return 0;
}
void pyo3zig_ClearManagedDict(PyObject* o) { (void)o; }
#else
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
#endif

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
 * ("expected int, got str"). The full API reads tp_name directly; the Limited
 * API can't touch the struct, so it copies the type's __name__ into a
 * thread-local buffer (the result is consumed immediately by the caller). */
#ifdef Py_LIMITED_API
const char* pz_type_name(PyObject* o) {
    static _Thread_local char buf[256];
    buf[0] = 0;
    PyObject* name = PyType_GetName(Py_TYPE(o)); /* new ref, str */
    if (name) {
        const char* s = PyUnicode_AsUTF8AndSize(name, NULL);
        if (s) {
            strncpy(buf, s, sizeof(buf) - 1);
            buf[sizeof(buf) - 1] = 0;
        }
        Py_DECREF(name);
    }
    return buf;
}
#else
const char* pz_type_name(PyObject* o) { return Py_TYPE(o)->tp_name; }
#endif

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

/* PyComplex_Check is a macro; wrap it so Zig can call it. */
int pyo3zig_PyComplex_Check(PyObject* o) { return PyComplex_Check(o); }

/* PyAnySet_Check (set or frozenset) is a macro; wrap it for Zig. */
int pyo3zig_PyAnySet_Check(PyObject* o) { return PyAnySet_Check(o); }

/* The canonical "this type is unhashable" hash function. CPython special-cases
 * this exact pointer in tp_hash to expose __hash__ as None (the semantics of a
 * class that defines __eq__ but no __hash__). */
void* pyo3zig_HashNotImplemented(void) { return (void*)PyObject_HashNotImplemented; }
