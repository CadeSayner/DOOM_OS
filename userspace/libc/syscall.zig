pub export var errno: c_int = 0;

pub export fn syscall(number: u32, arg1: u32, arg2: u32, arg3: u32) i32 {
    return asm volatile ("int $0x80"
        : [result] "={eax}" (-> i32),
        : [number] "{eax}" (number),
          [arg1] "{ebx}" (arg1),
          [arg2] "{ecx}" (arg2),
          [arg3] "{edx}" (arg3),
        : .{ .memory = true, .cc = true });
}

fn checked(result: i32) i32 {
    if (result < 0) {
        errno = -result;
        return -1;
    }
    return result;
}

pub export fn open(path: [*:0]const u8, flags: c_int, ...) c_int {
    return checked(syscall(2, @intFromPtr(path), @bitCast(flags), 0));
}

pub export fn read(fd: c_int, buf: [*]u8, count: usize) isize {
    return checked(syscall(0, @bitCast(fd), @intFromPtr(buf), count));
}

pub export fn write(fd: c_int, buf: [*]const u8, count: usize) isize {
    return checked(syscall(1, @bitCast(fd), @intFromPtr(buf), count));
}

pub export fn close(fd: c_int) c_int {
    return checked(syscall(3, @bitCast(fd), 0, 0));
}

pub export fn lseek(fd: c_int, offset: i32, whence: c_int) i32 {
    return checked(syscall(8, @bitCast(fd), @bitCast(offset), @bitCast(whence)));
}

pub export fn execve(path: [*:0]const u8, argv: ?[*:null]const ?[*:0]const u8, envp: ?[*:null]const ?[*:0]const u8) c_int {
    return checked(syscall(11, @intFromPtr(path), @intFromPtr(argv), @intFromPtr(envp)));
}

pub export fn brk(addr: ?*anyopaque) i32 {
    return syscall(45, @intFromPtr(addr), 0, 0);
}

pub export fn map_linear_framebuffer() ?*anyopaque {
    const result = syscall(42, 0, 0, 0);
    if (result >= -4095 and result < 0) {
        errno = -result;
        return null;
    }
    return @ptrFromInt(@as(u32, @bitCast(result)));
}

pub export fn sys_get_proc_uptime() u32 {
    return @bitCast(syscall(12, 0, 0, 0));
}

pub export fn sleep(ms: u32) void {
    _ = syscall(13, ms, 0, 0);
}

pub export fn exit(code: c_int) noreturn {
    _ = syscall(40, @bitCast(code), 0, 0);
    while (true) asm volatile ("pause");
}
