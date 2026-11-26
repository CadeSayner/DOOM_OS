const std = @import("std");
const Abi = @import("abi.zig");
const Process = @import("../proc/process.zig");
const Context = @import("../context.zig");
const File = @import("../fs/vfs/vfs.zig").File;
const InterruptRegisters = @import("../arch/x86/idt.zig").InterruptRegisters;

const max_path_len = 256;
const max_transfer = std.math.maxInt(i32);

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
    const allocator = Context.ctx.allocator;

    const file = Context.ctx.vfs.open(path, allocator) catch |err| return Abi.errnoOf(err);
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
