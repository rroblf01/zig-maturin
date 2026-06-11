const std = @import("std");
const zm = @import("zig-maturin");

/// Map a Zig type to its Python type-hint spelling, at comptime.
pub fn pyType(comptime T: type) []const u8 {
    if (T == void) return "None";
    if (T == ?*zm.PyObject or T == *zm.PyObject) return "object";
    if (T == @import("datetime.zig").DateTime) return "datetime.datetime";
    if (T == std.math.Complex(f64) or T == std.math.Complex(f32)) return "complex";

    // Wrapper types expose `borrow`; map the known ones by name.
    const tn = @typeName(T);
    if (std.mem.endsWith(u8, tn, "PyString")) return "str";
    if (std.mem.endsWith(u8, tn, "PyBytes")) return "bytes";
    if (std.mem.endsWith(u8, tn, "PyInt")) return "int";
    if (std.mem.endsWith(u8, tn, "PyFloat")) return "float";
    if (std.mem.endsWith(u8, tn, "PyBool")) return "bool";
    if (std.mem.endsWith(u8, tn, "PyList")) return "list";
    if (std.mem.endsWith(u8, tn, "PyDict")) return "dict";
    if (std.mem.endsWith(u8, tn, "PyTuple")) return "tuple";
    if (std.mem.endsWith(u8, tn, "PyFrozenSet")) return "frozenset";
    if (std.mem.endsWith(u8, tn, "PySet")) return "set";

    switch (@typeInfo(T)) {
        .bool => return "bool",
        .int => return "int",
        .float => return "float",
        .@"enum" => return "int",
        .error_union => |eu| return pyType(eu.payload),
        .optional => |o| return pyType(o.child) ++ " | None",
        .pointer => |p| {
            if (p.size == .slice) {
                if (p.child == u8) return "str";
                return "list[" ++ pyType(p.child) ++ "]";
            }
            return "object";
        },
        .array => |a| return "list[" ++ pyType(a.child) ++ "]",
        .@"struct" => |s| {
            if (s.is_tuple) {
                comptime var inner: []const u8 = "";
                inline for (s.fields, 0..) |f, i| {
                    if (i != 0) inner = inner ++ ", ";
                    inner = inner ++ pyType(f.type);
                }
                return "tuple[" ++ inner ++ "]";
            }
            return "dict";
        },
        else => return "object",
    }
}

/// Build a `.pyi` `def` line for a function. `arg_names` may be empty, in
/// which case parameters are named arg0, arg1, ... (Zig has no param names).
pub fn funcStub(
    comptime name: []const u8,
    comptime func: anytype,
    comptime arg_names: []const []const u8,
) []const u8 {
    const fn_info = @typeInfo(@TypeOf(func)).@"fn";
    comptime var sig: []const u8 = "def " ++ name ++ "(";
    inline for (fn_info.params, 0..) |param, i| {
        if (i != 0) sig = sig ++ ", ";
        const pname = if (i < arg_names.len) arg_names[i] else std.fmt.comptimePrint("arg{d}", .{i});
        sig = sig ++ pname ++ ": " ++ pyType(param.type.?);
    }
    const ret = if (fn_info.return_type) |r| pyType(r) else "None";
    return sig ++ ") -> " ++ ret ++ ": ...";
}

/// A `.pyi` `def` line for a variadic (`pz.pyFnRaw`) function: the two
/// `?*PyObject` parameters become `*args` / `**kwargs`.
pub fn rawFuncStub(comptime name: []const u8, comptime func: anytype) []const u8 {
    const fn_info = @typeInfo(@TypeOf(func)).@"fn";
    const ret = if (fn_info.return_type) |r| pyType(r) else "None";
    return "def " ++ name ++ "(*args: object, **kwargs: object) -> " ++ ret ++ ": ...";
}

/// Concatenate `def` lines into a full stub module. `entries` is a tuple of
/// `.{ .name = "f", .func = f, .args = &.{...} }` (args optional). Set
/// `.raw = true` on an entry for a variadic (`*args`/`**kwargs`) function.
pub fn moduleStub(comptime entries: anytype) []const u8 {
    comptime var out: []const u8 = "";
    inline for (entries) |e| {
        const is_raw = @hasField(@TypeOf(e), "raw") and e.raw;
        if (is_raw) {
            out = out ++ rawFuncStub(e.name, e.func) ++ "\n";
        } else {
            const names: []const []const u8 = if (@hasField(@TypeOf(e), "args")) e.args else &.{};
            out = out ++ funcStub(e.name, e.func, names) ++ "\n";
        }
    }
    return out;
}

/// A `.pyi` `class` line for a custom exception type (`pz.exceptionClass`):
/// `class Name(Base): ...`. `base` is the Python base spelling, e.g.
/// "ValueError" or "Exception".
pub fn exceptionStub(comptime name: []const u8, comptime base: []const u8) []const u8 {
    return "class " ++ name ++ "(" ++ base ++ "): ...\n\n";
}

/// A `.pyi` method line: like `funcStub` but indented and with an implicit
/// `self` (the first Zig parameter is skipped). `arg_names` names the remaining
/// parameters, matching `wrapMethodNamed` / `wrapMethodKw`.
pub fn methodStub(
    comptime name: []const u8,
    comptime func: anytype,
    comptime arg_names: []const []const u8,
) []const u8 {
    const fn_info = @typeInfo(@TypeOf(func)).@"fn";
    const params = fn_info.params[1..];
    comptime var sig: []const u8 = "    def " ++ name ++ "(self";
    inline for (params, 0..) |param, i| {
        const pname = if (i < arg_names.len) arg_names[i] else std.fmt.comptimePrint("arg{d}", .{i});
        sig = sig ++ ", " ++ pname ++ ": " ++ pyType(param.type.?);
    }
    const ret = if (fn_info.return_type) |r| pyType(r) else "None";
    return sig ++ ") -> " ++ ret ++ ": ...\n";
}

/// A `.pyi` `class` block for a Zig class struct. `spec` is
/// `.{ .name = "Vec2", .type = Vec2, .init = &.{"x","y"},
///     .methods = .{ .{ .name = "dot", .func = dot, .args = &.{...} }, ... },
///     .properties = .{ .{ .name = "length_sq", .get = fn }, ... } }`.
/// `.init`, `.methods` and `.properties` are optional. Struct fields become
/// annotated class attributes; properties become `@property` accessors typed
/// from the getter's return type.
pub fn classStub(comptime spec: anytype) []const u8 {
    const T = spec.type;
    const fields = std.meta.fields(T);
    const has_init = @hasField(@TypeOf(spec), "init");
    const has_methods = @hasField(@TypeOf(spec), "methods");
    const has_properties = @hasField(@TypeOf(spec), "properties");
    // `.base = "Animal"` emits `class Name(Base):` for an inheriting class.
    const base_suffix = if (@hasField(@TypeOf(spec), "base")) "(" ++ spec.base ++ ")" else "";

    comptime var out: []const u8 = "class " ++ spec.name ++ base_suffix ++ ":\n";
    comptime var has_body = false;

    // When inheriting (`.base`), the first field is the embedded base struct;
    // its attributes are inherited, so skip it here.
    const field_skip = if (@hasField(@TypeOf(spec), "base")) 1 else 0;
    inline for (fields, 0..) |f, i| {
        if (i >= field_skip) {
            out = out ++ "    " ++ f.name ++ ": " ++ pyType(f.type) ++ "\n";
            has_body = true;
        }
    }

    if (has_properties) {
        inline for (spec.properties) |prop| {
            const gi = @typeInfo(@TypeOf(prop.get)).@"fn";
            const ret = if (gi.return_type) |r| pyType(r) else "object";
            out = out ++ "    @property\n    def " ++ prop.name ++ "(self) -> " ++ ret ++ ": ...\n";
            if (@hasField(@TypeOf(prop), "set")) {
                out = out ++ "    @" ++ prop.name ++ ".setter\n    def " ++
                    prop.name ++ "(self, value: " ++ ret ++ ") -> None: ...\n";
            }
            has_body = true;
        }
    }

    if (has_init) {
        const init_info = @typeInfo(@TypeOf(T.init)).@"fn";
        comptime var sig: []const u8 = "    def __init__(self";
        inline for (init_info.params, 0..) |param, i| {
            const pname = if (i < spec.init.len) spec.init[i] else std.fmt.comptimePrint("arg{d}", .{i});
            sig = sig ++ ", " ++ pname ++ ": " ++ pyType(param.type.?);
        }
        out = out ++ sig ++ ") -> None: ...\n";
        has_body = true;
    }

    if (has_methods) {
        inline for (spec.methods) |meth| {
            const names: []const []const u8 = if (@hasField(@TypeOf(meth), "args")) meth.args else &.{};
            out = out ++ methodStub(meth.name, meth.func, names);
            has_body = true;
        }
    }

    // Auto-emit dunder methods declared on the struct whose signatures map
    // cleanly to Python types (scalars/str/bool). Operators returning Self are
    // skipped — the stub generator can't spell the class type for them yet.
    const dunders = .{
        .{ "__str__", &[_][]const u8{} },
        .{ "__repr__", &[_][]const u8{} },
        .{ "__hash__", &[_][]const u8{} },
        .{ "__eq__", &[_][]const u8{"other"} },
        .{ "__lt__", &[_][]const u8{"other"} },
        .{ "__le__", &[_][]const u8{"other"} },
        .{ "__gt__", &[_][]const u8{"other"} },
        .{ "__ge__", &[_][]const u8{"other"} },
        .{ "__len__", &[_][]const u8{} },
        .{ "__getitem__", &[_][]const u8{"key"} },
        .{ "__contains__", &[_][]const u8{"item"} },
        .{ "__call__", &[_][]const u8{} },
        .{ "__int__", &[_][]const u8{} },
        .{ "__float__", &[_][]const u8{} },
        .{ "__index__", &[_][]const u8{} },
        .{ "__bool__", &[_][]const u8{} },
        .{ "__format__", &[_][]const u8{"format_spec"} },
        .{ "__reversed__", &[_][]const u8{} },
        .{ "__delitem__", &[_][]const u8{"key"} },
        .{ "__bytes__", &[_][]const u8{} },
        .{ "__floor__", &[_][]const u8{} },
        .{ "__ceil__", &[_][]const u8{} },
        .{ "__trunc__", &[_][]const u8{} },
        .{ "__round__", &[_][]const u8{} },
        .{ "__divmod__", &[_][]const u8{"other"} },
        .{ "__getstate__", &[_][]const u8{} },
        .{ "__setstate__", &[_][]const u8{"state"} },
        .{ "__fspath__", &[_][]const u8{} },
        .{ "__length_hint__", &[_][]const u8{} },
        .{ "__dir__", &[_][]const u8{} },
        .{ "__sizeof__", &[_][]const u8{} },
        .{ "__set_name__", &[_][]const u8{ "owner", "name" } },
    };
    inline for (dunders) |d| {
        if (@hasDecl(T, d[0])) {
            out = out ++ methodStub(d[0], @field(T, d[0]), d[1]);
            has_body = true;
        }
    }

    if (!has_body) out = out ++ "    pass\n";
    return out ++ "\n";
}
