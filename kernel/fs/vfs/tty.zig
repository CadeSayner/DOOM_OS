const std = @import("std");
const File = @import("vfs.zig").File;
const Inode = @import("vfs.zig").Inode;
const Serial = @import("../../drivers/serial.zig");
const Ps2 = @import("../../drivers/ps2.zig");
const Context = @import("../../context.zig");

// need to implement open

pub const Tty = struct {
    ring_buffer: [1024]u8 = undefined,
    head: usize = 0,
    tail: usize = 0,
    count: usize = 0,
    serial_output: bool = false,

    pub fn ttyKeyListener(event: Ps2.KeyEvent) void {
        const process = Context.ctx.scheduler.?.executing_process orelse return;
        const ascii = event.ascii orelse return;
        if (!event.pressed) return;
        const stdin = process.getFile(0) orelse return;
        _ = stdin.write(&.{ascii}) catch {};
    }

    pub fn getDescriptor(self: *Tty, allocator: std.mem.Allocator) !*File {
        const file = try allocator.create(File);
        file.* = .{
            .implementation = .{
                .tty = .{
                    .tty = self,
                },
            },
        };
        return file;
    }
};

pub const TtyFile = struct {
    tty: *Tty,

    pub fn read(self: *TtyFile, buffer: []u8) !usize {
        const to_read = @min(buffer.len, self.tty.count);
        for (0..to_read) |i| {
            buffer[i] = self.tty.ring_buffer[self.tty.tail];
            self.tty.tail = (self.tty.tail + 1) % self.tty.ring_buffer.len;
            self.tty.count -= 1;
        }
        return to_read;
    }

    /// Never blocks: bytes that do not fit in the ring are dropped and the short count is returned.
    pub fn write(self: *TtyFile, buffer: []const u8) !usize {
        if (self.tty.serial_output) {
            for (buffer) |byte| Serial.writeByte(byte);
            return buffer.len;
        }
        const to_write = @min(buffer.len, self.tty.ring_buffer.len - self.tty.count);
        for (0..to_write) |i| {
            self.tty.ring_buffer[self.tty.head] = buffer[i];
            self.tty.head = (self.tty.head + 1) % self.tty.ring_buffer.len;
            self.tty.count += 1;
        }
        return to_write;
    }

    pub fn seek(self: *TtyFile, offset: i32, whence: File.Whence) !u32 {
        _ = self;
        _ = offset;
        _ = whence;
        return error.Unsupported;
    }
};
