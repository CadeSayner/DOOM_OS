const std = @import("std");

const FrameAllocator = @import("mm/frame_allocator.zig").FrameAllocator;
const SlabAllocator = @import("mm/slab_allocator.zig").SlabAllocator;
const Vfs = @import("fs/vfs/vfs.zig").Vfs;
const LinearFrameBuffer = @import("drivers/vga.zig").LinearFrameBuffer;
const Scheduler = @import("proc/scheduler.zig").Scheduler;

pub const KernelContext = struct {
    allocator: std.mem.Allocator = undefined,
    frame_allocator: FrameAllocator = undefined,
    slab_allocator: SlabAllocator = undefined,
    vfs: Vfs = undefined,
    scheduler: Scheduler = undefined,
};

// Initialize fields in place: the slab allocator and allocator point into ctx.
pub var ctx: KernelContext = .{};
