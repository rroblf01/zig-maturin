"""Quick benchmark: Zig extension vs pure Python.

Build + install the demo first:
    zig-maturin build && pip install --find-links dist --no-index pyo3zig_demo
Then:
    python examples/bench.py
"""

import time

import pyo3zig_demo as m


def bench(label, fn, n=50):
    # warm up
    fn()
    start = time.perf_counter()
    for _ in range(n):
        fn()
    elapsed = time.perf_counter() - start
    print(f"{label:<28} {elapsed / n * 1e3:8.3f} ms/call")


N = 1_000_000

print(f"Summing 0..{N} ({N:,} iterations), 50 calls each\n")

bench("Zig (GIL released)", lambda: m.heavy_sum(N))
bench("Pure Python sum(range)", lambda: sum(range(N)))


def py_loop():
    total = 0
    for i in range(N):
        total += i
    return total


bench("Pure Python for-loop", py_loop)
