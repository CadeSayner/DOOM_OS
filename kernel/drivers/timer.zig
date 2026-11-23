const Port = @import("port.zig");
const InterruptRegisters = @import("../arch/x86/idt.zig").InterruptRegisters;

var timer_ticks: u64 = 0;

const target_frequency = 1000;
const pit_base_frequency_hz = 1193182;
const divisor = pit_base_frequency_hz / target_frequency;

pub fn init() void {
    timer_ticks = 0;
    Port.outb(0x43, 0x36);
    Port.outb(0x40, divisor & 0xFF);
    Port.outb(0x40, (divisor >> 8) & 0xFF);
}

pub fn timer_handler(regs: *InterruptRegisters) void {
    _ = regs;
    timer_ticks += 1;
}

pub fn get_millis() u64 {
    return @as(*volatile u64, &timer_ticks).*;
}

pub fn get_ticks() u64 {
    return get_millis() / 50;
}
