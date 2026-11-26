const std = @import("std");
const Abi = @import("abi.zig");
const Process = @import("../proc/process.zig");
const Timer = @import("../drivers/timer.zig");
const InterruptRegisters = @import("../arch/x86/idt.zig").InterruptRegisters;
const Context = @import("../context.zig");

const max_path_len = 256;

/// exit(code: ebx): terminates the calling process, does not return.
pub fn exit(regs: *InterruptRegisters) i32 {
    const proc = Context.ctx.scheduler.executing_process orelse return -Abi.ESRCH;
    _ = proc;
    _ = regs;

    // TODO:
    // needs to kill the process by removing it from the scheduler queue and
    //  freeing the processes memory and all the structures it contains
    return 0;
}

/// execve(path: ebx) -> -errno on failure. On success the caller is replaced and this does not return.
pub fn execve(regs: *InterruptRegisters) i32 {
    const proc = Context.ctx.scheduler.executing_process orelse return -Abi.ESRCH;
    var path = proc.userString(regs.ebx, max_path_len) orelse return -Abi.EFAULT;
    while (std.mem.startsWith(u8, path, "./")) path = path[2..];
    while (std.mem.startsWith(u8, path, "/")) path = path[1..];

    const new_proc = Process.elf32_parse_file(path, Context.ctx.allocator) catch |err| return Abi.errnoOf(err);

    Context.ctx.scheduler.addProcess(new_proc) catch |err| return Abi.errnoOf(err);

    return 0;
}

/// get_proc_uptime() -> elapsed 50 ms ticks, as expected by the bundled Doom port.
pub fn getProcUptime(regs: *InterruptRegisters) i32 {
    _ = regs;
    const proc = Context.ctx.scheduler.executing_process orelse return -Abi.ESRCH;
    return @bitCast(@as(u32, @truncate(Timer.get_ticks() -% proc.start_time_ms)));
}

/// sleep(ms: ebx): waits with interrupts enabled so the timer keeps ticking.
pub fn sleep(regs: *InterruptRegisters) i32 {

    // TODOOO this needs to change to actually block it and add it to the timers queue and will be woken at some later stage
    const start = Timer.get_millis();
    const ms: u64 = regs.ebx;
    while (Timer.get_millis() -% start < ms) {
        asm volatile ("sti; nop; hlt; cli" ::: .{ .memory = true });
    }
    return 0;
}
