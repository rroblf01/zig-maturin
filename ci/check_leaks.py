#!/usr/bin/env python3
"""Gate a Valgrind log on memory leaks attributable to the Zig extension.

Running a full CPython interpreter under Valgrind reports thousands of
"definitely lost" blocks that belong to CPython itself (compile, marshal,
interned strings, ...), not to us — so failing on the global leak total is
meaningless. This checker instead keeps only the lost blocks whose stack passes
through the extension, drops the intentional one-time allocations, and fails if
what remains looks like a *scaling* leak.

Why "scaling": the test suite exercises the hot paths tens of thousands of times
(20k identity calls, 10k container conversions, 5k instances). A genuine
per-call/per-instance leak therefore shows up as thousands of lost blocks. A
handful of blocks is a one-time finalization artifact, not a real bug.

Usage:
  python3 ci/check_leaks.py <valgrind-log>
      Absolute gate: fail if > MAX_BLOCKS extension blocks (the main suite, which
      hammers the hot paths so a per-call leak shows up as thousands of blocks).

  python3 ci/check_leaks.py --scaling <small-log> <big-log> <small-n> <big-n>
      Scaling gate for the sub-interpreter test: the only correctness question is
      whether the leak *grows* with the number of interpreters. A fixed one-time
      cost (CPython's own imperfect sub-interpreter teardown — orphaned module
      dict / interned strings) is expected; a per-interpreter leak grows roughly
      linearly with the interpreter count. Fail only on growth.
"""
from __future__ import annotations

import re
import sys

# Frames that mean a block was allocated by our extension.
OURS = re.compile(r"pyclass\.|module\.zig|conversion\.zig|funcwrap\.|pyo3zig_demo")
# Intentional, process-lifetime allocations: per-class type metadata
# (tp_getset / tp_methods arrays) built once and owned by the type for the
# interpreter's lifetime — the standard pattern for C extension types.
INTENTIONAL = re.compile(r"getTypeObject")

# A real per-call leak would produce thousands of blocks under the suite's
# iteration counts; tolerate a few one-time artifacts below this bound.
MAX_BLOCKS = 5

HEADER = re.compile(r"==\d+==\s+\d[\d,]*\s+bytes in (\d[\d,]*) blocks are (?:definitely|indirectly) lost")


def offending_blocks(path: str) -> list[str]:
    with open(path, encoding="utf-8", errors="replace") as fh:
        lines = fh.readlines()

    blocks: list[list[str]] = []
    current: list[str] | None = None
    for line in lines:
        if HEADER.search(line):
            if current:
                blocks.append(current)
            current = [line]
        elif current is not None:
            # A block's frames are the indented "==N==    at/by 0x..." lines;
            # a line without that shape ends the block.
            if re.search(r"==\d+==\s+(at|by) 0x", line):
                current.append(line)
            else:
                blocks.append(current)
                current = None
    if current:
        blocks.append(current)

    out = []
    for blk in blocks:
        text = "".join(blk)
        if OURS.search(text) and not INTENTIONAL.search(text):
            out.append(text)
    return out


def main(path: str) -> int:
    offending = offending_blocks(path)
    if len(offending) > MAX_BLOCKS:
        print(f"LEAK CHECK FAILED: {len(offending)} extension leak blocks "
              f"(> {MAX_BLOCKS}); a per-call leak is likely.\n")
        for t in offending[:20]:
            print(t)
        return 1

    print(f"LEAK CHECK OK: {len(offending)} non-intentional extension leak "
          f"block(s) (<= {MAX_BLOCKS}); no scaling leak detected.")
    return 0


def scaling(small_log: str, big_log: str, small_n: int, big_n: int) -> int:
    small = len(offending_blocks(small_log))
    big = len(offending_blocks(big_log))
    grew = big - small
    span = max(1, big_n - small_n)
    # A per-interpreter leak adds >= 1 block per extra interpreter, so growth
    # tracks `span`. Allow a small slack for one-off teardown jitter.
    allowed = max(3, span // 4)
    if grew > allowed:
        print(f"LEAK CHECK FAILED (scaling): {small} blocks at n={small_n}, "
              f"{big} at n={big_n} (+{grew} over {span} more interpreters, "
              f"allowed +{allowed}); a per-interpreter leak is likely.")
        return 1
    print(f"LEAK CHECK OK (scaling): {small} blocks at n={small_n}, {big} at "
          f"n={big_n} (+{grew} <= +{allowed}); leak is fixed one-time cost, "
          f"not per-interpreter.")
    return 0


if __name__ == "__main__":
    if len(sys.argv) == 2:
        sys.exit(main(sys.argv[1]))
    if len(sys.argv) == 6 and sys.argv[1] == "--scaling":
        sys.exit(scaling(sys.argv[2], sys.argv[3], int(sys.argv[4]), int(sys.argv[5])))
    print(__doc__)
    sys.exit(2)
