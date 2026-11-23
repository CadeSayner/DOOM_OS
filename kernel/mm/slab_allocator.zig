//! Slab allocator for small objects. Implements `std.mem.Allocator`.
//!
//! Sizes 8..512 bytes (powers of two) are served from per-size caches.
//! Each cache owns one-frame slabs. A slab is laid out as:
//!
//!   [ Slab header | padding | obj | obj | obj | ... ]
//!
//! Free objects form an intrusive linked list (each free object stores
//! a pointer to the next free one), so alloc and free are O(1) within a slab.
//! Anything larger than 512 bytes goes straight to the frame allocator.

const std = @import("std");
const FrameAllocator = @import("frame_allocator.zig").FrameAllocator;
const constants = @import("../lib/constants.zig");

const min_class_size: usize = 8;
const max_class_size: usize = 512;
const class_count = 7; // 8, 16, 32, 64, 128, 256, 512

const FreeNode = struct {
    next: ?*FreeNode,
};

comptime {
    // A free object must be able to hold a FreeNode.
    std.debug.assert(@sizeOf(FreeNode) <= min_class_size);
}

const Slab = struct {
    next: ?*Slab,
    free_list: ?*FreeNode,
    in_use: usize,

    /// Offset of the first object. Rounded up to the object size (a power
    /// of two) so that every object is naturally aligned, because the
    /// frame itself is frame-aligned.
    fn objectsStart(obj_size: usize) usize {
        return std.mem.alignForward(usize, @sizeOf(Slab), obj_size);
    }

    /// Initialise a slab in place inside the frame at `frame_addr`.
    /// Only the header and free-list links are written, no big temporaries
    /// on the stack.
    fn init(frame_addr: usize, obj_size: usize) *Slab {
        const slab: *Slab = @ptrFromInt(frame_addr);
        slab.* = .{ .next = null, .free_list = null, .in_use = 0 };

        const start = objectsStart(obj_size);
        const count = (constants.frame_size - start) / obj_size;

        // Thread in reverse so the first allocation is the lowest address.
        var i = count;
        while (i > 0) {
            i -= 1;
            const node: *FreeNode = @ptrFromInt(frame_addr + start + i * obj_size);
            node.next = slab.free_list;
            slab.free_list = node;
        }
        return slab;
    }
};

const Cache = struct {
    obj_size: usize,
    slabs: ?*Slab = null,

    fn init(obj_size: usize) Cache {
        return .{ .obj_size = obj_size };
    }

    fn allocate(self: *Cache, frame_allocator: *FrameAllocator) ?[*]u8 {
        // Find a slab with a free object.
        var current = self.slabs;
        while (current) |slab| : (current = slab.next) {
            if (slab.free_list) |node| return take(slab, node);
        }

        // All slabs full (or none yet): get a fresh frame.
        const frame_addr = frame_allocator.allocateFrame();
        const slab = Slab.init(frame_addr, self.obj_size);
        slab.next = self.slabs;
        self.slabs = slab;
        return take(slab, slab.free_list.?);
    }

    fn take(slab: *Slab, node: *FreeNode) [*]u8 {
        slab.free_list = node.next;
        slab.in_use += 1;
        return @ptrCast(node);
    }

    fn deallocate(self: *Cache, ptr: [*]u8) void {
        const addr = @intFromPtr(ptr);

        // Slabs are frame-aligned, so rounding down finds the header.
        const slab_addr = std.mem.alignBackward(usize, addr, constants.frame_size);
        const slab: *Slab = @ptrFromInt(slab_addr);

        const start = Slab.objectsStart(self.obj_size);
        const offset = addr - slab_addr;
        if (offset < start or (offset - start) % self.obj_size != 0) {
            @panic("slab: freed pointer is not a valid object for this cache");
        }

        const node: *FreeNode = @ptrCast(@alignCast(ptr));
        node.next = slab.free_list;
        slab.free_list = node;
        slab.in_use -= 1;
    }
};

pub const SlabAllocator = struct {
    frame_allocator: *FrameAllocator,
    caches: [class_count]Cache,

    pub fn init(frame_allocator: *FrameAllocator) SlabAllocator {
        var caches: [class_count]Cache = undefined;
        for (&caches, 0..) |*cache, i| {
            cache.* = Cache.init(min_class_size << @intCast(i));
        }
        return .{
            .frame_allocator = frame_allocator,
            .caches = caches,
        };
    }

    pub fn allocator(self: *SlabAllocator) std.mem.Allocator {
        return .{ .ptr = self, .vtable = &vtable };
    }

    const vtable: std.mem.Allocator.VTable = .{
        .alloc = alloc,
        .resize = resize,
        .remap = remap,
        .free = free,
    };

    /// Which cache serves this request, or null if it is too big for the
    /// slabs. Must give identical answers in `alloc` and `free`.
    fn classIndex(len: usize, alignment: std.mem.Alignment) ?usize {
        const size = @max(len, alignment.toByteUnits(), min_class_size);
        if (size > max_class_size) return null;
        return @as(usize, std.math.log2_int_ceil(usize, size)) - 3; // 8 -> 0, 16 -> 1, ...
    }

    fn alloc(ctx: *anyopaque, len: usize, alignment: std.mem.Alignment, _: usize) ?[*]u8 {
        const self: *SlabAllocator = @ptrCast(@alignCast(ctx));
        if (classIndex(len, alignment)) |i| return self.caches[i].allocate(self.frame_allocator);

        // Large allocation: frames are frame-aligned, so that is the
        // strongest alignment we can promise.
        if (alignment.toByteUnits() > constants.frame_size) return null;
        
        // Calculate required pages based on length and frame size
        const num_pages: u16 = @intCast((len + constants.frame_size - 1) / constants.frame_size);
        if (num_pages <= 1) {
            return @ptrCast(@as(*u8, @ptrFromInt(self.frame_allocator.allocateFrame())));
        } else {
            return @ptrCast(@as(*u8, @ptrFromInt(self.frame_allocator.allocateConsecutiveFrames(num_pages))));
        }
    }

    fn free(ctx: *anyopaque, memory: []u8, alignment: std.mem.Alignment, _: usize) void {
        const self: *SlabAllocator = @ptrCast(@alignCast(ctx));
        if (classIndex(memory.len, alignment)) |i| {
            self.caches[i].deallocate(memory.ptr);
        } else {
            const num_pages: u16 = @intCast((memory.len + constants.frame_size - 1) / constants.frame_size);
            if (num_pages <= 1) {
                self.frame_allocator.freeVaddrFrame(@intFromPtr(memory.ptr));
            } else {
                self.frame_allocator.freeVaddrFrames(@intFromPtr(memory.ptr), num_pages);
            }
        }
    }

    fn resize(_: *anyopaque, memory: []u8, alignment: std.mem.Alignment, new_len: usize, _: usize) bool {
        const old = classIndex(memory.len, alignment);
        const new = classIndex(new_len, alignment);
        if (old == null and new == null) return new_len <= memory.len;
        return old == new;
    }

    fn remap(_: *anyopaque, _: []u8, _: std.mem.Alignment, _: usize, _: usize) ?[*]u8 {
        return null; // std falls back to alloc + copy + free
    }
};