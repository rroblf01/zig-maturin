# Changelog

All notable changes to this project are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/); this project adheres to
[Semantic Versioning](https://semver.org/).

## [0.3.0] - 2026-06-10

### Added
- **Awaitable instances (`__await__`)**: `await obj` resolves to whatever
  `__await__(self)` returns, via a shipped one-shot awaitable-iterator type.
  Works with `asyncio.run`. (Ready/immediate resolution — no suspension.)
- **`enum.IntEnum` classes**: `pz.enumClass(MyEnum, "Name")` exposes a Zig enum
  as a real Python `IntEnum` (registered in `.classes`); each variant becomes a
  member (`Color.RED == 0`).
- **Keyword arguments for `__call__`**: declare `.call_args` (and optional
  `.call_defaults`) on the class config to call instances with keywords/defaults.
- **`datetime.datetime` conversion**: a `pz.DateTime` struct (year/month/day +
  optional time fields) maps to/from Python's `datetime.datetime`. The module
  init runs `PyDateTime_IMPORT` so the C-API capsule is ready.
- **Zig `enum` arguments and return values**: cross the boundary as the enum's
  integer value; an out-of-range int argument raises `ValueError`.
- **`copy.copy` / `copy.deepcopy`**: `__copy__(self)` and
  `__deepcopy__(self, memo)` return a fresh **instance** of the class (wrapped
  like an operator result, not flattened to a dict).
- **`weakref` support** for classes that participate in cyclic GC (those with a
  `?*pz.PyObject` field): instances can be the target of `weakref.ref(obj)` via
  `Py_TPFLAGS_MANAGED_WEAKREF`, cleared in the custom dealloc.
- **`__divmod__`** (`divmod(obj, k)`).
- **Name-lookup numeric hooks**: `__bytes__` (`bytes(obj)`), `__floor__`,
  `__ceil__`, `__trunc__` (`math.*`), `__round__` (`round(obj)`), and pickle's
  `__getstate__` / `__setstate__` — auto-registered as plain methods.
- **Bitwise & shift operators**: `__and__`, `__or__`, `__xor__`, `__lshift__`,
  `__rshift__` (same mixed-operand dispatch as the arithmetic ops).
- **Unary number ops**: `__abs__`, `__pos__`, `__invert__`.
- **Complete in-place operator set**: adds `__itruediv__`, `__ifloordiv__`,
  `__imod__`, `__ipow__`, `__imatmul__`, `__iand__`, `__ior__`, `__ixor__`,
  `__ilshift__`, `__irshift__` (joining `__iadd__`/`__isub__`/`__imul__`).
- **Item deletion**: `__delitem__` (`del obj[key]`), sharing the assignment slot.
- **`__reversed__`** and **`__format__`** (auto-registered; power `reversed()`
  and `format()` / f-string specs).
- **Unhashable by `__eq__`**: a class that defines `__eq__` without `__hash__` is
  now unhashable (`__hash__ is None`), matching Python's own class semantics.
- **`bytearray` arguments** decode to a borrowed `[]const u8` (alongside `bytes`
  and `str`).
- **`__module__` on every class**: types now report their owning module, fixing
  `repr`, pickling, and CPython 3.13's dict-key error message (which reads
  `type.__module__`).
- **Subclassing from Python**: value classes (no `__deinit__`, no PyObject
  fields) set `Py_TPFLAGS_BASETYPE`, so `class Sub(MyClass): ...` inherits
  fields, methods, and operators. Instances now allocate via the type's own
  basicsize, so subclasses are correctly sized.
- **Buffer protocol** (read-only): `__buffer__(self) []const u8` exposes a
  zero-copy view to `memoryview`/`bytes`/numpy.
- **Numeric conversions**: `__int__`, `__float__`, `__index__`.
- **In-place operators**: `__iadd__`, `__isub__`, `__imul__`.
- **Context manager**: `__enter__`/`__exit__` (auto-registered; `__enter__`
  returns `self` when it returns void). **Pickle**: `__reduce__`.
- **Dynamic attributes**: `__getattr__` (only when normal lookup fails) and
  `__setattr__` (intercepts all assignments).
- **Integers wider than 64 bits** (`i65..i128`, `u65..u128`) as arguments and
  return values, round-tripped through CPython's arbitrary-precision int.
- **Argument names in type errors** for keyword-bound calls
  (`argument 'base': expected int, got str`).
- **CI leak-check job**: the full suite runs under Valgrind; `ci/check_leaks.py`
  keeps only the lost blocks attributable to the extension (filtering out
  CPython's own thousands of one-time allocations and our intentional
  process-lifetime type metadata) and fails on a *scaling* leak. Reproducible
  locally with `ci/leakcheck.Dockerfile`.
- **Benchmarks** documented in the README.
- **Full rich comparisons**: `__lt__`, `__le__`, `__gt__`, `__ge__` (any subset);
  `__ne__` is derived from `__eq__`. Enables `sorted()`, `min()`, `max()`.
- **`__call__`**: callable instances (tp_call).
- **Mixed-type and reflected operators**: a binary op's second operand may be a
  scalar (e.g. `money * 2`); `__radd__`/`__rsub__`/`__rmul__` handle the
  reflected form (`2 * money`). Non-matching operands yield `NotImplemented`.
- **More operators**: `__truediv__`, `__floordiv__`, `__mod__`, `__pow__`,
  `__matmul__` (joining `__add__`/`__sub__`/`__mul__`/`__neg__`/`__bool__`).
- **Cyclic garbage collection**: a class with a `?*pz.PyObject` field gets
  `Py_TPFLAGS_HAVE_GC` plus `tp_traverse`/`tp_clear`, so reference cycles are
  collectable. The framework owns one reference per field (incref on set/init,
  decref on clear/dealloc).

### Changed
- Instances are now allocated via `PyType_GenericAlloc` (zero-initialized,
  correctly sized, GC-tracked when applicable) and freed via the matching
  allocator. Fixes a type-reference leak when `__init__` failed.

### Not yet
- **Inheriting a built-in base** (e.g. custom `Exception` subclasses) and
  subclassing classes that need a custom destructor — both need teardown
  orchestration beyond this release.
- **weakref for non-GC value classes** (managed weakref needs the GC pre-header;
  a value class would need an explicit `tp_weaklistoffset` field instead).
- **Suspending coroutines / async iteration** (`__aiter__`/`__anext__`): only
  *ready* awaitables are supported (`__await__` resolves immediately); real
  suspension would need a coroutine driver that yields to the event loop.
- **Inheriting from a `pz.enumClass`** as a Zig `PyClass` base (the IntEnum is a
  standalone Python type, not a Zig-backed class).
- **Subclassing classes that need a custom destructor** (`__deinit__` or GC
  classes): `Py_TPFLAGS_BASETYPE` is set only for value classes, where CPython's
  default dealloc safely handles a subclass's managed `__dict__` and GC.

## [0.2.0] - 2026-06-10

### Added
- **Container arguments**: Python `list`/`tuple` → `[]T`/`[N]T`/tuple struct,
  and `dict` → struct (by field name, honoring field defaults).
- **Class instances as arguments**: pass an instance of one of your classes to a
  function as a `*MyClass` pointer (borrowed, type-checked).
- **`classMethod`**: class methods and alternative constructors — a function
  returning `T` (or `!T`) is wrapped into a fresh instance.
- **`staticMethod`** and computed **properties** (`.properties`) on classes.
- **Keyword arguments + defaults** for free functions (`pyFnKw`), methods
  (`wrapMethodKw`), and `__init__` (`.init_args` / `.init_defaults`).
- **Container / iterator protocols**: `__len__`, `__getitem__`, `__setitem__`,
  `__contains__`, `__iter__`, `__next__` (self-iterators). `__getitem__`
  normalizes negative indices when `__len__` is defined.
- **Operator overloading**: `__add__`, `__sub__`, `__mul__`, `__neg__`,
  `__bool__` (binary ops are same-type, returning `Self` wraps a new instance).
- **Class docstrings** via `.doc` on the `PyClass` config (`help(MyClass)`).
- **`__repr__`** slot (distinct from `__str__`).
- **Typed exceptions**: `pz.setError(exc, msg)` preserves a user-set exception;
  `pz.newException` creates custom exception types.
- **GIL release** for long computations via `pz.allowThreads`.
- **Module constants** via `.constants = .{ ... }`.
- **Compile-time `.pyi` stub generation** shipped inside the wheel, now
  including **class stubs** (`classStub`: fields, `__init__`, and methods).
- **Richer scaffold template** demonstrating panics, `!T` errors, a class with a
  method, and `.pyi` generation out of the box.

### Changed
- **Precise `TypeError` messages** on argument conversion failures
  (`expected int, got str`) instead of a generic message.
- The **panic safety net** now also covers methods, `__init__`, class methods,
  computed properties, and every protocol/dunder slot — a Zig panic anywhere in
  user code becomes a `RuntimeError` instead of aborting the interpreter.

## [0.1.0] - 2026

### Added
- Initial release: `pyModule` / `exportModule`, plain-function wrapping, classes
  with fields and `init`/`__deinit__`/`__str__`/`__hash__`/`__eq__`, the panic
  safety net, wheel building, and honest cross-compilation (glibc-pinned
  manylinux, macOS, Windows) via the `zig-maturin` CLI.
