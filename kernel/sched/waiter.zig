const std = @import("std");
const Process = @import("../proc/process.zig").Process;
const Queue = @import("../lib/queue.zig").Queue;

const max_waiters = 64;

extern fn irq_save() u32;
extern fn irq_restore(flags: u32) void;

pub const Waiter = struct {
    waiting_process: *Process,
    ticks_remaining: ?u64,

    // The waiter is invalid after this is called and should not be used again
    pub fn wake(self: *Waiter) void {
        if (self.waiting_process.status != .Terminated) {
            self.waiting_process.status = .Ready;
        }
        self.waiting_process.removeWaiterRef();
    }

    pub fn init(proc: *Process, ticks: ?u64) Waiter {
        proc.addWaiterRef();
        return .{ .waiting_process = proc, .ticks_remaining = ticks };
    }
};

pub const TimedWaitList = struct {
    entries: [max_waiters]?Waiter = [_]?Waiter{null} ** max_waiters,
    pub fn add(self: *TimedWaitList, proc: *Process, ticks: u64) !void {
        const flags = irq_save();
        for (&self.entries) |*slot| {
            if (slot.* == null) {
                slot.* = Waiter.init(proc, ticks);
                irq_restore(flags);
                return;
            }
        }
        irq_restore(flags);
        return error.WaitListFull;
    }

    pub fn tick(self: *TimedWaitList) void {
        for(&self.entries) |*slot| {
            if(slot.*) |*waiter| {
                if(waiter.ticks_remaining orelse continue > 0){
                    waiter.ticks_remaining.? -= 1;
                }else{
                    waiter.wake();
                    slot.* = null; // free the space in the list back up for another waiter, invalidating the wake pointer as is required
                }
            }
        }
    }
};

pub const WaitQueue = struct {
    waiters: Queue(max_waiters, Waiter) = .{},
    pub fn addWaiter(self: *WaitQueue, process: *Process) !void {
        const flags = irq_save();
        try self.waiters.enqueue(Waiter.init(process, null));
        irq_restore(flags);
    }

    pub fn wakeAll(self: *WaitQueue) void {
        while (self.waiters.len > 0) {
            self.wakeOne();
        }
    }

    pub fn wakeOne(self: *WaitQueue) void {
        const waiter = self.waiters.dequeue() orelse return;
        waiter.wake();
    }
};
