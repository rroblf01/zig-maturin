# Changelog

All notable changes to this project are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/); this project adheres to
[Semantic Versioning](https://semver.org/).

## [1.0.0] - 2026-06-11

First stable release. The public Zig API (`pyo3zig`, imported as `pz`) and the
`zig_maturin` build tooling are now covered by semantic versioning: breaking
changes to either wait for a 2.0.

### Added
- **Free-threading (no-GIL, PEP 703) support**: extensions declare themselves
  `Py_MOD_GIL_NOT_USED`, so on a free-threaded interpreter (`python3.13t` /
  `python3.14t`) they run without forcing the GIL back on process-wide. The
  shim already uses out-of-line refcounting and per-thread state; the remaining
  process-lifetime caches (the datetime class, the await-iterator type) are now
  published with an atomic compare-exchange / `PyMutex` so first-use is race-free
  without the GIL. Building on a free-threaded interpreter tags the wheel
  `cp3Xt`. (No-op on regular and Limited-API builds.)
- **Toolchain-free `pip install`**: when no `zig` is on PATH, the PEP 517 backend
  pulls in the `ziglang` wheel (a pinned Zig binary) automatically and builds via
  `python -m ziglang`, so `pip install .` works with no system toolchain.
  Developers who already have Zig pay nothing. A `zig-maturin build` from the CLI
  uses the same fallback.
- **Nested submodules**: `.submodules = .{ pz.pyModule("sub", .{...}), ... }` in a
  module config creates child modules, sets them as attributes of the parent, and
  registers them in `sys.modules` under the dotted `parent.child` name (with a
  fully-qualified `__name__`), so both `parent.sub` and `import parent.sub` work.
- **`complex` conversion**: Zig's `std.math.Complex(f64)` / `Complex(f32)` map
  to/from Python `complex` as arguments and return values (an `int`/`float`
  argument coerces, matching Python's own `complex()`).
- **`zig-maturin build --abi3 <X.Y>`** CLI flag: build a stable-ABI wheel without
  editing `pyproject.toml`.
- **Custom exception types** (`pz.exceptionClass("mod.MyError", base)`): register
  a Python exception subclass in a module's `.classes` and raise it from Zig
  (`MyError.raise("msg")`). `base` is a builtin exception getter (e.g.
  `pz.PyExc_ValueError`) or `null` for `Exception`.
- **Variadic functions** (`pz.pyFnRaw("name", fn)`): a function taking
  `(args: ?*PyObject, kwargs: ?*PyObject)` receives the raw argument tuple and
  keyword dict for `*args` / `**kwargs` handling.
- **Computed properties** documented: `.properties = &.{ .{ .name, .get, .set } }`
  exposes getter/setter attributes via `PyGetSetDef` (`set` optional → read-only).
- **`os.PathLike` arguments**: a `pathlib.Path` (anything implementing
  `__fspath__`) is accepted wherever a `[]const u8` string is expected, coerced
  via `os.fspath` and copied into the call arena.
- **Mixed Python/Zig package layout**: when `<python-source>/<module>/` is a
  package, the wheel ships its pure-Python files and nests the compiled extension
  inside it (`module/module.so`, re-exported from `__init__.py`).
- **PEP 660 editable installs**: `pip install -e .` works via a `build_editable`
  hook (debug build; re-install to recompile after Zig changes).
- **`zig-maturin generate-ci`**: writes a GitHub Actions workflow that builds
  wheels across Linux/macOS/Windows × CPython versions and publishes to PyPI on a
  tag (Trusted Publishing). Toolchain-free (uses the `ziglang` wheel).
- **Richer type stubs**: the generated `.pyi` now reflects `complex`, `set` /
  `frozenset` / `dict`, computed `@property` accessors (`classStub`
  `.properties`), variadic functions (`*args`/`**kwargs` via `moduleStub`
  `.raw`), custom exception subclasses (`pz.exceptionStub("Name", "Base")`), and
  base classes (`classStub` `.base`).
- **`dict`↔`std.HashMap` conversion**: a Python `dict` maps to/from a managed
  `std.StringHashMap(V)` / `std.AutoHashMap(K, V)` as arguments and return values
  (argument maps are backed by the per-call arena). Keys/values convert by their
  element types.
- **`set` / `frozenset` output**: `pz.PySet` and `pz.PyFrozenSet` wrapper types
  build Python sets from Zig (like `pz.PyList` / `pz.PyDict`).
- **Zig-class inheritance** (`.base = SomeZigClass`): a `PyClass` can inherit from
  another `PyClass` (`Py_tp_base`). The derived struct embeds the base struct as
  its first field; the base's methods and field accessors are inherited and
  operate correctly on derived instances, `isinstance`/`issubclass` work, and a
  Python class can further subclass the derived type.
- **Sub-interpreter support**: modules now use multi-phase init (PEP 489) and
  declare `Py_MOD_MULTIPLE_INTERPRETERS_SUPPORTED`, so the extension imports and
  runs in (shared-GIL) sub-interpreters — which single-phase modules cannot.
  Type objects and the cached `datetime`/awaitable/exception objects are keyed
  per interpreter, so each interpreter gets its own (an object is never shared
  across interpreters). Verified end-to-end (`tests/test_subinterp.py`): classes,
  operators, inheritance, container conversions, `datetime` and custom exceptions
  all work in sub-interpreters, and several interpreters coexist.

### Not yet
- **Per-interpreter GIL** (`Py_MOD_PER_INTERPRETER_GIL_SUPPORTED`, true parallel
  interpreters): the per-interpreter caches are serialized by the shared GIL; the
  own-GIL mode would need them lock-protected. Shared-GIL sub-interpreters are
  fully supported.

## [0.3.0] - 2026-06-10

### Added
- **PEP 517 build backend** (`zig_maturin.buildapi`): set
  `build-backend = "zig_maturin.buildapi"` and `pip install .` / `pip wheel .` /
  `python -m build` work without invoking the CLI (Zig must be on PATH).
  Implements `build_wheel`, `build_sdist`, and `prepare_metadata_for_build_wheel`.
- **abi3 / stable ABI (opt-in)**: set `[tool.zig-maturin] abi3 = "3.12"` (or
  `zig-maturin build --abi3 3.12`, or `--config-setting abi3=3.12`) to build one
  `cp312-abi3-<platform>` wheel that
  works on that CPython and every later version. The C shim compiles against the
  Limited API; the one-shot awaitable type is built via `PyType_FromSpec` and
  datetime goes through the `datetime` module, so both stay stable-ABI. Because
  the framework already uses out-of-line refcounting and accessor functions, the
  abi3 runtime overhead is ~0 here. (Managed `__dict__` and weakref need the GC
  pre-header and are gated off under abi3; cyclic GC of fields still works.)
- **Every class is subclassable from Python**, including those with `__deinit__`
  or cyclic GC. Teardown moved to `tp_finalize` (running `__deinit__` and
  releasing PyObject fields) so CPython's `subtype_dealloc` owns the actual
  deallocation — clearing a subclass's `__dict__`/weakrefs, GC untracking, the
  correct `tp_free`, and the heaptype reference. `Py_TPFLAGS_BASETYPE` is now
  always set; `__deinit__` fires for subclass instances and cycles through them
  (via fields or the managed dict) stay collectable.
- **Suspending coroutines (`__await_delegate__`)**: a class can return a real
  Python awaitable (Future/coroutine) to delegate to, so `await obj` genuinely
  suspends to the running event loop (verified: delegated awaitables interleave
  under `asyncio.gather`, resolve via `loop.create_future()`).
- **Arbitrary attributes on GC classes (managed `__dict__`)**: a class with a
  `?*pz.PyObject` field now also carries a managed `__dict__`, so instances
  accept any Python attribute (`node.label = ...`), expose `__dict__`/`vars()`,
  and the dict's contents are GC-traced (cycles through it are collectable).
- **Writable buffer protocol** (`__buffer_mut__(self) []u8`): exposes a
  mutable zero-copy view, so `memoryview`/numpy can write into the instance
  (read-only `__buffer__` is unchanged).
- **`__init_subclass__(cls)`**: an implicit classmethod hook fired whenever a
  Python subclass is created (registry/validation patterns).
- **`__dir__`, `__sizeof__`, `__set_name__`**: customize `dir(obj)`,
  `sys.getsizeof(obj)`, and react to being bound as a class attribute.
- **Descriptor protocol** (`__get__` / `__set__` / `__delete__`): a class can be
  a managed attribute on another class (`tp_descr_get` / `tp_descr_set`); the
  assigned value in `__set__` is converted to its declared Zig type.
- **`os.PathLike` (`__fspath__`)** and **`__length_hint__`**: auto-registered
  name-lookup hooks, so instances work with `os.fspath`/`open()` and
  `operator.length_hint`.
- **Subscriptable classes for type hints**: every class gets
  `__class_getitem__`, so `MyClass[int]` returns a `types.GenericAlias`
  (`Stack[int]` in annotations).
- **Awaitable instances (`__await__`)**: `await obj` resolves to whatever
  `__await__(self)` returns, via a shipped one-shot awaitable-iterator type.
  Works with `asyncio.run`. (Ready/immediate resolution — no suspension.)
- **Async iteration (`__anext__` / `__aiter__`)**: `async for x in obj` drives
  `__anext__(self) -> ?T` (null ends iteration); works in async comprehensions.
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
- **Inheriting a built-in base** (e.g. custom `Exception` subclasses) — needs a
  non-`object` base wired through the spec.
- **weakref and `__dict__` for non-GC value classes**: both need the GC
  pre-header. A value class could only get them via an explicit
  `tp_weaklistoffset`/`tp_dictoffset` field plus a subclass-safe custom dealloc
  (a `subtype_dealloc` equivalent) — out of scope. Add a `?*pz.PyObject` field to
  make the class GC and get both. (weakref/`__dict__` work on GC classes today.)
- **Inheriting from a `pz.enumClass`** as a Zig `PyClass` base (the IntEnum is a
  standalone Python type, not a Zig-backed class).

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
