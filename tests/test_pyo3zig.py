"""Tests for the pyo3zig extension module."""

import sys
import os

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))

import pyo3zig_demo as m

passed = 0
failed = 0

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

def test_hello():
    result = m.hello()
    check("hello", result == "Hello from pyo3zig!", repr(result))

def test_add():
    check("add(2,3)==5", m.add(2, 3) == 5)
    check("add(-1,1)==0", m.add(-1, 1) == 0)
    check("add(0,0)==0", m.add(0, 0) == 0)
    check("add(large)==3000000", m.add(1000000, 2000000) == 3000000)
    check("add(-5,-3)==-8", m.add(-5, -3) == -8)

def test_double():
    check("double(2.5)==5.0", m.double(2.5) == 5.0)
    check("double(0.0)==0.0", m.double(0.0) == 0.0)
    check("double(-3.0)==-6.0", m.double(-3.0) == -6.0)

def test_greet():
    check("greet('World')", m.greet("World") == "Hello, World!")
    check("greet('')", m.greet("") == "Hello, !")
    check("greet('Alice')", m.greet("Alice") == "Hello, Alice!")

def test_error_arg_count():
    try:
        m.add(1)
        check("add(1) should raise", False)
    except TypeError as e:
        check("add(1) TypeError", "expected 2 arguments, got 1" in str(e), str(e))
    try:
        m.add(1, 2, 3)
        check("add(1,2,3) should raise", False)
    except TypeError as e:
        check("add(1,2,3) TypeError", "expected 2 arguments, got 3" in str(e), str(e))

def test_error_type():
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

def test_module():
    check("has hello", hasattr(m, "hello"))
    check("has add", hasattr(m, "add"))
    check("has double", hasattr(m, "double"))
    check("has greet", hasattr(m, "greet"))
    check("name is pyo3zig_demo", m.__name__ == "pyo3zig_demo")

def test_large_ints():
    check("add(2**62,1)", m.add(2**62, 1) == 2**62 + 1)
    check("add(-2**62,-1)", m.add(-(2**62), -1) == -(2**62) - 1)

def test_class():
    check("Greeter class exists", hasattr(m, "Greeter"))
    g = m.Greeter(42)
    check("Greeter val init", g.val == 42)
    check("Greeter method greet", g.greet() == "Hello, val=42!")

    g.val = 99
    check("Greeter set val", g.val == 99)
    check("Greeter greet after set", g.greet() == "Hello, val=99!")

    g2 = m.Greeter(100)
    check("Greeter second instance", g2.greet() == "Hello, val=100!")

def test_bytes():
    check("repeat_bytes exists", hasattr(m, "repeat_bytes"))
    result = m.repeat_bytes(b"AB", 3)
    check("repeat_bytes returns bytes", isinstance(result, bytes))
    check("repeat_bytes correct value", result == b"ABABAB")

    result2 = m.repeat_bytes(b"x", 0)
    check("repeat_bytes zero count", result2 == b"")

    result3 = m.repeat_bytes(b"abc", 3)
    check("repeat_bytes abc*3", result3 == b"abcabcabc")


if __name__ == "__main__":
    for name, fn in sorted((n, f) for n, f in globals().items() if n.startswith("test_")):
        print(f"\n[{name}]")
        fn()
    total = passed + failed
    print(f"\n{'='*40}")
    print(f"Results: {passed}/{total} passed" + (f", {failed} failed!" if failed else ", all passed!"))
    sys.exit(0 if failed == 0 else 1)
