const std = @import("std");

const utils = @import("utils.zig");
const fut_rt = @import("fut_rt.zig");

const future = fut_rt;
const Result = fut_rt.Result;
const Context = fut_rt.Context;
const Executor = fut_rt.Executor;

test "test-futture-api" {
    const allocator = std.testing.allocator;

    var executor = Executor.init(allocator);
    defer executor.deinit();

    var value: u32 = 10;
    const fut = future.run(struct {
        fn poll(ctx: *Context) Result {
            const v = @as(*u32, @ptrCast(@alignCast(ctx.payload))).*;
            std.debug.print("the value = {}\n", .{v});
            return .{ .done = v };
        }
    }, &value);

    executor.schedule(fut);

    executor.run();
}
