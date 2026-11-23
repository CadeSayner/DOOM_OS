const std = @import("std");

const FrameAllocator = @import("mm/frame_allocator.zig").FrameAllocator;
const SlabAllocator = @import("mm/slab_allocator.zig").SlabAllocator;
const Vfs = @import("fs/vfs/vfs.zig").Vfs;
const LinearFrameBuffer = @import("drivers/vga.zig").LinearFrameBuffer;

pub const KernelContext = struct {
    allocator: std.mem.Allocator,
    frame_allocator: FrameAllocator,
    slab_allocator: SlabAllocator,
    vfs: Vfs,
};

// Initialize fields in place: the slab allocator and allocator point into ctx.
pub var ctx: KernelContext = undefined;
