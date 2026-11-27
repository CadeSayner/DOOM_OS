const std = @import("std");

pub const KeyEvent = extern struct {
    scan_code: u8 = 0,
    ascii: u8 = 0,
    pressed: u8 = 0,
    shift: u8 = 0,
    extended: u8 = 0,
};

extern fn write(fd: c_int, buf: [*]const u8, len: usize) isize;
extern fn open(path: [*:0]const u8, flags: c_int, ...) c_int;
extern fn read(fd: c_int, buf: *anyopaque, len: usize) isize;
extern fn close(fd: c_int) c_int;

fn writeStr(msg: []const u8) void {
    _ = write(1, msg.ptr, msg.len);
}

export fn main() c_int {
    writeStr("Going to try reading in blocking mode...\n");

    const fd = open("/dev/input", 0);
    if (fd < 0) {
        writeStr("Failed to open /dev/input\n");
        return 1;
    }
    defer _ = close(fd);

    var events: [1]KeyEvent = .{.{}};
    const n = read(fd, &events, @sizeOf(@TypeOf(events)));
    if (n <= 0) {
        writeStr("Read returned error or EOF\n");
        return 1;
    }

    writeStr("Woken up with a key press\n");
    return 0;
}
