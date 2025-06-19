const std = @import("std");

pub fn dynStackToHeapPtr(allocator: std.mem.Allocator, comptime T: type, value: T) *T {
    const x = allocator.create(T) catch unreachable;
    x.* = value;
    return x;
}
