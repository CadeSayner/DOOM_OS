const std = @import("std");
const File = @import("vfs.zig").File;
const Inode = @import("vfs.zig").Inode;
const Serial = @import("../../drivers/serial.zig");
const Ps2 = @import("../../drivers/ps2.zig");
const SequenceBuffer = @import("../../lib/sequence.zig").SequenceBuffer;
const Context = @import("../../context.zig");
const OpenFlags = @import("../../syscalls/io.zig").OpenFlags;
const WaitQueue = @import("../../sched/waiter.zig").WaitQueue;

extern fn irq_save() u32;
extern fn irq_restore(flags: u32) void;

pub fn CharacterDevice(T: type) type {
    return struct {
        const Self = @This();
        inode: *Inode,
        sequence_buffer: SequenceBuffer(T, 1024) = .{},
        waiters: WaitQueue = .{},

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

        seq_no: u64 = 0,

        pub fn read(self: *Self, out: *T) !usize {
            if (OpenFlags.has(self.flags, OpenFlags.nonblock)) {
                if (!self.char.sequence_buffer.readAt(self.seq_no, out)) {
                    if (self.char.sequence_buffer.next_seq > self.seq_no) {
                        out.* = self.char.sequence_buffer.readOldest();
                        self.seq_no = self.char.sequence_buffer.oldestSeq() + 1;
                    } else {
                        return 0;
                    }
                } else {
                    self.seq_no += 1;
                }
            } else {
                std.log.info("Trying to read in blocking mode!!", .{});

                const flags = irq_save();
                try self.char.waiters.addWaiter(Context.ctx.scheduler.executing_process orelse return error.Unsupported);

                Context.ctx.scheduler.schedule();

                irq_restore(flags);
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
