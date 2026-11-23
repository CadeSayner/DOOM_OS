const std = @import("std");

const FrameAllocator = @import("mm/frame_allocator.zig").FrameAllocator;
const Vfs = @import("fs/vfs/vfs.zig").Vfs;
const LinearFrameBuffer = @import("drivers/vga.zig").LinearFrameBuffer;

pub const KernelContext = struct {
    allocator: std.mem.Allocator,
    frame_allocator: FrameAllocator,
    vfs: *Vfs,
};

pub var ctx: KernelContext = undefined;
