const std = @import("std");
const zm = @import("zig-maturin");

pub fn formatCharForType(comptime T: type) []const u8 {
    switch (@typeInfo(T)) {
        .int => |info| {
            if (info.signedness == .signed) {
                if (info.bits <= 8) return "b";
                if (info.bits <= 16) return "h";
                if (info.bits <= 32) return "i";
                if (info.bits <= 64) return "L";
            } else {
                if (info.bits <= 8) return "B";
                if (info.bits <= 16) return "H";
                if (info.bits <= 32) return "I";
                if (info.bits <= 64) return "K";
            }
            @compileError("Integer size not supported for Python args: " ++ @typeName(T));
        },
        .float => {
            if (T == f32) return "f";
            return "d";
        },
        .bool => return "p",
        .pointer => |info| {
            if (info.size == .slice and info.child == u8) return "s";
            return "O";
        },
        .optional => return "O",
        else => {
            @compileError("Unsupported type for Python argument: " ++ @typeName(T));
        },
    }
}

pub fn argTypeName(comptime T: type) []const u8 {
    switch (@typeInfo(T)) {
        .int => |info| {
            if (info.signedness == .signed) return "int";
            return "unsigned int";
        },
        .float => return "float",
        .bool => return "bool",
        .pointer => |info| {
            if (info.size == .slice and info.child == u8) return "str";
            return "object";
        },
        .optional => return "Optional",
        else => return "object",
    }
}
