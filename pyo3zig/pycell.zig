const std = @import("std");
const zm = @import("zig-maturin");

pub fn PyCell(comptime T: type) type {
    return struct {
        const Self = @This();

        pub const ObjectLayout = extern struct {
            header: zm.PyObjectHeader,
            data: T,
        };

        pub fn objFromPtr(ptr: *T) ?*zm.PyObject {
            const layout: *ObjectLayout = @fieldParentPtr("data", ptr);
            return @as(?*zm.PyObject, @ptrCast(layout));
        }

        pub fn ptrFromObj(obj: ?*zm.PyObject) *T {
            const layout = @as(*ObjectLayout, @ptrCast(@alignCast(obj)));
            return &layout.data;
        }

        pub fn allocSize() usize {
            return @sizeOf(ObjectLayout);
        }
    };
}
