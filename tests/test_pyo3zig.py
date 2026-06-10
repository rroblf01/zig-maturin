"""Tests for the pyo3zig extension module."""
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
