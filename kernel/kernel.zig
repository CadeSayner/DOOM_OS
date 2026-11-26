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
const Process = @import("proc/process.zig");
const KernelContext = @import("context.zig");
const Timer = @import("drivers/timer.zig");
const BuildOptions = @import("build_options");
const Scheduler = @import("proc/scheduler.zig").Scheduler;
const Ps2 = @import("drivers/ps2.zig");

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
    KernelContext.ctx.scheduler = .{};

    run(initrd_module) catch |err| @panic(@errorName(err));

    while (true) {}
}

fn initKernelVfs(allocator: std.mem.Allocator) !*Vfs {
    KernelContext.ctx.vfs = try Vfs.init(allocator);
    const vfs = &KernelContext.ctx.vfs;
    return vfs;
}

fn initTtyDevices(allocator: std.mem.Allocator, vfs: *Vfs) !void {
    std.log.info("Initialising devices...", .{});

    const tty0_inode = try vfs.createInode(Inode.Kind.device, 0, &.{});
    const tty1_inode = try vfs.createInode(Inode.Kind.device, 0, &.{});

    const tty0 = try allocator.create(Tty);
    const tty1 = try allocator.create(Tty);

    tty0.* = Tty.init(tty0_inode);
    tty1.* = Tty.init(tty1_inode);

    tty0_inode.device = Device{ .tty = tty0 };
    tty1_inode.device = Device{ .tty = tty1 };

    std.log.info("TTY devices initialised", .{});

    Ps2.subscribe(&Tty.ttyKeyListener) catch |err| std.log.err("Could not subscribe tty listener: {s}", .{@errorName(err)});

    _ = try vfs.addInode("tty0", tty0_inode);
    _ = try vfs.addInode("tty1", tty1_inode);

    std.log.info("TTY devices added to VFS", .{});
}

fn mountFilesystems(initrd: *Grub.Module, vfs: *Vfs) !void {
    try TarFs.mountTarFs(initrd, vfs);
    std.log.info("TarFs mounted", .{});

    vfs.ls();
}

fn startInitialProcess() !void {
    std.log.info("Starting {s}", .{BuildOptions.program});
    const process = Process.elf32_parse_file(BuildOptions.program) catch |err| {
        std.log.err("Cannot start {s}: {s}", .{ BuildOptions.program, @errorName(err) });
        return err;
    };

    // we have the process handle now add it to the scheduler and lets ball!
    try KernelContext.ctx.scheduler.addProcess(process);
    Scheduler.setBootProcessStack();
    try KernelContext.ctx.scheduler.schedule();
}

fn run(initrd: *Grub.Module) !void {
    const allocator = KernelContext.ctx.allocator;
    const vfs = try initKernelVfs(allocator);
    try initTtyDevices(allocator, vfs);
    try mountFilesystems(initrd, vfs);
    try startInitialProcess();
}
