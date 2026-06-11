# Reproduces the CI `leak-check` job locally: builds the demo extension with
# Zig and runs the test suite under Valgrind. Build + run from the repo root:
#
#   docker build -f ci/leakcheck.Dockerfile -t zm-leakcheck .
#   docker run --rm zm-leakcheck
#
# Exit code 99 means Valgrind found a definite leak (the full report is printed).
# Use the official Python image (self-contained headers in /usr/local, like the
# CI's setup-python) — Ubuntu's system Python splits headers into a multiarch
# directory that python3-config doesn't fully report.
FROM python:3.13-bookworm

ARG ZIG_VERSION=0.16.0
ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
        valgrind curl ca-certificates xz-utils \
    && rm -rf /var/lib/apt/lists/*

# Install the pinned Zig toolchain.
RUN curl -fsSL "https://ziglang.org/download/${ZIG_VERSION}/zig-x86_64-linux-${ZIG_VERSION}.tar.xz" \
        | tar -xJ -C /opt \
    && ln -s "/opt/zig-x86_64-linux-${ZIG_VERSION}/zig" /usr/local/bin/zig

WORKDIR /app
COPY . .

ENV PYTHONMALLOC=malloc

RUN zig build

CMD ["bash", "-c", "set -e; cp zig-out/lib/libpyo3zig_demo.so pyo3zig_demo.so && \
  valgrind \
    --leak-check=full --show-leak-kinds=definite,indirect --num-callers=20 \
    --log-file=/tmp/valgrind.log \
    python3 tests/test_pyo3zig.py && \
  python3 ci/check_leaks.py /tmp/valgrind.log && \
  sed 's/range(100)/range(10)/' tests/test_subinterp.py > /tmp/si_small.py && \
  sed 's/range(100)/range(80)/' tests/test_subinterp.py > /tmp/si_big.py && \
  valgrind --leak-check=full --show-leak-kinds=definite,indirect --num-callers=20 \
    --log-file=/tmp/vg_si_small.log python3 /tmp/si_small.py && \
  valgrind --leak-check=full --show-leak-kinds=definite,indirect --num-callers=20 \
    --log-file=/tmp/vg_si_big.log python3 /tmp/si_big.py && \
  python3 ci/check_leaks.py --scaling /tmp/vg_si_small.log /tmp/vg_si_big.log 10 80"]
