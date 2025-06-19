const std = @import("std");
const fut_rt = @import("fut_rt.zig");

const Executor = fut_rt.Executor;

const STACK_SIZE = 1024 * 1024 * 10;

comptime {
    asm (@embedFile("switch.s"));
}
extern fn switch_ctx(old_ctx: *StackContext, new_ctx: *StackContext) void;

const Frame = struct {
    func_ptr: ?*const anyopaque = null,
    args_ptr: ?*const anyopaque = null,
};

fn call(coro_ptr_int: u64) void {
    std.debug.print("will execute call\n", .{});

    const coro: *Coroutine = @ptrFromInt(coro_ptr_int);
    // const coro: *Coroutine = @alignCast(@as(*Coroutine, @ptrFromInt(@as(usize, coro_ptr_int - 0x20)))); // todo: - why this is wrong

    std.debug.print("current coro address: 0x{x}\n", .{@intFromPtr(coro)});

    if (coro.frame.func_ptr != null) {
        if (coro.frame.args_ptr != null) {
            const func_ptr = @as(*const fn (*const anyopaque) void, @ptrCast(coro.frame.func_ptr.?));
            const args_ptr = coro.frame.args_ptr.?;
            func_ptr(args_ptr);
            // @call(.auto, func_ptr.*, .{args_ptr});
        } else {
            const func_ptr = @as(*const fn () void, @ptrCast(coro.frame.func_ptr.?));
            func_ptr();
            // @call(.auto, func_ptr.*, .{});
        }
    } else {
        std.debug.print("the func pointer is null\n", .{});
    }
}

const StackContext = packed struct {
    rsp: u64 = 0,
    r15: u64 = 0,
    r14: u64 = 0,
    r13: u64 = 0,
    r12: u64 = 0,
    rbx: u64 = 0,
    rbp: u64 = 0,
    coro_ptr: u64 = 0,
};

const State = enum {
    start,
    running,
    suspended,
    done,
};

const Coroutine = struct {
    const Self = @This();

    allocator: std.mem.Allocator = undefined,

    stack: []align(16) u8 = undefined,
    context: StackContext,
    state: State = .start,

    frame: Frame,

    // todo: - 编译器检查 - 参数类型
    fn init(allocator: std.mem.Allocator, func: anytype, args: anytype) !Self {
        const typeinfo = @typeInfo(@TypeOf(func));

        const stack = try allocator.alignedAlloc(u8, 16, STACK_SIZE);
        const stack_bottom = @intFromPtr(stack.ptr) + STACK_SIZE;
        const sb_aligned = stack_bottom & ~@as(usize, 15);
        const rsp = sb_aligned - 16;
        @as(*u64, @ptrFromInt(rsp)).* = @intFromPtr(&call);
        const context: StackContext = if (typeinfo == .null) .{} else .{
            .rsp = rsp,
            .coro_ptr = 0,
        };

        const frame: Frame = if (typeinfo == .null) .{} else .{
            .func_ptr = &func,
            .args_ptr = if (@typeInfo(@TypeOf(args)) == .null) null else args,
        };

        std.debug.print("the func ptr = {any}\n", .{frame.func_ptr});

        return .{
            .allocator = allocator,
            .stack = stack,
            .context = context,
            .frame = frame,
        };
    }

    fn deinit(self: *Self) void {
        if (@intFromPtr(self.stack.ptr) != 0) {
            self.allocator.free(self.stack);
        }
    }

    fn resumeFrom(self: *Self, coro: *Coroutine) void {
        switch_ctx(&coro.context, &self.context);
    }
};

fn runExecutor(arg: *anyopaque) void {
    std.debug.print("prepare to executor run\n", .{});
    const executor: *Executor = @as(*Executor, @ptrCast(@alignCast(arg)));
    // std.debug.print("the executor = {any}\n", .{executor});
    std.debug.print("executor address after cast: 0x{x}\n", .{@intFromPtr(executor)});
    executor.run();
}

pub const Runtime = struct {
    const Self = @This();

    allocator: std.mem.Allocator,

    executor: *Executor,

    base_coro: *Coroutine,
    task_coro: ?*Coroutine = null,
    executor_coro: *Coroutine,

    pub fn init(allocator: std.mem.Allocator) !Self {
        const executor = try allocator.create(Executor);
        executor.* = Executor.init(allocator);
        std.debug.print("executor size = {}\n", .{@sizeOf(Executor)});
        std.debug.print("executor address: 0x{x}\n", .{@intFromPtr(executor)});

        const base_coro = try createCoro(allocator, null, null);
        std.debug.print("base_coro address: 0x{x}\n", .{@intFromPtr(base_coro)});

        const executor_coro = try createCoro(allocator, runExecutor, executor);
        std.debug.print("executor_coro address: 0x{x}\n", .{@intFromPtr(executor_coro)});

        return .{
            .allocator = allocator,
            .executor = executor,
            .base_coro = base_coro,
            .executor_coro = executor_coro,
        };
    }

    fn createCoro(allocator: std.mem.Allocator, func: anytype, args: anytype) !*Coroutine {
        const coro: *Coroutine = try allocator.create(Coroutine);
        coro.* = try Coroutine.init(allocator, func, args);
        coro.context.coro_ptr = @intFromPtr(coro);
        return coro;
    }

    fn destroyCoro(allocator: std.mem.Allocator, coro: *Coroutine) void {
        coro.deinit();
        allocator.destroy(coro);
    }

    pub fn deinit(self: *Self) void {
        if (self.task_coro) |coro| {
            destroyCoro(self.allocator, coro);
        }
        destroyCoro(self.allocator, self.executor_coro);
        destroyCoro(self.allocator, self.base_coro);
        self.executor.deinit();
        self.allocator.destroy(self.executor);
    }

    pub fn xasync(self: *Self, func: anytype) !void {
        const task_coro = try createCoro(self.allocator, func, null);
        std.debug.print("task_coro size = {}\n", .{@sizeOf(Coroutine)});
        std.debug.print("task_coro address: 0x{x}\n", .{@intFromPtr(task_coro)});
        self.task_coro = task_coro;
        task_coro.resumeFrom(self.base_coro);
    }

    pub fn switchToExecutor(self: *Self) void {
        std.debug.print("switch to executor run\n", .{});
        std.debug.print("executor_coro address: 0x{x}\n", .{@intFromPtr(self.executor_coro)});

        self.executor_coro.resumeFrom(self.base_coro);
    }

    pub fn switchToBase(self: *Self) void {
        self.base_coro.resumeFrom(self.executor_coro);
    }

    pub fn switchTaskToBase(self: *Self) void {
        if (self.task_coro) |task_coro| {
            self.base_coro.resumeFrom(task_coro);
        }
    }

    pub fn switchToTask(self: *Self) void {
        if (self.task_coro) |task_coro| {
            std.debug.print("Switching to task coro at 0x{x}\n", .{@intFromPtr(task_coro)});
            task_coro.resumeFrom(self.executor_coro);
        }
    }

    pub fn wait(self: *Self) void {
        self.executor_coro.resumeFrom(self.base_coro);
    }

    pub fn switchTaskToExecutor(self: *Self) void {
        if (self.task_coro) |task_coro| {
            self.executor_coro.resumeFrom(task_coro);
        }
    }
};
