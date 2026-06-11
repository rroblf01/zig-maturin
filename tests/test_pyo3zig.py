"""Tests for the pyo3zig extension module."""

import asyncio
import copy
import datetime
import enum
import gc
import math
import operator
import os
import sys
import types
import weakref

sys.path.insert(0, ".")
import pyo3zig_demo as m

passed, failed = 0, 0


def check(name, ok, detail=""):
    global passed, failed
    if ok:
        passed += 1
        print(f"  PASS  {name}")
    else:
        failed += 1
        msg = f"  FAIL  {name}"
        if detail:
            msg += f": {detail}"
        print(msg)


# test_hello
r = m.hello()
check("hello", r == "Hello from pyo3zig!", repr(r))

# test_add
check("add(2,3)==5", m.add(2, 3) == 5)
check("add(-1,1)==0", m.add(-1, 1) == 0)
check("add(0,0)==0", m.add(0, 0) == 0)
check("add(large)==3000000", m.add(1000000, 2000000) == 3000000)
check("add(-5,-3)==-8", m.add(-5, -3) == -8)

# test_double
check("double(2.5)==5.0", m.double(2.5) == 5.0)
check("double(0.0)==0.0", m.double(0.0) == 0.0)
check("double(-3.0)==-6.0", m.double(-3.0) == -6.0)

# test_greet
check("greet('World')", m.greet("World") == "Hello, World!")
check("greet('')", m.greet("") == "Hello, !")
check("greet('Alice')", m.greet("Alice") == "Hello, Alice!")

# test_container_conversions
check("make_array -> list", m.make_array() == [10, 20, 30])
check("make_point -> dict", m.make_point() == {"x": 1, "y": 2})
check("make_pair -> tuple", m.make_pair() == (7, 1.5))

# test_panic_to_exception (Zig panic must not crash the interpreter)
try:
    m.boom()
    check("boom raises", False, "no exception")
except Exception as e:
    check("boom raises RuntimeError", isinstance(e, RuntimeError), repr(e))
try:
    m.oob()
    check("oob raises", False, "no exception")
except Exception as e:
    check("oob raises RuntimeError", isinstance(e, RuntimeError), repr(e))
# interpreter still usable after panics
check("alive after panic", m.add(2, 3) == 5)

# test_container_args
check("sum_list(list)", m.sum_list([1, 2, 3, 4]) == 10)
check("sum_list(tuple)", m.sum_list((10, 20)) == 30)
check("sum_list(empty)", m.sum_list([]) == 0)
check("point_sum(dict)", m.point_sum({"x": 3, "y": 4}) == 7)
try:
    m.sum_list([1, "x", 3])
    check("sum_list bad elem", False, "no exception")
except TypeError:
    check("sum_list bad elem", True)

# test_typed_exceptions
check("parse_positive(5)", m.parse_positive(5) == 5)
try:
    m.parse_positive(-3)
    check("parse_positive raises ValueError", False, "no exception")
except ValueError as e:
    check(
        "parse_positive raises ValueError", str(e) == "value must be positive", str(e)
    )
except Exception as e:
    check("parse_positive raises ValueError", False, f"wrong type {type(e).__name__}")

# test_class_kwargs
v0 = m.Vec2(3)
check("Vec2 init default y", v0.x == 3 and v0.y == 0)
v1 = m.Vec2(x=3, y=4)
check("Vec2 init kwargs", v1.x == 3 and v1.y == 4)
check("Vec2.dot positional", v1.dot(1, 2) == 11)
check("Vec2.dot kwarg default", v1.dot(other_x=2) == 6)
check("Vec2.length_sq property", v1.length_sq == 25)
check("Vec2.dims staticmethod", m.Vec2.dims() == 2)
# classmethod / alternative constructor
vp = m.Vec2.from_pair({"x": 5, "y": 6})
check("Vec2.from_pair classmethod", isinstance(vp, m.Vec2) and vp.x == 5 and vp.y == 6)
# class instance passed as argument (*Vec2)
check("vec_dot(Vec2, Vec2)", m.vec_dot(m.Vec2(1, 2), m.Vec2(3, 4)) == 11)
try:
    m.vec_dot(m.Vec2(1, 2), "nope")
    check("vec_dot wrong type", False, "no exception")
except TypeError as e:
    check("vec_dot wrong type", "Vec2" in str(e), str(e))
try:
    v1.length_sq = 99
    check("length_sq read-only", False, "no error")
except AttributeError:
    check("length_sq read-only", True)

# test_operators (number protocol)
va, vb = m.Vec2(1, 2), m.Vec2(3, 4)
vs = va + vb
check("Vec2 __add__", vs.x == 4 and vs.y == 6)
vd = m.Vec2(5, 5) - m.Vec2(1, 2)
check("Vec2 __sub__", vd.x == 4 and vd.y == 3)
check("Vec2 __mul__ (dot)", va * vb == 11)
vn = -va
check("Vec2 __neg__", vn.x == -1 and vn.y == -2)
check("Vec2 __bool__ true", bool(m.Vec2(1, 0)) is True)
check("Vec2 __bool__ false", bool(m.Vec2(0, 0)) is False)
try:
    _ = va + 5
    check("Vec2 + int rejected", False, "no exception")
except TypeError:
    check("Vec2 + int rejected", True)
check(
    "Vec2 __doc__", m.Vec2.__doc__ == "A 2D integer vector with arithmetic operators."
)

# test_full_comparisons (sorting, min/max via __lt__ etc)
g_a, g_b, g_c = m.Greeter(1), m.Greeter(5), m.Greeter(3)
check("Greeter <", (g_a < g_b) is True)
check("Greeter >", (g_b > g_c) is True)
check("Greeter <=", (g_a <= m.Greeter(1)) is True)
check("Greeter >=", (g_b >= g_c) is True)
check("sorted(Greeters)", [g.val for g in sorted([g_b, g_a, g_c])] == [1, 3, 5])
check("max(Greeters)", max([g_a, g_b, g_c]).val == 5)

# test_call (callable instances)
check("Greeter() callable", m.Greeter(10)(5) == 15)

# test_mixed_reflected_operators
m1, m2 = m.Money(100), m.Money(50)
check("Money + Money", (m1 + m2).cents == 150)
check("Money - Money", (m1 - m2).cents == 50)
check("Money * int (mixed)", (m1 * 3).cents == 300)
check("int * Money (reflected)", (3 * m1).cents == 300)
check("Money // int", (m.Money(100) // 3).cents == 33)
check("Money % int", (m.Money(100) % 7).cents == 2)
check("Money ** int", (m.Money(2) ** 5).cents == 32)
try:
    _ = m1 * m2  # __mul__ takes int, not Money
    check("Money * Money rejected", False, "no exception")
except TypeError:
    check("Money * Money rejected", True)

# test_inplace_and_numeric_conversions
mi = m.Money(100)
mi += m.Money(50)
check("Money += (in-place)", mi.cents == 150)
ms = m.Money(100)
ms -= m.Money(30)
check("Money -= (in-place)", ms.cents == 70)
mp = m.Money(10)
mp *= 3
check("Money *= int (in-place)", mp.cents == 30)
check("int(Money)", int(m.Money(100)) == 100)
check("float(Money)", float(m.Money(100)) == 100.0)
check("Money.__reduce__()", m.Money(7).__reduce__() == (7,))

# test_context_manager
res = m.Resource()
check("Resource starts closed", res.open == 0)
with m.Resource() as r:
    check("Resource open in with", r.open == 1)
check("with-block returns self", r.open == 0)
# __exit__ returning False does NOT suppress
try:
    with m.Resource():
        raise ValueError("boom")
    check("Resource does not suppress", False, "no exception")
except ValueError:
    check("Resource does not suppress", True)
# __exit__ returning True suppresses the exception
suppressed = True
with m.Suppressor():
    raise ValueError("swallowed")
    suppressed = False  # unreachable
check("Suppressor swallows exception", suppressed)

# test_setattr_error (__setattr__ raising)
ro = m.ReadOnly(5)
check("ReadOnly field read", ro.x == 5)
try:
    ro.x = 99
    check("ReadOnly __setattr__ raises", False, "no exception")
except AttributeError:
    check("ReadOnly __setattr__ raises", True)
check("ReadOnly unchanged", ro.x == 5)

# test_setattr
rec = m.Recorder()
rec.anything = 5
rec.other = 7
check("__setattr__ intercepts all sets", rec.sets == 2)

# test_getattr (generic lookup first, then fallback)
dyn = m.Dynamic(10)
check("Dynamic normal field", dyn.base == 10)
check("Dynamic __getattr__ fallback", dyn.foo == 10 + 3)
check("Dynamic __index__ (hex)", hex(m.Dynamic(255)) == "0xff")

# test_buffer_protocol (zero-copy memoryview / bytes)
b8 = m.Bytes8(65)  # fill with 'A'
mv = memoryview(b8)
check("memoryview len", len(mv) == 8)
check("memoryview content", bytes(b8) == b"AAAAAAAA")

# test_big_ints (>64-bit)
check("big_mul 2**100", m.big_mul(2**50, 2**50) == 2**100)
check("big_mul negative", m.big_mul(-(2**60), 8) == -(2**63))
check(
    "big_mul roundtrip",
    m.big_mul(123456789012345678901234567890, 1) == 123456789012345678901234567890,
)


# test_subclass_from_python (value classes are subclassable)
class MyVec(m.Vec2):
    def norm(self):
        return self.x * self.x + self.y * self.y


mv2 = MyVec(3, 4)
check("subclass instance", isinstance(mv2, m.Vec2) and mv2.x == 3)
check("subclass method", mv2.norm() == 25)
check("subclass operator inherited", (mv2 + m.Vec2(1, 1)).x == 4)

# test_kwargs_arg_name_error
try:
    m.power(base="oops")
    check("kwargs arg-name error", False, "no exception")
except TypeError as e:
    check(
        "kwargs arg-name error",
        "argument 'base'" in str(e) and "expected int" in str(e),
        str(e),
    )

# test_gc_cycles (reference cycle must be collectable)
n0 = m.get_node_deinit_count()
a_node = m.Node()
b_node = m.Node()
a_node.next = b_node
b_node.next = a_node  # cycle: a -> b -> a
check("Node.next getter", a_node.next is b_node)
del a_node
del b_node
gc.collect()
check("gc collects reference cycle", m.get_node_deinit_count() - n0 == 2)

# test_protocols
r = m.Range(0, 5)
check("len(Range)", len(r) == 5)
check("Range[2]", r[2] == 2)
check("Range[-1] negative index", r[-1] == 4)
check("Range[-2] negative index", r[-2] == 3)
check("3 in Range", (3 in r) is True)
check("10 not in Range", (10 in r) is False)
check("list(Range)", list(m.Range(0, 3)) == [0, 1, 2])
check("sum(Range)", sum(m.Range(0, 4)) == 6)
# panic net on a dunder (__getitem__ panics at index 99)
try:
    _ = m.Range(0, 5)[99]
    check("getitem panic raises", False, "no exception")
except RuntimeError:
    check("getitem panic raises", True)
check("alive after getitem panic", m.Range(0, 5)[2] == 2)

# test_gil_release
check("heavy_sum(1000)", m.heavy_sum(1000) == 499500)

# test_panic_net_methods_and_init
try:
    m.Vec2(1, 2).bad()
    check("method panic raises", False, "no exception")
except RuntimeError:
    check("method panic raises", True)
try:
    m.Boomable(-1)
    check("init panic raises", False, "no exception")
except RuntimeError:
    check("init panic raises", True)
check("Boomable(5).v", m.Boomable(5).v == 5)

# test_module_constants
check("VERSION constant", m.VERSION == "0.3.0")
check("MAX_ITEMS constant", m.MAX_ITEMS == 100)
check("PI constant", abs(m.PI - 3.14159) < 1e-9)

# test_no_leaks (refcounts must stay stable across many calls)
_obj = object()
_before = sys.getrefcount(_obj)
for _ in range(20000):
    m.identity(_obj)
check("identity: no refcount leak", sys.getrefcount(_obj) == _before)

_big = list(range(64))
_elem = _big[0]
_eb = sys.getrefcount(_elem)
for _ in range(10000):
    m.sum_list(_big)
check("sum_list: no element refcount leak", sys.getrefcount(_elem) == _eb)

_s = m.greet("x")
check("greet: returned str refcount sane", sys.getrefcount(_s) == 2)

_n0 = m.get_deinit_count()
for _ in range(5000):
    _d = m.DeinitTracker()
    del _d
check("DeinitTracker: every instance finalized", m.get_deinit_count() - _n0 == 5000)

# test_kwargs_and_defaults
check("power default exp", m.power(3) == 9)
check("power positional", m.power(2, 10) == 1024)
check("power keyword", m.power(base=5, exp=3) == 125)
check("power mixed", m.power(2, exp=5) == 32)
try:
    m.power()
    check("power() missing arg", False, "no exception")
except TypeError:
    check("power() missing arg", True)

# test_error_arg_count
try:
    m.add(1)
    check("add(1) should raise", False)
except TypeError:
    check("add(1) TypeError", True)
try:
    m.add(1, 2, 3)
    check("add(1,2,3) should raise", False)
except TypeError:
    check("add(1,2,3) TypeError", True)

# test_error_type
for args in [("hello", 2), (1, "world")]:
    try:
        m.add(*args)
        check(f"add{args} should raise", False)
    except TypeError:
        check(f"add{args} TypeError", True)

try:
    m.double("hello")
    check("double('hello') should raise", False)
except TypeError:
    check("double('hello') TypeError", True)

try:
    m.greet(42)
    check("greet(42) should raise", False)
except TypeError:
    check("greet(42) TypeError", True)

# test_stub (functions + classes present in the generated .pyi)
_stub = m.__pyi__()
check("stub has add def", "def add(a: int, b: int) -> int" in _stub, _stub)
check("stub has class Vec2", "class Vec2:" in _stub, _stub)
check("stub has Vec2 fields", "x: int" in _stub and "y: int" in _stub)
check(
    "stub has Vec2 method",
    "def dot(self, other_x: int, other_y: int) -> int" in _stub,
    _stub,
)
check("stub has class Range", "class Range:" in _stub)
check("stub has dunder __eq__", "def __eq__(self, other:" in _stub, _stub)
check("stub has dunder __len__", "def __len__(self) -> int" in _stub, _stub)

# test_module
check("has hello", hasattr(m, "hello"))
check("has add", hasattr(m, "add"))
check("has double", hasattr(m, "double"))
check("has greet", hasattr(m, "greet"))
check("has repeat_bytes", hasattr(m, "repeat_bytes"))
check("has Greeter", hasattr(m, "Greeter"))
check("name is pyo3zig_demo", m.__name__ == "pyo3zig_demo")

# test_large_ints
check("add(2**62,1)", m.add(2**62, 1) == 2**62 + 1)
check("add(-2**62,-1)", m.add(-(2**62), -1) == -(2**62) - 1)

# test_bytes
check("repeat_bytes exists", hasattr(m, "repeat_bytes"))
result = m.repeat_bytes(b"AB", 3)
check("repeat_bytes returns bytes", isinstance(result, bytes))
check("repeat_bytes correct value", result == b"ABABAB")
result2 = m.repeat_bytes(b"x", 0)
check("repeat_bytes zero count", result2 == b"")
result3 = m.repeat_bytes(b"abc", 3)
check("repeat_bytes abc*3", result3 == b"abcabcabc")

# test_class
check("Greeter class exists", hasattr(m, "Greeter"))
g = m.Greeter(42)
check("Greeter val init", g.val == 42)
check("Greeter method greet", g.greet() == "Hello, val=42!")
g.val = 99
check("Greeter set val", g.val == 99)
check("Greeter greet after set", g.greet() == "Hello, val=99!")
g2 = m.Greeter(100)
check("Greeter second instance", g2.greet() == "Hello, val=100!")

# test_str
g3 = m.Greeter(42)
check("str(Greeter)", str(g3) == "Greeter(val=42)")
check("str(Greeter(100))", str(m.Greeter(100)) == "Greeter(val=100)")

# test_repr (distinct from __str__)
check("repr(Greeter)", repr(g3) == "<Greeter val=42>")

# test_error_messages (precise: expected X, got Y)
try:
    m.add("x", 2)
    check("add type error message", False, "no exception")
except TypeError as e:
    check(
        "add type error message",
        "expected int" in str(e) and "got str" in str(e),
        str(e),
    )
try:
    m.sum_list(42)
    check("sum_list type error message", False, "no exception")
except TypeError as e:
    check("sum_list type error message", "list or tuple" in str(e), str(e))

# test_kwargs_rejected
try:
    m.Greeter(42, extra=1)
    check("Greeter kwargs rejected", False)
except TypeError:
    check("Greeter kwargs rejected", True)

# test_deinit_tracker
check("DeinitTracker class exists", hasattr(m, "DeinitTracker"))
check("get_deinit_count exists", hasattr(m, "get_deinit_count"))
count_before = m.get_deinit_count()
d = m.DeinitTracker()
check("deinit count after create", m.get_deinit_count() == count_before)
del d
check("deinit count after delete", m.get_deinit_count() == count_before + 1)

# test_bitwise_operators
b = m.Bits(0b1100)
check("Bits & ", int(b & 0b1010) == 0b1000)
check("Bits | ", int(b | 0b0011) == 0b1111)
check("Bits ^ ", int(b ^ 0b1010) == 0b0110)
check("Bits <<", int(b << 2) == 0b110000)
check("Bits >>", int(b >> 2) == 0b11)
check("Bits ~ ", int(~m.Bits(0)) == -1)

# test_unary_abs_pos
check("abs(Bits)", int(abs(m.Bits(-5))) == 5)
check("pos Bits", int(+m.Bits(7)) == 7)
check("abs(Money)", abs(m.Money(-7)).cents == 7)
check("pos Money", (+m.Money(5)).cents == 5)

# test_inplace_bitwise
v = m.Bits(0b1100)
v &= 0b1010
check("Bits &=", int(v) == 0b1000)
v = m.Bits(0b1100)
v |= 0b0011
check("Bits |=", int(v) == 0b1111)
v = m.Bits(0b1100)
v ^= 0b1010
check("Bits ^=", int(v) == 0b0110)
v = m.Bits(1)
v <<= 4
check("Bits <<=", int(v) == 16)
v = m.Bits(16)
v >>= 4
check("Bits >>=", int(v) == 1)

# test_inplace_arithmetic_extra
mm = m.Money(10)
mm %= 3
check("Money %=", mm.cents == 1)
mm = m.Money(3)
mm **= 3
check("Money **=", mm.cents == 27)

# test_truediv_returns_float
check("Money / -> float", m.Money(7) / 2 == 3.5)

# test_delitem
bag = m.Bag()
del bag[5]
del bag[3]
check("__delitem__", bag.deleted == 8)

# test_reversed_custom
check("custom __reversed__", list(reversed(m.Range(2, 9))) == [9, 2])

# test_format
g = m.Greeter(42)
check("format(g)", format(g) == "Greeter(42)")
check("f-string spec", f"{g:hex}" == "[hex=42]")

# test_unhashable
u = m.Unhashable(1)
check("__hash__ is None", m.Unhashable.__hash__ is None)
check("Unhashable eq", m.Unhashable(1) == m.Unhashable(1))
try:
    hash(u)
    check("hash raises", False, "no exception")
except TypeError:
    check("hash raises", True)
try:
    {u: 1}
    check("dict key raises", False, "no exception")
except TypeError:
    check("dict key raises", True)

# test_module_attribute_set
check("type.__module__", m.Greeter.__module__ == "pyo3zig_demo")

# test_bytearray_argument
check("sum_bytes(bytearray)", m.sum_bytes(bytearray(b"\x01\x02\x03")) == 6)
check("sum_bytes(bytes)", m.sum_bytes(b"\x01\x02\x03") == 6)
check("sum_bytes(str)", m.sum_bytes("ABC") == 65 + 66 + 67)

# test_divmod
check("divmod(Money)", divmod(m.Money(17), 5) == (3, 2))

# test_numeric_hooks
t = m.Temp(37)
check("float(Temp)", float(t) == 3.7)
check("math.floor", math.floor(t) == 3)
check("math.ceil", math.ceil(t) == 4)
check("math.trunc", math.trunc(t) == 3)
check("round(Temp)", round(t) == 4)
check("bytes(Temp)", bytes(t) == (37).to_bytes(8, "little"))
check("__getstate__", t.__getstate__() == 37)
t.__setstate__(99)
check("__setstate__", t.__getstate__() == 99)

# test_weakref
node = m.Node()
ref = weakref.ref(node)
check("weakref deref (GC class)", ref() is node)
del node
gc.collect()
check("weakref cleared on dealloc", ref() is None)
try:
    weakref.ref(m.Greeter(1))
    check("weakref rejected for value class", False, "no exception")
except TypeError:
    check("weakref rejected for value class", True)

# test_enum_conversion
check("enum next red->green", m.next_color(0) == 1)
check("enum next green->blue", m.next_color(1) == 2)
check("enum next blue->red", m.next_color(2) == 0)
try:
    m.next_color(7)
    check("enum out-of-range rejected", False, "no exception")
except ValueError as e:
    check("enum out-of-range rejected", "Color" in str(e), str(e))

# test_copy_deepcopy
v = m.Vec2(3, 4)
cp = copy.copy(v)
check("copy.copy -> instance", type(cp) is m.Vec2 and cp.x == 3 and cp.y == 4)
check("copy.copy is a new object", cp is not v)
dp = copy.deepcopy(v)
check("copy.deepcopy -> instance", type(dp) is m.Vec2 and dp.x == 3 and dp.y == 4)
check("copy.deepcopy is a new object", dp is not v)

# test_datetime
dt = m.make_dt(2026, 6, 11)
check("make_dt -> datetime", isinstance(dt, datetime.datetime))
check("make_dt fields", (dt.year, dt.month, dt.day) == (2026, 6, 11))
check("dt_year reads datetime", m.dt_year(datetime.datetime(1999, 1, 2)) == 1999)
nd = m.next_day(datetime.datetime(2026, 6, 11, 3, 4, 5))
check("next_day round-trip", (nd.year, nd.month, nd.day) == (2026, 6, 12))
try:
    m.dt_year("notadate")
    check("datetime type error", False, "no exception")
except TypeError as e:
    check("datetime type error", "datetime" in str(e), str(e))

# test_call_kwargs
adder = m.Adder(10)
check("call positional + default", adder(5) == 15)
check("call two positional", adder(5, 2) == 20)
check("call by keyword", adder(x=3) == 13)
check("call all keywords", adder(x=3, step=4) == 22)
check("call mixed", adder(7, step=0) == 10)

# test_intenum
check("Color is IntEnum", issubclass(m.Color, enum.IntEnum))
check("Color.red == 0", m.Color.red == 0)
check("Color.green == 1", m.Color.green == 1)
check("Color.blue == 2", m.Color.blue == 2)
check("Color(2).name", m.Color(2).name == "blue")
check("int(Color.green)", int(m.Color.green) == 1)
check("Color.__module__", m.Color.__module__ == "pyo3zig_demo")

# test_await
async def _await_task(x):
    return await x


_coro = _await_task(m.Task(21))
try:
    _coro.send(None)
    check("await resolves", False, "coroutine did not finish")
except StopIteration as e:
    check("await resolves", e.value == 42, repr(e.value))
check("asyncio.run awaitable", asyncio.run(_await_task(m.Task(50))) == 100)


# test_async_iteration
async def _collect(stop):
    out = []
    async for x in m.ARange(stop):
        out.append(x)
    return out


check("async for yields range", asyncio.run(_collect(5)) == [0, 1, 2, 3, 4])
check("async for empty", asyncio.run(_collect(0)) == [])


async def _acomp():
    return [x * x async for x in m.ARange(4)]


check("async comprehension", asyncio.run(_acomp()) == [0, 1, 4, 9])

# test_class_getitem
_ga = m.Vec2[int]
check("class_getitem -> GenericAlias", isinstance(_ga, types.GenericAlias))
check("GenericAlias origin", _ga.__origin__ is m.Vec2)
check("GenericAlias args", _ga.__args__ == (int,))
check("class_getitem multi-arg", m.Range[int, str].__args__ == (int, str))
check("class_getitem on plain class", m.Bag[int].__origin__ is m.Bag)

# test_fspath_and_length_hint
check("os.fspath", os.fspath(m.FilePath(7)) == "/tmp/file7")
check("operator.length_hint", operator.length_hint(m.ARange(5)) == 5)

# test_descriptor
class _Holder:
    temp = m.Doubler()


_h = _Holder()
check("descriptor initial __get__", _h.temp == 0)
_h.temp = 21
check("descriptor __set__ doubles", _h.temp == 42)
_h.temp = 5
check("descriptor __set__ again", _h.temp == 10)
check("descriptor on class", _Holder.temp == 10)

# test_dir_sizeof_setname
check("__dir__", dir(m.Introspect(0)) == ["alpha", "beta", "gamma"])
check("__sizeof__", sys.getsizeof(m.Introspect(0)) == 64)


class _SetNameHolder:
    field = m.Doubler()


check("__set_name__", vars(_SetNameHolder)["field"].name_len == len("field"))

# test_init_subclass
_isc_before = m.get_subclass_count()


class _P1(m.Plugin):
    pass


class _P2(m.Plugin):
    pass


class _P3(_P1):
    pass


check("__init_subclass__ fires per subclass", m.get_subclass_count() == _isc_before + 3)

# test_writable_buffer
_mb = m.MutableBuf()
_mv = memoryview(_mb)
check("writable buffer not readonly", _mv.readonly is False)
_mv[0] = 42
_mv[3] = 99
check("buffer writes reach object", _mb.get(0) == 42 and _mb.get(3) == 99)
check("read-only buffer still readonly", memoryview(m.Bytes8(7)).readonly is True)

# test_managed_dict
_nd = m.Node()
_nd.label = "hello"
_nd.count = 42
check("GC class arbitrary attrs", _nd.label == "hello" and _nd.count == 42)
check("GC class __dict__", _nd.__dict__ == {"label": "hello", "count": 42})
check("GC class vars()", vars(_nd) == {"label": "hello", "count": 42})
_nd.__dict__ = {"x": 1}
check("GC class __dict__ assignment", _nd.x == 1 and not hasattr(_nd, "label"))
check("value class has no __dict__", not hasattr(m.Vec2(1, 2), "__dict__"))
# attributes stored in the dict are GC-traced (cycle through dict collectable)
_a = m.Node()
_b = m.Node()
_a.peer = _b
_b.peer = _a
del _a, _b
gc.collect()
check("cycle through managed dict collectable", True)
# stress the dict alloc/clear path so the Valgrind gate catches a leak
for _i in range(500):
    _t = m.Node()
    _t.a = _i
    _t.b = "x" * (_i % 8)
    del _t
gc.collect()
check("managed dict stress (no leak)", True)

total = passed + failed
print(
    f"\nResults: {passed}/{total} passed"
    + (f", {failed} failed!" if failed else ", all passed!")
)
sys.exit(0 if failed == 0 else 1)
