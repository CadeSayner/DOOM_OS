const Abi = @import("abi.zig");
const Process = @import("../proc/process.zig");
const InterruptRegisters = @import("../arch/x86/idt.zig").InterruptRegisters;

/// brk(addr: ebx) -> current break when addr is 0, 1 on success, -ENOMEM on failure.
/// The heap pages are mapped lazily by the page fault handler.
pub fn brk(regs: *InterruptRegisters) i32 {
    const proc = Process.current() orelse return -Abi.ESRCH;
    if (regs.ebx == 0) return @bitCast(proc.brk);
    return if (proc.setBrk(regs.ebx)) 1 else -Abi.ENOMEM;
}
