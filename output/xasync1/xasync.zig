const std = @import("std");
const fut_rt = @import("fut_rt.zig");
const fiber_rt = @import("fiber_rt.zig");

const future = fut_rt;
const Result = fut_rt.Result;
const Context = fut_rt.Context;
const Waker = fut_rt.Waker;
const Executor = fut_rt.Executor;

const Runtime = fiber_rt.Runtime;

const EventLoop = @import("event_loop.zig").EventLoop;
const EventCallback = @import("event_loop.zig").EventCallback;
const TimerHandle = @import("event_loop.zig").TimerHandle;

const Timer = struct {
    const Self = @This();

    handle: TimerHandle,
    completed: bool = false,
    waker: ?*const Waker = null,

    fn init(nanoseconds: u64) !Self {
        const handle = try TimerHandle.init(
            &global_event_loop,
            nanoseconds,
        );
        std.debug.print("Timer registered with event loop\n", .{});

        return .{
            .handle = handle,
        };
    }

    fn deinit(self: *Self) void {
        self.handle.deinit();
    }

    fn timerCompletedCallback(data: ?*anyopaque) void {
        if (data) |ptr| {
            const timer: *Timer = @ptrCast(@alignCast(ptr));
            timer.completed = true;
            std.debug.print("Timer completed!\n", .{});

            // 如果有等待的waker，唤醒它
            if (timer.waker) |waker| {
                waker.wake();
            }
        }
    }

    fn poll(ctx: *Context) Result {
        const timer: *Timer = @ptrCast(@alignCast(ctx.payload));
        std.debug.print("poll timer is completed = {}\n", .{timer.completed});
        if (timer.completed) {
            // timer.deinit();
            ctx.allocator.destroy(timer);
            return .{ .done = null };
        } else {
            timer.waker = ctx.waker;
        }
        return .wait;
    }
};

fn sleep(nanoseconds: u64) void {
    std.debug.print("sleep comes in \n", .{});
    if (!sys_is_block) {
        std.debug.print("prepare to create timer\n", .{});

        const timer_ptr = global_runtime.allocator.create(Timer) catch unreachable;
        timer_ptr.* = Timer.init(nanoseconds) catch unreachable;

        // 设置回调函数来标记完成状态
        const callback = EventCallback{
            .waker = null, // 这里先设为null，在poll中会设置实际的waker
            .callback_fn = Timer.timerCompletedCallback,
            .user_data = timer_ptr,
        };
        timer_ptr.handle.setCallback(callback) catch unreachable;

        const timer_fut = future.runWithAllocator(global_runtime.allocator, Timer.poll, timer_ptr); // todo: - need change allocator

        std.debug.print("before schedule \n", .{});

        std.debug.print("Future size: {}, address: 0x{x}\n", .{
            @sizeOf(future.Future),
            @intFromPtr(&timer_fut),
        });
        global_runtime.executor.schedule(timer_fut);
        std.debug.print("after schedule\n", .{});

        global_runtime.switchTaskToBase(); // suspend

        // global_runtime.switchToExecutor(); // suspend -> switch to executor coroutine
    } else {
        std.Thread.sleep(nanoseconds);
    }
}

fn delay() void {
    std.debug.print("delay comes in...\n", .{});
    sleep(5 * std.time.ns_per_s);
    std.debug.print("delay finish \n", .{});
}

var sys_is_block = false;

var global_event_loop: EventLoop = undefined;
var event_loop_thread: ?std.Thread = null;
var global_runtime: Runtime = undefined;

var should_stop: bool = false;

var runtime_mutex: std.Thread.Mutex = .{};

fn eventLoopThread() void {
    std.debug.print("eventloop start at thread = {}\n", .{std.Thread.getCurrentId()});

    while (!should_stop) {
        _ = global_event_loop.poll(100) catch |err| {
            std.debug.print("事件循环轮询错误: {}\n", .{err});
        };

        runtime_mutex.lock();
        if (global_runtime.executor.hasWork()) {
            global_runtime.switchToExecutor();
        }
        runtime_mutex.unlock();

        std.time.sleep(1 * std.time.ns_per_ms);
    }

    std.debug.print("event loop quit\n", .{});
}

pub fn getRuntime() *Runtime {
    return &global_runtime;
}

fn initRuntime(allocator: std.mem.Allocator) !void {
    global_event_loop = try EventLoop.init(allocator);
    global_runtime = try Runtime.init(allocator);
    event_loop_thread = try std.Thread.spawn(.{}, eventLoopThread, .{});
}

fn deinitRuntime() void {
    // 设置停止标志
    should_stop = true;

    // 等待事件循环线程结束
    if (event_loop_thread) |thread| {
        thread.join();
    }

    // 清理资源
    global_runtime.deinit();
    global_event_loop.deinit();
}

fn xasync(func: anytype) void {
    // _ = try std.Thread.spawn(.{}, run, .{&self}); // todo: - 参考这种 api 机制实现 xasync
    runtime_mutex.lock();
    defer runtime_mutex.unlock();
    global_runtime.xasync(func) catch unreachable;
}

fn xawait() void {
    var task_completed = false;

    const checkTaskStatus = struct {
        fn check() bool {
            runtime_mutex.lock();
            defer runtime_mutex.unlock();
            return global_runtime.executor.allFinish();
        }
    }.check;

    while (!task_completed) {
        std.time.sleep(10 * std.time.ns_per_ms);
        task_completed = checkTaskStatus();
    }
}

pub fn main() !void {
    std.debug.print("main thread = {}\n", .{std.Thread.getCurrentId()});

    var debug_allocator = std.heap.DebugAllocator(.{}){};
    defer _ = debug_allocator.deinit();
    const allocator = debug_allocator.allocator();
    try initRuntime(allocator);
    defer deinitRuntime();

    {
        xasync(delay);
        // xawait();
        std.debug.print("hello world-------------------->\n", .{});
    }

    std.debug.print("main continue run...\n", .{});

    std.time.sleep(10 * std.time.ns_per_s);

    std.debug.print("main will quit\n", .{});
}

test "fn-type" {
    const delay_fn = delay;
    const delay_fn_ptr = &delay_fn;
    std.debug.print("the delay func type = {}, func ptr = 0x{x}\n", .{ @TypeOf(delay_fn), @intFromPtr(delay_fn_ptr) });
}
