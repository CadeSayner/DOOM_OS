const sys = @import("syscall.zig");

const Block = extern struct {
    size: usize,
    free: bool,
    next: ?*Block,
};

var first: ?*Block = null;
const alignment: usize = 16;
const header_size = (@sizeOf(Block) + alignment - 1) & ~(alignment - 1);

pub export fn malloc(size: usize) ?*anyopaque {
    if (size == 0 or size > 0x7fffffff - header_size - alignment) return null;
    const aligned = (size + alignment - 1) & ~(alignment - 1);
    var cursor = first;
    var last: ?*Block = null;
    while (cursor) |block| : (cursor = block.next) {
        if (block.free and block.size >= aligned) {
            block.free = false;
            return @ptrFromInt(@intFromPtr(block) + header_size);
        }
        last = block;
    }
    const current: u32 = @bitCast(sys.brk(null));
    const start = (current + alignment - 1) & ~(alignment - 1);
    const end = start + header_size + aligned;
    if (end < start or sys.brk(@ptrFromInt(end)) != 1) return null;
    const block: *Block = @ptrFromInt(start);
    block.* = .{ .size = aligned, .free = false, .next = null };
    if (last) |prev| prev.next = block else first = block;
    return @ptrFromInt(start + header_size);
}

pub export fn free(ptr: ?*anyopaque) void {
    if (ptr == null) return;
    var cursor = first;
    while (cursor) |block| : (cursor = block.next) {
        if (@intFromPtr(block) + header_size == @intFromPtr(ptr)) {
            block.free = true;
            return;
        }
    }
}
