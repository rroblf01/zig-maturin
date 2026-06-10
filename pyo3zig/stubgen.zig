const std = @import("std");
const zm = @import("zig-maturin");

/// Map a Zig type to its Python type-hint spelling, at comptime.
pub fn pyType(comptime T: type) []const u8 {
    if (T == void) return "None";
    if (T == ?*zm.PyObject or T == *zm.PyObject) return "object";

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

    switch (@typeInfo(T)) {
        .bool => return "bool",
        .int => return "int",
        .float => return "float",
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

/// Concatenate `def` lines into a full stub module. `entries` is a tuple of
/// `.{ .name = "f", .func = f, .args = &.{...} }` (args optional).
pub fn moduleStub(comptime entries: anytype) []const u8 {
    comptime var out: []const u8 = "";
    inline for (entries) |e| {
        const names: []const []const u8 = if (@hasField(@TypeOf(e), "args")) e.args else &.{};
        out = out ++ funcStub(e.name, e.func, names) ++ "\n";
    }
    return out;
}
