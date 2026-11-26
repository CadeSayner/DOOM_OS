const std = @import("std");
const Port = @import("../../drivers/port.zig");
const Ps2 = @import("../../drivers/ps2.zig");
const Process = @import("../../proc/process.zig");
const Timer = @import("../../drivers/timer.zig");

const IDTEntry = packed struct(u64) {
    base_low: u16,
    sel: u16,
    always0: u8,
    flags: u8,
    base_high: u16,
};

const IDTPtr = packed struct(u48) {
    limit: u16,
    base: u32,
};

pub const SyscallFn = *const fn (*InterruptRegisters) i32;
pub const IrqFn = *const fn (*InterruptRegisters) void;

pub const InterruptRegisters = extern struct {
    cr2: u32,
    ds: u32,
    edi: u32,
    esi: u32,
    ebp: u32,
    esp: u32,
    ebx: u32,
    edx: u32,
    ecx: u32,
    eax: u32,
    int_no: u32,
    err_code: u32,
    eip: u32,
    cs: u32,
    eflags: u32,
    useresp: u32,
    ss: u32,
};

extern fn idt_flush(idt_ptr_addr: u32) callconv(.c) void;

extern fn isr0() callconv(.c) void;
extern fn isr1() callconv(.c) void;
extern fn isr2() callconv(.c) void;
extern fn isr3() callconv(.c) void;
extern fn isr4() callconv(.c) void;
extern fn isr5() callconv(.c) void;
extern fn isr6() callconv(.c) void;
extern fn isr7() callconv(.c) void;
extern fn isr8() callconv(.c) void;
extern fn isr9() callconv(.c) void;
extern fn isr10() callconv(.c) void;
extern fn isr11() callconv(.c) void;
extern fn isr12() callconv(.c) void;
extern fn isr13() callconv(.c) void;
extern fn isr14() callconv(.c) void;
extern fn isr15() callconv(.c) void;
extern fn isr16() callconv(.c) void;
extern fn isr17() callconv(.c) void;
extern fn isr18() callconv(.c) void;
extern fn isr19() callconv(.c) void;
extern fn isr20() callconv(.c) void;
extern fn isr21() callconv(.c) void;
extern fn isr22() callconv(.c) void;
extern fn isr23() callconv(.c) void;
extern fn isr24() callconv(.c) void;
extern fn isr25() callconv(.c) void;
extern fn isr26() callconv(.c) void;
extern fn isr27() callconv(.c) void;
extern fn isr28() callconv(.c) void;
extern fn isr29() callconv(.c) void;
extern fn isr30() callconv(.c) void;
extern fn isr31() callconv(.c) void;

extern fn irq0() callconv(.c) void;
extern fn irq1() callconv(.c) void;
extern fn irq2() callconv(.c) void;
extern fn irq3() callconv(.c) void;
extern fn irq4() callconv(.c) void;
extern fn irq5() callconv(.c) void;
extern fn irq6() callconv(.c) void;
extern fn irq7() callconv(.c) void;
extern fn irq8() callconv(.c) void;
extern fn irq9() callconv(.c) void;
extern fn irq10() callconv(.c) void;
extern fn irq11() callconv(.c) void;
extern fn irq12() callconv(.c) void;
extern fn irq13() callconv(.c) void;
extern fn irq14() callconv(.c) void;
extern fn irq15() callconv(.c) void;

extern fn isr128() callconv(.c) void; // Syscalls !!!
extern fn isr177() callconv(.c) void;

const MAX_SYSCALLS = 256;
const SYSCALL_ISR_NO = 128;
const ISR_MAX_ERROR_NO = 32;
const SYSCALL_ERR_NO = -38; // -ENOSYS
const ISR_MAX_NO = 31;

const Syscall = struct {
    const abi = @import("../../syscalls/abi.zig");
    const io = @import("../../syscalls/io.zig");
    const mem = @import("../../syscalls/mem.zig");
    const gfx = @import("../../syscalls/gfx.zig");
    const proc = @import("../../syscalls/proc.zig");
};

const syscall_table: [MAX_SYSCALLS]?SyscallFn = blk: {
    var table = [_]?SyscallFn{null} ** MAX_SYSCALLS;

    table[Syscall.abi.read] = &Syscall.io.read;
    table[Syscall.abi.write] = &Syscall.io.write;
    table[Syscall.abi.open] = &Syscall.io.open;
    table[Syscall.abi.close] = &Syscall.io.close;
    table[Syscall.abi.lseek] = &Syscall.io.lseek;
    table[Syscall.abi.execve] = &Syscall.proc.execve;
    table[Syscall.abi.get_proc_uptime] = &Syscall.proc.getProcUptime;
    table[Syscall.abi.sleep] = &Syscall.proc.sleep;
    table[Syscall.abi.exit] = &Syscall.proc.exit;
    table[Syscall.abi.map_fb] = &Syscall.gfx.mapFramebuffer;
    table[Syscall.abi.brk] = &Syscall.mem.brk;

    break :blk table;
};

const irq_table: [16]?IrqFn = blk: {
    var table = [_]?IrqFn{null} ** 16;
    table[0] = &Timer.timer_handler;
    table[1] = &Ps2.kbdHandler;
    break :blk table;
};

const exception_messages: [32][]const u8 = .{
    "Division By Zero",
    "Debug",
    "Non Maskable Interrupt",
    "Breakpoint",
    "Into Detected Overflow",
    "Out of Bounds",
    "Invalid Opcode",
    "No Coprocessor",
    "Double Fault",
    "Coprocessor Segment Overrun",
    "Bad TSS",
    "Segment Not Present",
    "Stack Fault",
    "General Protection Fault",
    "Page Fault",
    "Unknown Interrupt",
    "Coprocessor Fault",
    "Alignment Check",
    "Machine Check",
} ++ .{"Reserved"} ** 13;

var idt_entries: [256]IDTEntry = std.mem.zeroes([256]IDTEntry);
var idt_ptr: IDTPtr = undefined;

fn setIdtGate(num: u8, base: u32, sel: u16, flags: u8) void {
    idt_entries[num] = .{
        .base_low = @truncate(base),
        .base_high = @truncate(base >> 16),
        .sel = sel,
        .always0 = 0,
        .flags = flags | 0x60,
    };
}

pub fn init() void {
    idt_ptr.limit = @sizeOf(@TypeOf(idt_entries)) - 1;
    idt_ptr.base = @intFromPtr(&idt_entries);

    Port.outb(0x20, 0x11);
    Port.outb(0xA0, 0x11);

    Port.outb(0x21, 0x20);
    Port.outb(0xA1, 0x28);
    Port.outb(0x21, 0x04);
    Port.outb(0xA1, 0x02);
    Port.outb(0x21, 0x01);
    Port.outb(0xA1, 0x01);
    Port.outb(0x21, 0x0);
    Port.outb(0xA1, 0x0);

    setIdtGate(0, @intFromPtr(&isr0), 0x08, 0x8E);
    setIdtGate(1, @intFromPtr(&isr1), 0x08, 0x8E);
    setIdtGate(2, @intFromPtr(&isr2), 0x08, 0x8E);
    setIdtGate(3, @intFromPtr(&isr3), 0x08, 0x8E);
    setIdtGate(4, @intFromPtr(&isr4), 0x08, 0x8E);
    setIdtGate(5, @intFromPtr(&isr5), 0x08, 0x8E);
    setIdtGate(6, @intFromPtr(&isr6), 0x08, 0x8E);
    setIdtGate(7, @intFromPtr(&isr7), 0x08, 0x8E);
    setIdtGate(8, @intFromPtr(&isr8), 0x08, 0x8E);
    setIdtGate(9, @intFromPtr(&isr9), 0x08, 0x8E);
    setIdtGate(10, @intFromPtr(&isr10), 0x08, 0x8E);
    setIdtGate(11, @intFromPtr(&isr11), 0x08, 0x8E);
    setIdtGate(12, @intFromPtr(&isr12), 0x08, 0x8E);
    setIdtGate(13, @intFromPtr(&isr13), 0x08, 0x8E);
    setIdtGate(14, @intFromPtr(&isr14), 0x08, 0x8E);
    setIdtGate(15, @intFromPtr(&isr15), 0x08, 0x8E);
    setIdtGate(16, @intFromPtr(&isr16), 0x08, 0x8E);
    setIdtGate(17, @intFromPtr(&isr17), 0x08, 0x8E);
    setIdtGate(18, @intFromPtr(&isr18), 0x08, 0x8E);
    setIdtGate(19, @intFromPtr(&isr19), 0x08, 0x8E);
    setIdtGate(20, @intFromPtr(&isr20), 0x08, 0x8E);
    setIdtGate(21, @intFromPtr(&isr21), 0x08, 0x8E);
    setIdtGate(22, @intFromPtr(&isr22), 0x08, 0x8E);
    setIdtGate(23, @intFromPtr(&isr23), 0x08, 0x8E);
    setIdtGate(24, @intFromPtr(&isr24), 0x08, 0x8E);
    setIdtGate(25, @intFromPtr(&isr25), 0x08, 0x8E);
    setIdtGate(26, @intFromPtr(&isr26), 0x08, 0x8E);
    setIdtGate(27, @intFromPtr(&isr27), 0x08, 0x8E);
    setIdtGate(28, @intFromPtr(&isr28), 0x08, 0x8E);
    setIdtGate(29, @intFromPtr(&isr29), 0x08, 0x8E);
    setIdtGate(30, @intFromPtr(&isr30), 0x08, 0x8E);
    setIdtGate(31, @intFromPtr(&isr31), 0x08, 0x8E);

    // irqs start here
    setIdtGate(32, @intFromPtr(&irq0), 0x08, 0x8E);
    setIdtGate(33, @intFromPtr(&irq1), 0x08, 0x8E);
    setIdtGate(34, @intFromPtr(&irq2), 0x08, 0x8E);
    setIdtGate(35, @intFromPtr(&irq3), 0x08, 0x8E);
    setIdtGate(36, @intFromPtr(&irq4), 0x08, 0x8E);
    setIdtGate(37, @intFromPtr(&irq5), 0x08, 0x8E);
    setIdtGate(38, @intFromPtr(&irq6), 0x08, 0x8E);
    setIdtGate(39, @intFromPtr(&irq7), 0x08, 0x8E);
    setIdtGate(40, @intFromPtr(&irq8), 0x08, 0x8E);
    setIdtGate(41, @intFromPtr(&irq9), 0x08, 0x8E);
    setIdtGate(42, @intFromPtr(&irq10), 0x08, 0x8E);
    setIdtGate(43, @intFromPtr(&irq11), 0x08, 0x8E);
    setIdtGate(44, @intFromPtr(&irq12), 0x08, 0x8E);
    setIdtGate(45, @intFromPtr(&irq13), 0x08, 0x8E);
    setIdtGate(46, @intFromPtr(&irq14), 0x08, 0x8E);
    setIdtGate(47, @intFromPtr(&irq15), 0x08, 0x8E);

    setIdtGate(128, @intFromPtr(&isr128), 0x08, 0x8E);
    setIdtGate(177, @intFromPtr(&isr177), 0x08, 0x8E);

    idt_flush(@intFromPtr(&idt_ptr));
}

export fn irqHandler(regs: *InterruptRegisters) callconv(.c) void {
    const handler = irq_table[regs.int_no - 32];
    if (handler) |h| {
        h(regs);
    }
    sendPicEoi(regs.int_no - 32);
}

export fn isrHandler(regs: *InterruptRegisters) callconv(.c) i32 {
    if (regs.int_no < ISR_MAX_ERROR_NO) {
        switch (regs.int_no) {
            14 => {
                _ = Process.page_fault_handler(regs.cr2);
            },
            else => {
                @panic(exception_messages[regs.int_no]);
            },
        }
    }
    if (regs.int_no == SYSCALL_ISR_NO) {
        if (regs.eax < MAX_SYSCALLS) {
            if (syscall_table[regs.eax]) |handler| {
                return handler(regs);
            }
        }
        return SYSCALL_ERR_NO;
    }
    return @bitCast(regs.eax);
}

pub fn sendPicEoi(irq: u32) void {
    if (irq >= 8) {
        Port.outb(0xA0, 0x20);
    }
    Port.outb(0x20, 0x20);
}
