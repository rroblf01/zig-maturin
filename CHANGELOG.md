# Changelog

All notable changes to this project are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/); this project adheres to
[Semantic Versioning](https://semver.org/).

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
  `__contains__`, `__iter__`, `__next__` (self-iterators).
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
