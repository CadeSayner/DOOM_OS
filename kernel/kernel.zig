const std = @import("std");
const Serial = @import("drivers/serial.zig");
const Vga = @import("drivers/vga.zig");
const Gdt = @import("arch/x86/gdt.zig");
const Idt = @import("arch/x86/idt.zig");
const Constants = @import("lib/constants.zig");
const Grub = @import("lib/grub.zig");
const FrameAllocator = @import("mm/frame_allocator.zig").FrameAllocator;
const SlabAllocator = @import("mm/slab_allocator.zig").SlabAllocator;
const Vfs = @import("fs/vfs/vfs.zig").Vfs;
const Inode = @import("fs/vfs/vfs.zig").Inode;
const Device = @import("fs/vfs/vfs.zig").Device;
const Tty = @import("fs/vfs/tty.zig").Tty;
const TarFs = @import("fs/tarfs/tarfs.zig");
const Process = @import("process.zig");
const KernelContext = @import("context.zig");
const Timer = @import("drivers/timer.zig");
const BuildOptions = @import("build_options");

pub const std_options: std.Options = .{
    .log_level = .debug,
    .logFn = Serial.kernelLogFn,
};

export fn kmain(magic: u32, multiboot_info: *Grub.MultibootInfo) callconv(.c) void {
    // Kernel entry point
    _ = magic;

    Serial.init();
    std.log.info("Serial initialized", .{});

    Gdt.init();
    std.log.info("GDT initialized", .{});

    Idt.init();
    std.log.info("IDT initialized", .{});

    Timer.init();
    std.log.info("Timer initialized", .{});

    Vga.init(multiboot_info);
    std.log.info("VGA Driver initialized", .{});

    std.log.info("Initializing memory", .{});

    var memory_start: usize = 0;

    if (multiboot_info.mods_count != 1) {
        @panic("Invalid number of modules loaded by GRUB, cannot boot OS");
    }

    const virt_mods_addr = Constants.physToVirt(multiboot_info.mods_addr);
    const modules_ptr: [*]Grub.Module = @ptrFromInt(virt_mods_addr);
    const initrd_module = &modules_ptr[0];

    const virt_module_end = Constants.physToVirt(initrd_module.module_end);
    memory_start = std.mem.alignForward(usize, virt_module_end, Constants.frame_size);
    std.log.info("Memory start from module end: {x}", .{memory_start});

    std.log.info("Final memory start for allocator: {x}", .{memory_start});

    const initial_frame: u32 = @intCast((memory_start - Constants.kernel_offset) / Constants.frame_size);

    std.log.info("Initial frame: {d}", .{initial_frame});

    KernelContext.ctx.frame_allocator = FrameAllocator.init(initial_frame);
    KernelContext.ctx.slab_allocator = SlabAllocator.init(&KernelContext.ctx.frame_allocator);
    KernelContext.ctx.allocator = KernelContext.ctx.slab_allocator.allocator();

    run(initrd_module) catch |err| @panic(@errorName(err));

    while (true) {}
}

fn run(initrd: *Grub.Module) !void {
    const allocator = KernelContext.ctx.allocator;
    KernelContext.ctx.vfs = try Vfs.init(allocator);
    const vfs = &KernelContext.ctx.vfs;
    std.log.info("VFS initialized", .{});

    const tty0 = try allocator.create(Tty);
    const tty1 = try allocator.create(Tty);
    tty0.* = .{};
    tty1.* = .{ .serial_output = true };

    _ = try vfs.addEntry("tty0", Inode.Kind.character_device, &.{}, Device{ .tty = tty0 });
    _ = try vfs.addEntry("tty1", Inode.Kind.character_device, &.{}, Device{ .tty = tty1 });

    std.log.info("TTY devices added to VFS", .{});
    try TarFs.mountTarFs(initrd, vfs);
    std.log.info("TarFs mounted", .{});

    vfs.ls();

    std.log.info("Starting {s}", .{BuildOptions.program});
    const process = Process.elf32_parse_file(BuildOptions.program) catch |err| {
        std.log.err("Cannot start {s}: {s}", .{ BuildOptions.program, @errorName(err) });
        return err;
    };
    process.start();
}
