const Port = @import("port.zig");
const InterruptRegisters = @import("../arch/x86/idt.zig").InterruptRegisters;
const std = @import("std");
const Context = @import("../context.zig");
const Idt = @import("../arch/x86/idt.zig");
const WaitList = @import("../sched/waiter.zig").TimedWaitList;


const target_frequency = 1000;
const pit_base_frequency_hz = 1193182;
const divisor = pit_base_frequency_hz / target_frequency;
const quantum = 20; // amount of time each task gets

pub const Timer = struct {
    timer_ticks: u64 = 0,
    waiters: WaitList = .{},
    pub fn init() Timer {
        Port.outb(0x43, 0x36);
        Port.outb(0x40, divisor & 0xFF);
        Port.outb(0x40, (divisor >> 8) & 0xFF);
        return Timer{
            .timer_ticks = 0,
        };
    }

    pub fn getMillis(self: *Timer) u64 {
        return @as(*volatile u64, &self.timer_ticks).*;
    }

    pub fn timer_handler(regs: *InterruptRegisters) void {
        _ = regs;
        Context.ctx.timer.timer_ticks += 1;
        const current_process = Context.ctx.scheduler.executing_process orelse return;
        current_process.ticks_remaining -= 1;
        Context.ctx.timer.waiters.tick();
        if (current_process.ticks_remaining == 0) {
            // important to let the pic know not to wait for us
            Idt.sendPicEoi(0);
            current_process.ticks_remaining = current_process.ticks_allocated;
            Context.ctx.scheduler.schedule();
        }
    }
};
