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
const CharacterDevice = @import("fs/vfs/character_device.zig").CharacterDevice;
const TarFs = @import("fs/tarfs/tarfs.zig");
const Process = @import("proc/process.zig");
const Context = @import("context.zig");
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

    Context.ctx.frame_allocator = FrameAllocator.init(initial_frame);
    Context.ctx.slab_allocator = SlabAllocator.init(&Context.ctx.frame_allocator);
    Context.ctx.allocator = Context.ctx.slab_allocator.allocator();
    Context.ctx.scheduler = .{};

    run(initrd_module) catch |err| @panic(@errorName(err));

    while (true) {}
}

fn initKernelVfs(allocator: std.mem.Allocator) !*Vfs {
    Context.ctx.vfs = try Vfs.init(allocator);
    const vfs = &Context.ctx.vfs;
    return vfs;
}

fn initDevices(allocator: std.mem.Allocator, vfs: *Vfs) !void {
    std.log.info("Initialising devices...", .{});

    const kb_input_device_inode = try vfs.createInode(Inode.Kind.device, 0, &.{});
    const kb_input_character_device = try allocator.create(CharacterDevice(Ps2.KeyEvent));
    kb_input_character_device.* = CharacterDevice(Ps2.KeyEvent).init(kb_input_device_inode);
    kb_input_device_inode.device = Device{ .ps2_event_char = kb_input_character_device };
    _ = try vfs.addInode("dev/input", kb_input_device_inode);
    try Ps2.subscribe(kb_input_character_device);

    std.log.info("Devices added to VFS", .{});
}

fn mountFilesystem(initrd: *Grub.Module, vfs: *Vfs) !void {
    try TarFs.mountTarFs(initrd, vfs);
    std.log.info("TarFs mounted", .{});
    vfs.ls();
}

fn startInitialProcess() !void {
    const doom_process = Process.elf32_parse_file("doom.elf", Context.ctx.allocator) catch |err| {
        std.log.err("Cannot start {s}: {s}", .{ BuildOptions.program, @errorName(err) });
        return err;
    };
    const hello_process = Process.elf32_parse_file("hello.elf", Context.ctx.allocator) catch |err| {
        std.log.err("Cannot start {s}: {s}", .{ BuildOptions.program, @errorName(err) });
        return err;
    };
    try Context.ctx.scheduler.addProcess(doom_process);
    try Context.ctx.scheduler.addProcess(hello_process);
    Scheduler.initialiseBootProcess();
    Context.ctx.scheduler.schedule();
}

fn run(initrd: *Grub.Module) !void {
    const allocator = Context.ctx.allocator;
    const vfs = try initKernelVfs(allocator);
    try initDevices(allocator, vfs);
    try mountFilesystem(initrd, vfs);
    try startInitialProcess();
    idleLoop();
}

pub fn idleLoop() callconv(.c) noreturn {
    while (true) {
        asm volatile ("cli" ::: .{ .memory = true });

        if (Context.ctx.scheduler.run_queue.len != 0) {
            Context.ctx.scheduler.schedule();
        } else {
            asm volatile ("sti; hlt" ::: .{ .memory = true });
        }
    }
}
