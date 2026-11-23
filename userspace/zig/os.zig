//! zig interfaces to the DOOM_OS user space abi...
const std = @import("std");

extern fn malloc(size: usize) ?*anyopaque;
extern fn free(ptr: ?*anyopaque) void;
extern fn write(fd: c_int, buffer: [*]const u8, count: usize) isize;

pub const allocator: std.mem.Allocator = .{
    .ptr = undefined,
    .vtable = &.{
        .alloc = alloc,
        .resize = resize,
        .remap = std.mem.Allocator.noRemap,
        .free = dealloc,
    },
};

fn alloc(_: *anyopaque, len: usize, alignment: std.mem.Alignment, _: usize) ?[*]u8 {
    const align_bytes = @max(alignment.toByteUnits(), @alignOf(usize));
    const extra = std.math.add(usize, align_bytes - 1, @sizeOf(usize)) catch return null;
    const total = std.math.add(usize, len, extra) catch return null;
    const raw = malloc(total) orelse return null;
    const start = std.math.add(usize, @intFromPtr(raw), @sizeOf(usize)) catch {
        free(raw);
        return null;
    };
    const end = std.math.add(usize, start, align_bytes - 1) catch {
        free(raw);
        return null;
    };
    const aligned = end & ~(align_bytes - 1);
    const header: *usize = @ptrFromInt(aligned - @sizeOf(usize));
    header.* = @intFromPtr(raw);
    return @ptrFromInt(aligned);
}

fn resize(_: *anyopaque, memory: []u8, _: std.mem.Alignment, new_len: usize, _: usize) bool {
    return new_len <= memory.len;
}

fn dealloc(_: *anyopaque, memory: []u8, _: std.mem.Alignment, _: usize) void {
    const header: *const usize = @ptrFromInt(@intFromPtr(memory.ptr) - @sizeOf(usize));
    free(@ptrFromInt(header.*));
}

pub fn writeAll(fd: c_int, bytes: []const u8) error{WriteFailed}!void {
    var written: usize = 0;
    while (written < bytes.len) {
        const n = write(fd, bytes.ptr + written, bytes.len - written);
        if (n <= 0) return error.WriteFailed;
        written += @intCast(n);
    }
}
