"""Tests for the pyo3zig extension module."""
import gc
import sys
sys.path.insert(0, '.')
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
    check("parse_positive raises ValueError", str(e) == "value must be positive", str(e))
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
check("Vec2 __doc__", m.Vec2.__doc__ == "A 2D integer vector with arithmetic operators.")

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
check("big_mul roundtrip", m.big_mul(123456789012345678901234567890, 1) == 123456789012345678901234567890)

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
    check("kwargs arg-name error", "argument 'base'" in str(e) and "expected int" in str(e), str(e))

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
check("VERSION constant", m.VERSION == "0.4.0")
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
check("stub has Vec2 method", "def dot(self, other_x: int, other_y: int) -> int" in _stub, _stub)
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
    check("add type error message", "expected int" in str(e) and "got str" in str(e), str(e))
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

total = passed + failed
print(f"\nResults: {passed}/{total} passed" + (f", {failed} failed!" if failed else ", all passed!"))
sys.exit(0 if failed == 0 else 1)
