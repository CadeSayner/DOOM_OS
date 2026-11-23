const sys = @import("syscall.zig");

pub const File = extern struct {
    fd: c_int,
    err: c_int,
    eof: c_int,
};

var input = File{ .fd = 0, .err = 0, .eof = 0 };
var output = File{ .fd = 1, .err = 0, .eof = 0 };
pub export var stdin: *File = &input;
pub export var stdout: *File = &output;
pub export var stderr: *File = &output;
var pool: [32]File = [_]File{.{ .fd = -1, .err = 0, .eof = 0 }} ** 32;

pub export fn fopen(path: [*:0]const u8, mode: [*:0]const u8) ?*File {
    _ = mode;
    for (&pool) |*file| {
        if (file.fd < 0) {
            const fd = sys.open(path, 0);
            if (fd < 0) return null;
            file.* = .{ .fd = fd, .err = 0, .eof = 0 };
            return file;
        }
    }
    sys.errno = 24;
    return null;
}

pub export fn fclose(file: *File) c_int {
    if (file.fd < 0) return -1;
    const result = sys.close(file.fd);
    if (result == 0) file.fd = -1;
    return result;
}

pub export fn fread(ptr: [*]u8, size: usize, count: usize, file: *File) usize {
    if (size == 0 or count == 0) return 0;
    if (count > 0x7fffffff / size) {
        file.err = 1;
        return 0;
    }
    const n = sys.read(file.fd, ptr, size * count);
    if (n < 0) {
        file.err = 1;
        return 0;
    }
    const got: usize = @intCast(n);
    if (got < size * count) file.eof = 1;
    return got / size;
}

pub export fn fwrite(ptr: [*]const u8, size: usize, count: usize, file: *File) usize {
    if (size == 0 or count == 0) return 0;
    if (count > 0x7fffffff / size) {
        file.err = 1;
        return 0;
    }
    const n = sys.write(file.fd, ptr, size * count);
    if (n < 0) {
        file.err = 1;
        return 0;
    }
    return @as(usize, @intCast(n)) / size;
}

pub export fn fseek(file: *File, offset: i32, whence: c_int) c_int {
    if (sys.lseek(file.fd, offset, whence) < 0) return -1;
    file.eof = 0;
    return 0;
}

pub export fn ftell(file: *File) i32 {
    return sys.lseek(file.fd, 0, 1);
}
