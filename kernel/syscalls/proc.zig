const std = @import("std");
const Abi = @import("abi.zig");
const Process = @import("../process.zig");
const Timer = @import("../drivers/timer.zig");
const InterruptRegisters = @import("../arch/x86/idt.zig").InterruptRegisters;

const max_path_len = 256;

/// exit(code: ebx): terminates the calling process, does not return.
pub fn exit(regs: *InterruptRegisters) i32 {
    const proc = Process.current() orelse return -Abi.ESRCH;
    proc.exit(regs.ebx);
}

/// execve(path: ebx) -> -errno on failure. On success the caller is replaced and this does not return.
pub fn execve(regs: *InterruptRegisters) i32 {
    const proc = Process.current() orelse return -Abi.ESRCH;
    var path = proc.userString(regs.ebx, max_path_len) orelse return -Abi.EFAULT;
    while (std.mem.startsWith(u8, path, "./")) path = path[2..];
    while (std.mem.startsWith(u8, path, "/")) path = path[1..];

    const new_proc = Process.elf32_parse_file(path) catch |err| return Abi.errnoOf(err);
    proc.status = .Terminated;
    proc.release();
    new_proc.start();
    return 0;
}

/// get_proc_uptime() -> milliseconds since the process started.
pub fn getProcUptime(regs: *InterruptRegisters) i32 {
    _ = regs;
    const proc = Process.current() orelse return -Abi.ESRCH;
    return @bitCast(@as(u32, @truncate(Timer.get_ticks() -% proc.start_time_ms)));
}

/// sleep(ms: ebx): waits with interrupts enabled so the timer keeps ticking.
pub fn sleep(regs: *InterruptRegisters) i32 {
    const start = Timer.get_ticks();
    const ms: u64 = regs.ebx;
    while (Timer.get_ticks() - start < ms) {
        asm volatile ("sti; nop; hlt; cli" ::: .{ .memory = true });
    }
    return 0;
}
