const std = @import("std");
const File = @import("vfs.zig").File;
const Inode = @import("vfs.zig").Inode;
const Serial = @import("../../drivers/serial.zig");
const Ps2 = @import("../../drivers/ps2.zig");
const SequenceBuffer = @import("../../lib/sequence.zig").SequenceBuffer;
const Context = @import("../../context.zig");
const OpenFlags = @import("../../syscalls/io.zig").OpenFlags;

pub fn CharacterDevice(T: type) type {
    return struct {
        const Self = @This();
        inode: *Inode,
        sequence_buffer: SequenceBuffer(T, 1024) = undefined,
        pub fn init(inode: *Inode) Self {
            return .{ .inode = inode };
        }

        pub fn getDescriptor(self: *Self, allocator: std.mem.Allocator, flags: u32) !*File {
            const file = try allocator.create(File);
            file.* = .{
                .implementation = .{
                    .ps2_char_file = .{
                        .char = self,
                        .flags = flags,
                    },
                },
            };
            return file;
        }
    };
}

pub fn CharacterDeviceFile(T: type) type {
    return struct {
        const Self = @This();
        char: *CharacterDevice(T),
        flags: u32,

        var seq_no : u64 = 0;

        pub fn read(self: *Self, out: *T) !usize {
            if(OpenFlags.has(self.flags, OpenFlags.nonblock)){
                if (!self.char.sequence_buffer.readAt(seq_no, out)) {
                    out.* = self.char.sequence_buffer.readOldest();
                    seq_no += 1;
                }
            }else{
                std.log.err("Trying to read character device in blocking mode", .{});
                return error.NotSupported;
            }
            return @sizeOf(T);
        }

        pub fn write(self: *Self, value: T) void {
            self.char.sequence_buffer.push(value);
        }

        pub fn seek(self: *Self, offset: i32, whence: File.Whence) !u32 {
            _ = self;
            _ = offset;
            _ = whence;
            return error.Unsupported;
        }

        pub fn close(self: *Self, allocator: std.mem.Allocator) void {
            self.char.inode.removeRef(allocator);
        }
    };
}

pub const CharDeviceFile = struct {
    char: *CharacterDevice,

    pub fn read(self: *CharDeviceFile, buffer: []u8) !usize {
        const to_read = @min(buffer.len, self.character_device.count);
        for (0..to_read) |i| {
            buffer[i] = self.character_device.ring_buffer[self.character_device.tail];
            self.character_device.tail = (self.character_device.tail + 1) % self.character_device.ring_buffer.len;
            self.character_device.count -= 1;
        }
        return to_read;
    }

    /// Never blocks: bytes that do not fit in the ring are dropped and the short count is returned.
    pub fn write(self: *CharDeviceFile, buffer: []const u8) !usize {
        if (self.character_device.serial_output) {
            for (buffer) |byte| Serial.writeByte(byte);
            return buffer.len;
        }
        const to_write = @min(buffer.len, self.character_device.ring_buffer.len - self.character_device.count);
        for (0..to_write) |i| {
            self.character_device.ring_buffer[self.character_device.head] = buffer[i];
            self.character_device.head = (self.character_device.head + 1) % self.character_device.ring_buffer.len;
            self.character_device.count += 1;
        }
        return to_write;
    }

    pub fn seek(self: *CharDeviceFile, offset: i32, whence: File.Whence) !u32 {
        _ = self;
        _ = offset;
        _ = whence;
        return error.Unsupported;
    }

    pub fn close(self: *CharDeviceFile, allocator: std.mem.Allocator) void {
        self.character_device.inode.removeRef(allocator);
    }
};
