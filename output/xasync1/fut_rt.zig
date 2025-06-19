const std = @import("std");
const utils = @import("utils.zig");
const xasync = @import("xasync.zig");

var fut_allocator: ?std.mem.Allocator = null;

fn futAllocator() std.mem.Allocator {
    std.debug.assert(fut_allocator != null);
    return fut_allocator.?;
}

fn setFutAllocator(allocator: ?std.mem.Allocator) void {
    if (fut_allocator == null and allocator != null) {
        fut_allocator = allocator;
    }
}

pub fn runWithAllocator(allocator: ?std.mem.Allocator, run_fn: RunFn, payload: ?*anyopaque) *Future {
    return runFutureAllArgs(allocator, run_fn, payload);
}

pub fn run(run_fn: RunFn, payload: ?*anyopaque) *Future {
    return runFutureAllArgs(null, run_fn, payload);
}

pub fn runFutureAllArgs(
    allocator: ?std.mem.Allocator,
    run_fn: RunFn,
    payload: ?*anyopaque,
) *Future {
    setFutAllocator(allocator);

    const run_fut = Future{ .run = Run{
        .run_fn = run_fn,
        .payload = payload,
    } };

    return utils.dynStackToHeapPtr(futAllocator(), Future, run_fut);
}

pub fn done(value: ?*anyopaque) *Future {
    std.debug.assert(fut_allocator != null);

    const done_fut = Future{ .done = Done{ .value = value } };

    return utils.dynStackToHeapPtr(futAllocator(), Future, done_fut);
}

fn chain_fut(fut: *Future, then_fn: ThenFn) *Future {
    std.debug.assert(fut_allocator != null);

    // todo: - payload need chain ?
    // todo: - make it append to executor tree node

    const then_fut = Future{ .then = Then{
        .left_fut = fut,
        .then_fn = then_fn,
    } };

    return utils.dynStackToHeapPtr(futAllocator(), Future, then_fut);
}

pub const Result = union(enum) {
    wait,
    done: ?*anyopaque,
};

pub const Context = struct {
    allocator: std.mem.Allocator,
    waker: *const Waker,
    payload: ?*anyopaque = null,
};

pub const Future = union(enum) {
    const Self = @This();

    run: Run,
    then: Then,
    done: Done,

    pub fn poll(self: *Self, ctx: *Context) Result {
        switch (self.*) {
            inline else => |*case| {
                return case.poll(ctx);
            },
        }
    }

    pub fn destory(self: *Self) void {
        switch (self.*) {
            inline else => |*case| {
                case.destroy();
                futAllocator().destroy(self);
            },
        }
    }

    pub fn data(self: *Self) ?*anyopaque {
        switch (self.*) {
            inline else => |*case| {
                return case.data();
            },
        }
    }

    pub fn chain(self: *Self, then_fn: ThenFn) *Self {
        return chain_fut(self, then_fn);
    }
};

// use this for future chain gen done future
// different from future.run custom wait or done flow
pub const Done = struct {
    const Self = @This();

    value: ?*anyopaque,

    fn poll(self: *Self, _: *Context) Result {
        return .{ .done = self.value };
    }

    fn destroy(_: *Self) void {}

    fn data(self: *Self) ?*anyopaque {
        return self.value;
    }
};

const RunFn = *const fn (ctx: *Context) Result;

pub const Run = struct {
    const Self = @This();

    run_fn: RunFn,
    payload: ?*anyopaque = null,

    fn poll(self: *Self, ctx: *Context) Result {
        return self.run_fn(ctx);
    }

    fn destroy(_: *Self) void {}

    fn data(self: *Self) ?*anyopaque {
        return self.payload;
    }
};

const ThenFn = *const fn (result: ?*anyopaque, ctx: *Context) *Future;

pub const Then = struct {
    const Self = @This();

    left_fut: ?*Future = null, // todo: - consider all future use pointer
    right_fut: ?*Future = null,
    then_fn: ThenFn,

    pub fn poll(self: *Self, ctx: *Context) Result {
        if (self.left_fut) |left| {
            const result = left.poll(ctx);
            if (result == Result.done) {
                const then_fut = self.then_fn(result.done, ctx);
                self.right_fut = then_fut;
                self.destroy_left();
                return .wait;
            }
            return result;
        } else {
            std.debug.assert(self.right_fut != null); // must not null
            return self.right_fut.?.poll(ctx);
        }
    }

    fn destroy(self: *Self) void {
        self.destroy_left();
        self.destroy_right();
    }

    fn destroy_left(self: *Self) void {
        if (self.left_fut) |left| {
            left.destory();
        }
        self.left_fut = null;
    }

    fn destroy_right(self: *Self) void {
        if (self.right_fut) |right| {
            right.destory();
        }
        self.right_fut = null;
    }

    fn data(self: *Self) ?*anyopaque {
        if (self.left_fut) |fut| {
            return fut.data();
        } else {
            std.debug.assert(self.right_fut != null);
            return self.right_fut.?.data();
        }
    }
};

// todo: - add join future
const Join = struct {};
// todo: - add catch
const Catch = struct {};

pub const Waker = struct {
    executor: *Executor,
    fut: *Future,

    pub fn wake(self: *const Waker) void {
        const thread_id = std.Thread.getCurrentId();
        std.debug.print("the thread id = {}\n", .{thread_id});

        // self.executor.schedule(self.fut);

        if (self.executor.futs.items.len > 0) {
            xasync.getRuntime().switchToExecutor();
        }
    }
};

pub const Executor = struct {
    const Self = @This();

    allocator: std.mem.Allocator,

    // todo: - change future to task
    // todo: - change to task hashmap or treenode
    // todo: - optimize the data structure
    futs: std.ArrayList(*Future),
    ready_queue: std.ArrayList(*Future),

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
            .futs = std.ArrayList(*Future).init(allocator),
            .ready_queue = std.ArrayList(*Future).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        for (self.futs.items) |fut_ptr| {
            self.allocator.destroy(fut_ptr);
        }

        self.futs.clearAndFree();
        self.futs.deinit();

        self.ready_queue.clearAndFree();
        self.ready_queue.deinit();
    }

    pub fn hasWork(self: *Self) bool {
        return self.ready_queue.items.len > 0;
    }

    pub fn allFinish(self: *Self) bool {
        return self.ready_queue.items.len == 0 and self.futs.items.len == 0;
    }

    // 拷贝到堆上进行自己管理，所有权转移
    pub fn schedule(self: *Self, fut: *Future) void {
        std.debug.print("begin schedule\n", .{});

        self.ready_queue.append(fut) catch |err| {
            std.debug.print("err = {}\n", .{err});
            @panic("append future to ready queue failed");
        };

        std.debug.print("ready queue count = {}\n", .{self.ready_queue.items.len});
    }

    pub fn run(self: *Self) void {
        std.debug.print("------------- the executor run loop ------------\n", .{});

        while (self.futs.items.len > 0 or self.ready_queue.items.len > 0) { // todo: - make it no longer loop forever
            std.debug.print("will begin process ready queue\n", .{});

            // 处理就绪队列中的新任务
            while (self.ready_queue.items.len > 0) {
                const fut = self.ready_queue.swapRemove(0);
                self.futs.append(fut) catch unreachable;
            }

            // std.debug.print("i = {} len = {}\n", .{ i, self.futs.items.len });
            std.debug.print("will begin process ready queue 1\n", .{});

            var i: usize = 0;
            var all_waiting = true;

            std.debug.print("will begin process ready queue 2\n", .{});
            std.debug.print("i = {} - fut items len = {}\n", .{ i, self.futs.items.len });
            while (i < self.futs.items.len) {
                const fut = self.futs.items[i];
                const payload = fut.data(); // todo: - change to fetchPayload

                const waker = Waker{
                    .executor = self,
                    .fut = fut,
                }; // todo: - wake.wake re schedule the future task

                // todo: - this need change
                var ctx = Context{
                    .allocator = self.allocator,
                    .waker = &waker,
                    .payload = payload,
                };

                const result = fut.poll(&ctx);

                // const fut_type = @tagName(fut.*);
                // std.debug.print("future type = {s}, res = {any}\n", .{ fut_type, res });

                if (result == .done) {
                    const removed_fut = self.futs.swapRemove(i); // 移除队列 - need remove done future
                    // _ = removed_fut;
                    // todo: - if need resume, resume back
                    removed_fut.destory(); // todo: - double free problem
                    std.debug.print("fut done\n", .{});
                    all_waiting = false;
                    // 切换到对应的 taskCoro
                    // xasync.getRuntime().switchToTask();
                } else {
                    i += 1;
                }
            }
            // std.debug.print("all waiting ...\n", .{});

            // 如果所有future都在等待且没有新的就绪任务，则挂起
            if (all_waiting and self.ready_queue.items.len == 0 and self.futs.items.len > 0) {
                std.debug.print("all futures waiting, switching to base...\n", .{});
                xasync.getRuntime().switchToBase(); // todo: - make it not excepton when no runtime
            }

            // 在循环的最后检查是否应该退出
            // if (self.futs.items.len == 0 and self.ready_queue.items.len == 0) {
            //     break; // 退出循环
            // }
        }

        // 执行完毕，切换回 taskCoro
        std.debug.print("Executor finished, switching to base...\n", .{});
        xasync.getRuntime().switchToBase();
    }
};

const Counter = struct {
    const Self = @This();
    num: u32,
    max: u32,

    fn init(num: u32, max: u32) Self {
        return .{
            .num = num,
            .max = max,
        };
    }

    fn doCount(ctx: *Context) Result {
        const counter = @as(*Counter, @ptrCast(@alignCast(ctx.payload)));
        // std.debug.print("begin count num = {}\n", .{counter.num});
        if (counter.num < counter.max) {
            std.debug.print("counter num = {}\n", .{counter.num});
            counter.num += 1;
            return .wait;
        } else {
            return .{ .done = &counter.num };
        }
    }

    fn doNextCount(result: ?*anyopaque, ctx: *Context) *Future {
        var counter = @as(*Counter, @ptrCast(@alignCast(ctx.payload)));

        const num = @as(*u32, @ptrCast(@alignCast(result)));
        const value = num.*;

        counter.num = 0;
        counter.max = value + 5;

        return run(Counter.doCount, counter);
    }

    fn doNewCounterCount(result: ?*anyopaque, ctx: *Context) *Future {
        const num = @as(*u32, @ptrCast(@alignCast(result)));
        const value = num.*;

        const new_counter = utils.dynStackToHeapPtr(ctx.allocator, Counter, Counter.init(0, value + 5));

        return run(Counter.doCount, new_counter);
    }

    fn changeNumAndMax(result: ?*anyopaque, ctx: *Context) *Future {
        var counter = @as(*Counter, @ptrCast(@alignCast(ctx.payload)));

        const num = @as(*u32, @ptrCast(@alignCast(result)));
        const value = num.*;

        counter.num = value + 5;
        counter.max = value + 10;

        return run(Counter.doCount, counter);
    }

    fn destroyNewCounter(_: ?*anyopaque, ctx: *Context) *Future {
        const new_counter = @as(*Counter, @ptrCast(@alignCast(ctx.payload)));
        ctx.allocator.destroy(new_counter);
        return done(null);
    }

    fn printNum(result: ?*anyopaque, _: *Context) *Future {
        const num = @as(*u32, @ptrCast(@alignCast(result)));
        std.debug.print("counter has finished num = {}\n", .{num.*});
        return done(null);
    }
};

test "simple-future" {
    const allocator = std.testing.allocator;

    var executor = Executor.init(allocator);
    defer executor.deinit();

    var value: u32 = 0;
    const fut = runWithAllocator(allocator, struct {
        fn count(ctx: *Context) Result {
            const num = @as(*u32, @ptrCast(@alignCast(ctx.payload)));
            if (num.* < 10) {
                std.debug.print("the value = {}\n", .{num.*});
                num.* += 1;
                return .wait;
            } else {
                return .{ .done = num };
            }
        }
    }.count, &value);

    executor.schedule(fut);
    executor.run();
}

test "simple-future-chain" {
    const allocator = std.testing.allocator;

    var executor = Executor.init(allocator);
    defer executor.deinit();

    var value: u32 = 0;
    const fut = runWithAllocator(allocator, struct {
        fn count(ctx: *Context) Result {
            const num = @as(*u32, @ptrCast(@alignCast(ctx.payload)));
            if (num.* < 10) {
                std.debug.print("the value = {}\n", .{num.*});
                num.* += 1;
                return .wait;
            } else {
                return .{ .done = num };
            }
        }
    }.count, &value).chain(struct {
        fn showValue(result: ?*anyopaque, _: *Context) *Future {
            const value_ptr = @as(*u32, @ptrCast(@alignCast(result)));
            std.debug.print("the result = {}\n", .{value_ptr.*});
            return done(null);
        }
    }.showValue);

    executor.schedule(fut);
    executor.run();
}

test "done-chain-many-times" {
    const allocator = std.testing.allocator;

    var executor = Executor.init(allocator);
    defer executor.deinit();

    setFutAllocator(allocator); // this place must set munual

    const num = utils.dynStackToHeapPtr(allocator, u32, 10);
    defer allocator.destroy(num);

    const fut = done(num).chain(struct {
        fn thenFn(result: ?*anyopaque, _: *Context) *Future {
            std.debug.print("value1 = {}\n", .{@as(*u32, @ptrCast(@alignCast(result))).*});
            const new_value = utils.dynStackToHeapPtr(allocator, u32, 20);
            return done(new_value);
        }
    }.thenFn).chain(struct {
        fn thenFn(result: ?*anyopaque, ctx: *Context) *Future {
            const ctx_allocator = ctx.allocator;

            const old_value = @as(*u32, @ptrCast(@alignCast(result)));
            std.debug.print("value2 = {}\n", .{old_value.*});
            ctx_allocator.destroy(old_value);

            const new_value = utils.dynStackToHeapPtr(allocator, u32, 30);
            return done(new_value);
        }
    }.thenFn).chain(struct {
        fn thenFn(result: ?*anyopaque, ctx: *Context) *Future {
            const ctx_allocator = ctx.allocator;

            const old_value = @as(*u32, @ptrCast(@alignCast(result)));
            std.debug.print("value3 = {}\n", .{old_value.*});
            ctx_allocator.destroy(old_value);

            const new_value = utils.dynStackToHeapPtr(allocator, u32, 40);
            return done(new_value);
        }
    }.thenFn).chain(struct {
        fn thenFn(result: ?*anyopaque, ctx: *Context) *Future {
            const ctx_allocator = ctx.allocator;

            const old_value = @as(*u32, @ptrCast(@alignCast(result)));
            std.debug.print("value4 = {}\n", .{old_value.*});
            ctx_allocator.destroy(old_value);

            return done(null);
        }
    }.thenFn);

    executor.schedule(fut);
    executor.run();
}

test "counter-chain-done" {
    const allocator = std.testing.allocator;

    var executor = Executor.init(allocator);
    defer executor.deinit();

    var counter = Counter.init(0, 5);
    const fut = runWithAllocator(allocator, Counter.doCount, &counter).chain(Counter.printNum);

    executor.schedule(fut);

    executor.run();
}

test "counter-chain-counter" {
    const allocator = std.testing.allocator;

    var executor = Executor.init(allocator);
    defer executor.deinit();

    var counter = Counter.init(0, 5);
    const fut = runWithAllocator(allocator, Counter.doCount, &counter).chain(Counter.doNextCount);

    executor.schedule(fut);

    executor.run();
}

test "count-chain-new-counter-destroy" {
    const allocator = std.testing.allocator;

    var executor = Executor.init(allocator);
    defer executor.deinit();

    var counter = Counter.init(0, 5);
    const fut = runWithAllocator(allocator, Counter.doCount, &counter).chain(Counter.doNewCounterCount).chain(Counter.destroyNewCounter);

    executor.schedule(fut);

    executor.run();
}

test "counter-chain-change-num-max" {
    const allocator = std.testing.allocator;

    var executor = Executor.init(allocator);
    defer executor.deinit();

    var counter = Counter.init(0, 5);
    const fut = runWithAllocator(allocator, Counter.doCount, &counter).chain(Counter.changeNumAndMax);

    executor.schedule(fut);

    executor.run();
}

test "schedule-two-counter-future" {
    const allocator = std.testing.allocator;

    var executor = Executor.init(allocator);
    defer executor.deinit();

    var counter = Counter.init(0, 5);

    // const counter = utils.dynStackToHeapPtr(allocator, Counter, Counter.init(0, 5));
    // defer allocator.destroy(counter);

    // todo: - payload use anytype to make payload use const compile error

    const fut = runWithAllocator(allocator, Counter.doCount, &counter).chain(Counter.changeNumAndMax);
    executor.schedule(fut);

    var new_counter = Counter.init(20, 30);
    const new_fut = run(Counter.doCount, &new_counter);
    executor.schedule(new_fut);

    executor.run();
}
