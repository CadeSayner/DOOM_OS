const Abi = @import("abi.zig");
const InterruptRegisters = @import("../arch/x86/idt.zig").InterruptRegisters;
const Context = @import("../context.zig");
/// map_fb() -> virtual address of the linear framebuffer in the caller's address space.
pub fn mapFramebuffer(regs: *InterruptRegisters) i32 {
    _ = regs;
    const proc = Context.ctx.scheduler.?.executing_process orelse return -Abi.ESRCH;
    const address = proc.page_directory.mapLinearFrameBuffer() catch return -Abi.ENOMEM;
    return @bitCast(address);
}
