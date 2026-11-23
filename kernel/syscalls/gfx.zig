const Abi = @import("abi.zig");
const Process = @import("../process.zig");
const InterruptRegisters = @import("../arch/x86/idt.zig").InterruptRegisters;

/// map_fb() -> virtual address of the linear framebuffer in the caller's address space.
pub fn mapFramebuffer(regs: *InterruptRegisters) i32 {
    _ = regs;
    const proc = Process.current() orelse return -Abi.ESRCH;
    const address = proc.page_directory.mapLinearFrameBuffer() catch return -Abi.ENOMEM;
    return @bitCast(address);
}
