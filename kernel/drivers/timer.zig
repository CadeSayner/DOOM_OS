const Port = @import("port.zig");
const InterruptRegisters = @import("../arch/x86/idt.zig").InterruptRegisters;
const std = @import("std");
const Context = @import("../context.zig");
const Idt = @import("../arch/x86/idt.zig");

var timer_ticks: u64 = 0;

const target_frequency = 1000;
const pit_base_frequency_hz = 1193182;
const divisor = pit_base_frequency_hz / target_frequency;
const quantum = 20; // amount of time each task gets

pub fn init() void {
    timer_ticks = 0;
    Port.outb(0x43, 0x36);
    Port.outb(0x40, divisor & 0xFF);
    Port.outb(0x40, (divisor >> 8) & 0xFF);
}

pub fn timer_handler(regs: *InterruptRegisters) void {
    _ = regs;
    timer_ticks += 1;
    const current_process = Context.ctx.scheduler.executing_process orelse return;
    current_process.ticks_remaining -= 1;
    if(current_process.ticks_remaining == 0){
        // important to let the pic know not to wait for us
        Idt.sendPicEoi(0);
        current_process.ticks_remaining = current_process.ticks_allocated;
        Context.ctx.scheduler.schedule();
    }
}

pub fn get_millis() u64 {
    return @as(*volatile u64, &timer_ticks).*;
}

pub fn get_ticks() u64 {
    return get_millis() / 50;
}
