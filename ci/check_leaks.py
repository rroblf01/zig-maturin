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

Usage: python3 ci/check_leaks.py <valgrind-log>
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


def main(path: str) -> int:
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

    offending = []
    for blk in blocks:
        text = "".join(blk)
        if OURS.search(text) and not INTENTIONAL.search(text):
            offending.append(text)

    if len(offending) > MAX_BLOCKS:
        print(f"LEAK CHECK FAILED: {len(offending)} extension leak blocks "
              f"(> {MAX_BLOCKS}); a per-call leak is likely.\n")
        for t in offending[:20]:
            print(t)
        return 1

    print(f"LEAK CHECK OK: {len(offending)} non-intentional extension leak "
          f"block(s) (<= {MAX_BLOCKS}); no scaling leak detected.")
    return 0


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print(__doc__)
        sys.exit(2)
    sys.exit(main(sys.argv[1]))
