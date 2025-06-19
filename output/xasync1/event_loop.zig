const std = @import("std");
const fut_rt = @import("fut_rt.zig");
const Waker = fut_rt.Waker;

pub const EventType = enum {
    timer,
    io,
};

pub const EventCallback = struct {
    waker: ?*const Waker = null,
    callback_fn: ?*const fn (data: ?*anyopaque) void = null,
    user_data: ?*anyopaque = null,
};

pub const EventLoop = struct {
    const Self = @This();

    epfd: std.posix.fd_t,
    allocator: std.mem.Allocator,
    events: std.ArrayList(std.posix.system.epoll_event),
    callbacks: std.HashMap(std.posix.fd_t, EventCallback, std.hash_map.AutoContext(std.posix.fd_t), std.hash_map.default_max_load_percentage),
    running: bool = false,

    pub fn init(allocator: std.mem.Allocator) !Self {
        const epfd = try std.posix.epoll_create1(0);

        return .{
            .epfd = epfd,
            .allocator = allocator,
            .events = std.ArrayList(std.posix.system.epoll_event).init(allocator),
            .callbacks = std.HashMap(std.posix.fd_t, EventCallback, std.hash_map.AutoContext(std.posix.fd_t), std.hash_map.default_max_load_percentage).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.events.deinit();
        self.callbacks.deinit();
        std.posix.close(self.epfd);
    }

    pub fn addTimer(self: *Self, timerfd: std.posix.fd_t, callback: EventCallback) !void {
        var event = std.posix.system.epoll_event{
            .events = std.posix.system.EPOLL.IN | std.posix.system.EPOLL.ET,
            .data = .{ .fd = timerfd },
        };

        try std.posix.epoll_ctl(self.epfd, std.posix.system.EPOLL.CTL_ADD, timerfd, &event);
        try self.callbacks.put(timerfd, callback);
    }

    pub fn removeTimer(self: *Self, timerfd: std.posix.fd_t) !void {
        try std.posix.epoll_ctl(self.epfd, std.posix.system.EPOLL.CTL_DEL, timerfd, null);
        _ = self.callbacks.remove(timerfd);
    }

    pub fn poll(self: *Self, timeout_ms: i32) !usize {
        try self.events.resize(16); // 预分配事件数组

        const n = std.posix.epoll_wait(self.epfd, self.events.items, timeout_ms);

        for (self.events.items[0..n]) |event| {
            const fd = event.data.fd;

            if (self.callbacks.get(fd)) |callback| {
                // 处理 timer 事件
                if (event.events & std.posix.system.EPOLL.IN != 0) {
                    // 读取 timerfd 数据
                    var buf: [8]u8 = undefined;
                    _ = std.posix.read(fd, &buf) catch {};

                    // 触发回调
                    std.debug.print("timer invoke ...\n", .{});
                    // if (callback.waker) |waker| {
                    //     std.debug.print("call waker wake\n", .{});
                    //     waker.wake();
                    // }

                    if (callback.callback_fn) |func| {
                        func(callback.user_data);
                    }
                }
            }
        }

        return n;
    }

    pub fn run(self: *Self) !void {
        self.running = true;

        while (self.running) {
            _ = try self.poll(100); // 100ms 超时
        }
    }

    pub fn stop(self: *Self) void {
        self.running = false;
    }
};

pub const TimerHandle = struct {
    const Self = @This();

    timerfd: std.posix.fd_t,
    event_loop: *EventLoop,

    pub fn init(event_loop: *EventLoop, nanoseconds: u64) !Self {
        const s = nanoseconds / std.time.ns_per_s;
        const ns = nanoseconds % std.time.ns_per_s;

        const timerfd = try std.posix.timerfd_create(std.posix.timerfd_clockid_t.MONOTONIC, .{
            .CLOEXEC = true,
            .NONBLOCK = true,
        });

        const spec: std.posix.system.itimerspec = .{
            .it_interval = .{
                .sec = 0,
                .nsec = 0,
            },
            .it_value = .{
                .sec = std.math.cast(std.os.linux.time_t, s) orelse std.math.maxInt(std.os.linux.time_t),
                .nsec = std.math.cast(std.os.linux.time_t, ns) orelse std.math.maxInt(std.os.linux.time_t),
            },
        };
        try std.posix.timerfd_settime(timerfd, .{}, &spec, null);

        return .{
            .timerfd = timerfd,
            .event_loop = event_loop,
        };
    }

    pub fn deinit(self: *Self) void {
        self.event_loop.removeTimer(self.timerfd) catch {};
        std.posix.close(self.timerfd);
    }

    pub fn setCallback(self: *Self, callback: EventCallback) !void {
        try self.event_loop.addTimer(self.timerfd, callback);
    }
};
