const std = @import("std");

pub const Py_ssize_t = isize;

pub const PyObject = opaque {};

pub const PyCFunction = *const fn (?*PyObject, ?*PyObject) callconv(.c) ?*PyObject;

pub const METH_VARARGS: c_int = 0x0001;
pub const METH_KEYWORDS: c_int = 0x0002;
pub const METH_NOARGS: c_int = 0x0004;
pub const METH_O: c_int = 0x0008;

pub const PyMethodDef = extern struct {
    ml_name: ?[*:0]const u8,
    ml_meth: ?PyCFunction,
    ml_flags: c_int,
    ml_doc: ?[*:0]const u8,
};

pub const PyModuleDef_Base = extern struct {
    ob_refcnt: Py_ssize_t,
    ob_type: ?*PyObject,
    m_init: ?*const fn () callconv(.c) ?*PyObject,
    m_index: Py_ssize_t,
    m_copy: ?*PyObject,
};

pub const PyModuleDef = extern struct {
    m_base: PyModuleDef_Base,
    m_name: ?[*:0]const u8,
    m_doc: ?[*:0]const u8,
    m_size: Py_ssize_t,
    m_methods: ?[*]PyMethodDef,
    m_slots: ?*anyopaque,
    m_traverse: ?*anyopaque,
    m_clear: ?*anyopaque,
    m_free: ?*anyopaque,
};

pub const PyModuleDef_HEAD_INIT = PyModuleDef_Base{
    .ob_refcnt = @as(Py_ssize_t, 0x00050000c0000000),
    .ob_type = null,
    .m_init = null,
    .m_index = 0,
    .m_copy = null,
};
