const std = @import("std");

pub const Py_ssize_t = isize;

pub const PyObject = opaque {};

pub const PyObjectHeader = extern struct {
    ob_refcnt: isize,
    ob_type: ?*anyopaque,
};

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

pub const PyGILState_STATE = c_int;
pub const PyGILState_LOCKED: PyGILState_STATE = 0;
pub const PyGILState_UNLOCKED: PyGILState_STATE = 1;

pub const PyGetSetDef = extern struct {
    name: ?[*:0]const u8,
    get: ?*const fn (?*PyObject, ?*anyopaque) callconv(.c) ?*PyObject,
    set: ?*const fn (?*PyObject, ?*PyObject, ?*anyopaque) callconv(.c) c_int,
    doc: ?[*:0]const u8,
    closure: ?*anyopaque,
};

pub const PyType_Slot = extern struct {
    slot: c_int,
    pfunc: ?*anyopaque,
};

pub const PyType_Spec = extern struct {
    name: [*:0]const u8,
    basicsize: c_int,
    itemsize: c_int,
    flags: c_uint,
    slots: ?[*]PyType_Slot,
};

pub const Py_tp_alloc = 47;
pub const Py_tp_base = 48;
pub const Py_tp_bases = 49;
pub const Py_tp_call = 50;
pub const Py_tp_clear = 51;
pub const Py_tp_dealloc = 52;
pub const Py_tp_del = 53;
pub const Py_tp_descr_get = 54;
pub const Py_tp_descr_set = 55;
pub const Py_tp_doc = 56;
pub const Py_tp_getattr = 57;
pub const Py_tp_getattro = 58;
pub const Py_tp_hash = 59;
pub const Py_tp_init = 60;
pub const Py_tp_is_gc = 61;
pub const Py_tp_iter = 62;
pub const Py_tp_iternext = 63;
pub const Py_tp_methods = 64;
pub const Py_tp_new = 65;
pub const Py_tp_repr = 66;
pub const Py_tp_richcompare = 67;
pub const Py_tp_setattr = 68;
pub const Py_tp_setattro = 69;
pub const Py_tp_str = 70;
pub const Py_tp_traverse = 71;
pub const Py_tp_members = 72;
pub const Py_tp_getset = 73;
pub const Py_tp_free = 74;
pub const Py_tp_finalize = 80;
pub const Py_tp_vectorcall = 82;
pub const Py_tp_token = 83;

pub const Py_TPFLAGS_HEAPTYPE = @as(c_uint, 1 << 9);
pub const Py_TPFLAGS_BASETYPE = @as(c_uint, 1 << 10);
pub const Py_TPFLAGS_HAVE_GC = @as(c_uint, 1 << 14);
pub const Py_TPFLAGS_DEFAULT = @as(c_uint, 0);

pub const Py_bf_getbuffer = 1;
pub const Py_bf_releasebuffer = 2;
pub const Py_mp_ass_subscript = 3;
pub const Py_mp_length = 4;
pub const Py_mp_subscript = 5;
pub const Py_nb_absolute = 6;
pub const Py_nb_add = 7;
pub const Py_nb_and = 8;
pub const Py_nb_bool = 9;
pub const Py_nb_divmod = 10;
pub const Py_nb_float = 11;
pub const Py_nb_floor_divide = 12;
pub const Py_nb_index = 13;
pub const Py_nb_inplace_add = 14;
pub const Py_nb_inplace_and = 15;
pub const Py_nb_inplace_floor_divide = 16;
pub const Py_nb_inplace_lshift = 17;
pub const Py_nb_inplace_multiply = 18;
pub const Py_nb_inplace_or = 19;
pub const Py_nb_inplace_power = 20;
pub const Py_nb_inplace_remainder = 21;
pub const Py_nb_inplace_rshift = 22;
pub const Py_nb_inplace_subtract = 23;
pub const Py_nb_inplace_true_divide = 24;
pub const Py_nb_inplace_xor = 25;
pub const Py_nb_int = 26;
pub const Py_nb_invert = 27;
pub const Py_nb_lshift = 28;
pub const Py_nb_multiply = 29;
pub const Py_nb_negative = 30;
pub const Py_nb_or = 31;
pub const Py_nb_positive = 32;
pub const Py_nb_power = 33;
pub const Py_nb_remainder = 34;
pub const Py_nb_rshift = 35;
pub const Py_nb_subtract = 36;
pub const Py_nb_true_divide = 37;
pub const Py_nb_xor = 38;
pub const Py_sq_ass_item = 39;
pub const Py_sq_concat = 40;
pub const Py_sq_contains = 41;
pub const Py_sq_inplace_concat = 42;
pub const Py_sq_inplace_repeat = 43;
pub const Py_sq_item = 44;
pub const Py_sq_length = 45;
pub const Py_sq_repeat = 46;
pub const Py_nb_matrix_multiply = 75;
pub const Py_nb_inplace_matrix_multiply = 76;
pub const Py_am_await = 77;
pub const Py_am_aiter = 78;
pub const Py_am_anext = 79;
pub const Py_am_send = 81;
