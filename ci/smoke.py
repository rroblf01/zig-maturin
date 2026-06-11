"""End-to-end smoke test run against an *installed* pyo3zig_demo wheel.

Used by CI to prove the extension built by `zig-maturin build` actually loads
and runs on each OS (Linux/macOS/Windows) and Python version.
"""

import platform

import pyo3zig_demo as m

assert m.hello() == "Hello from pyo3zig!", m.hello()
assert m.add(2, 3) == 5
assert m.double(2.5) == 5.0
assert m.greet("CI") == "Hello, CI!", m.greet("CI")
assert m.identity([1, 2]) == [1, 2]
assert m.repeat_bytes(b"ab", 3) == b"ababab"

g = m.Greeter(7)
assert g == m.Greeter(7)
assert g != m.Greeter(9)
assert (g != m.Greeter(7)) is False, "richcompare NE must honor op"
assert str(g) == "Greeter(val=7)", str(g)

# Nested submodule: attribute access and dotted import.
import importlib  # noqa: E402

assert m.mathx.triple(4) == 12, m.mathx.triple(4)
assert importlib.import_module("pyo3zig_demo.mathx").triple(3) == 9

# complex round-trip (std.math.Complex <-> Python complex).
assert m.cmul(complex(1, 2), complex(3, 4)) == complex(-5, 10)

print(f"smoke OK on {platform.platform()} / Python {platform.python_version()}")
