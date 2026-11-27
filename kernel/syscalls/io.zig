const std = @import("std");
const Abi = @import("abi.zig");
const Process = @import("../proc/process.zig");
const Context = @import("../context.zig");
const File = @import("../fs/vfs/vfs.zig").File;
const InterruptRegisters = @import("../arch/x86/idt.zig").InterruptRegisters;

const max_path_len = 256;
const max_transfer = std.math.maxInt(i32);

pub const OpenFlags = struct {
    pub const accmode: u32 = 0x0003;
    pub const rdonly: u32 = 0x0000;
    pub const wronly: u32 = 0x0001;
    pub const rdwr: u32 = 0x0002;

    pub const creat: u32 = 0x0040;
    pub const excl: u32 = 0x0080;
    pub const noctty: u32 = 0x0100;
    pub const trunc: u32 = 0x0200;
    pub const append: u32 = 0x0400;
    pub const nonblock: u32 = 0x0800;
    pub const cloexec: u32 = 0x80000;

    pub inline fn has(flags: u32, flag: u32) bool {
        return (flags & flag) != 0;
    }

    pub inline fn accessMode(flags: u32) u32 {
        return flags & accmode;
    }
};

/// read(fd: ebx, buf: ecx, count: edx) -> bytes read | -errno
pub fn read(regs: *InterruptRegisters) i32 {
    const proc = Context.ctx.scheduler.executing_process orelse return -Abi.ESRCH;
    const file = proc.getFile(regs.ebx) orelse return -Abi.EBADF;
    const count = @min(regs.edx, max_transfer);
    if (count == 0) return 0;
    const buffer = proc.userBuffer(regs.ecx, count) orelse return -Abi.EFAULT;
    const n = file.read(buffer) catch |err| return Abi.errnoOf(err);
    return @intCast(n);
}

/// write(fd: ebx, buf: ecx, count: edx) -> bytes written | -errno
pub fn write(regs: *InterruptRegisters) i32 {
    if (regs.eax == 1) {
        // hack to see stdout
        const count = @min(regs.edx, max_transfer);
        if (count == 0) return 0;
        const ptr: [*]const u8 = @ptrFromInt(regs.ecx);
        const buffer = ptr[0..count];
        std.log.info("{s}", .{buffer });
        return @intCast(count);
    }
    const proc = Context.ctx.scheduler.executing_process orelse return -Abi.ESRCH;
    const file = proc.getFile(regs.ebx) orelse return -Abi.EBADF;
    const count = @min(regs.edx, max_transfer);
    if (count == 0) return 0;
    const buffer = proc.userBuffer(regs.ecx, count) orelse return -Abi.EFAULT;
    const n = file.write(buffer) catch |err| return Abi.errnoOf(err);
    return @intCast(n);
}

/// open(path: ebx) -> fd | -errno. Flags/mode are ignored, because I dont care really
pub fn open(regs: *InterruptRegisters) i32 {
    const proc = Context.ctx.scheduler.executing_process orelse return -Abi.ESRCH;
    var path = proc.userString(regs.ebx, max_path_len) orelse return -Abi.EFAULT;

    while (std.mem.startsWith(u8, path, "./")) path = path[2..];
    while (std.mem.startsWith(u8, path, "/")) path = path[1..];

    const flags: u32 = regs.ecx;
    const allocator = Context.ctx.allocator;

    const file = Context.ctx.vfs.open(path, flags, allocator) catch |err| return Abi.errnoOf(err);
    const fd = proc.addFile(file) orelse {
        file.close(allocator) catch {};
        return -Abi.EMFILE;
    };
    return @intCast(fd);
}

/// close(fd: ebx) -> 0 | -errno
pub fn close(regs: *InterruptRegisters) i32 {
    const proc = Context.ctx.scheduler.executing_process orelse return -Abi.ESRCH;
    proc.closeFile(regs.ebx) catch |err| return Abi.errnoOf(err);
    return 0;
}

/// lseek(fd: ebx, offset: ecx, whence: edx) -> new position | -errno
pub fn lseek(regs: *InterruptRegisters) i32 {
    const proc = Context.ctx.scheduler.executing_process orelse return -Abi.ESRCH;
    const file = proc.getFile(regs.ebx) orelse return -Abi.EBADF;
    const whence: File.Whence = switch (regs.edx) {
        0 => .set,
        1 => .cur,
        2 => .end,
        else => return -Abi.EINVAL,
    };
    const position = file.seek(@bitCast(regs.ecx), whence) catch |err| return Abi.errnoOf(err);
    return @intCast(position);
}
