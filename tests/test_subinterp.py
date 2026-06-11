"""End-to-end sub-interpreter test for an *installed* pyo3zig_demo wheel.

Proves the extension's multi-phase init + per-interpreter type caches let it load
and run in (shared-GIL / "legacy") sub-interpreters — every class, operator,
inheritance, container conversion and the custom exception work in a fresh
interpreter, and several interpreters coexist with independent type objects.

Single-phase modules (the pre-1.0 design) raise ImportError when imported into a
sub-interpreter, so a passing run here is the real proof of support.

Run directly:  python tests/test_subinterp.py
Skips cleanly when the low-level `_interpreters` API (CPython 3.13+) is absent.
"""

import sys

failures = 0


def check(name, ok):
    global failures
    print(f"  {'PASS' if ok else 'FAIL'}  {name}")
    if not ok:
        failures += 1


def main() -> int:
    try:
        import _interpreters
    except ImportError:
        print("SKIP: _interpreters not available (needs CPython 3.13+)")
        return 0
    if not hasattr(_interpreters, "run_string"):
        print("SKIP: _interpreters.run_string not available")
        return 0

    # The module must already work in the main interpreter.
    import os

    sys.path.insert(0, ".")
    import pyo3zig_demo as m

    check("main interpreter: class", m.Dog(2, False).legs_count() == 2)

    # The directory the extension was imported from, so the sub-interpreter can
    # find it regardless of cwd / how this script was launched.
    path0 = os.path.dirname(os.path.abspath(getattr(m, "__file__", ""))) or os.getcwd()
    # Body executed inside each sub-interpreter. Any AssertionError propagates out
    # of run_string as an error, failing the test.
    body = """
import sys
sys.path.insert(0, {path!r})
import pyo3zig_demo as m

assert m.hello().startswith("Hello"), m.hello()
assert m.add(2, 3) == 5
g = m.Greeter(7)
assert g == m.Greeter(7) and str(g) == "Greeter(val=7)"
v = m.Vec2(1, 2) + m.Vec2(3, 4)
assert (v.x, v.y) == (4, 6)
d = m.Dog({legs}, True)
assert isinstance(d, m.Animal) and d.legs_count() == {legs} and d.bark() and d.legs == {legs}
assert m.dict_sum({{"a": 1, "b": 2, "c": 3}}) == 6
assert m.unique_bytes(b"aab") == {{97, 98}}
assert m.cmul(complex(0, 1), complex(0, 1)) == complex(-1, 0)
import datetime
assert m.make_dt(2026, 6, 11).year == 2026
try:
    m.check_positive(-1)
    raise AssertionError("DemoError not raised")
except m.DemoError:
    pass
"""

    # Run in two independent (shared-GIL) sub-interpreters.
    ids = []
    try:
        for legs in (4, 6):
            i = _interpreters.create("legacy")
            ids.append(i)
            rc = _interpreters.run_string(i, body.format(path=path0, legs=legs))
            check(f"sub-interpreter (legs={legs}) ran clean", rc is None or rc == 0)
    finally:
        for i in ids:
            try:
                _interpreters.destroy(i)
            except Exception:
                pass

    # The main interpreter still works after sub-interpreters came and went.
    check("main interpreter intact afterwards", m.Greeter(9) == m.Greeter(9))

    print("subinterpreter E2E OK" if failures == 0 else f"{failures} FAILURE(S)")
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
