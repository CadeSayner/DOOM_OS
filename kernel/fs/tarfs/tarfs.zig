const Grub = @import("../../lib/grub.zig");
const Vfs = @import("../vfs/vfs.zig").Vfs;
const std = @import("std");
const InodeKind = @import("../vfs/vfs.zig").Inode.Kind;
const Constants = @import("../../lib/constants.zig");
const File = @import("../vfs/vfs.zig").File;

const tar_block_size = 512;
const TarTypeFlag = enum(u8) {
    regular = '0',
    hard_link = '1',
    symbolic_link = '2',
    character_device = '3',
    block_device = '4',
    directory = '5',
    fifo = '6',
    contiguous_file = '7',
};

const TarHeader = extern struct {
    name: [100]u8,
    mode: [8]u8,
    uid: [8]u8,
    gid: [8]u8,
    size: [12]u8,
    mtime: [12]u8,
    chksum: [8]u8,
    typeflag: u8,
    linkname: [100]u8,
    magic: [6]u8,
    version: [2]u8,
    uname: [32]u8,
    gname: [32]u8,
    devmajor: [8]u8,
    devminor: [8]u8,
    prefix: [155]u8,
    pad: [12]u8,
};

pub fn mountTarFs(initrd: *Grub.Module, vfs: *Vfs) !void {
    std.log.info("Mounting TarFs", .{});
    var tar_header: *TarHeader = @ptrFromInt(Constants.physToVirt(initrd.module_start));
    while (true) {
        const addr = @intFromPtr(tar_header);
        if (addr >= Constants.physToVirt(initrd.module_end) or addr < Constants.physToVirt(initrd.module_start)) {
            break;
        }
        if (tar_header.name[0] == 0) {
            break;
        }

        const size = try parseOctal(tar_header.size);
        const is_directory = tar_header.typeflag == @intFromEnum(TarTypeFlag.directory);
        const payload_ptr: [*]const u8 = @ptrFromInt(@intFromPtr(tar_header) + @sizeOf(TarHeader));
        std.log.info("The payload pointer is {x}", .{@intFromPtr(payload_ptr)});
        const data: []const u8 = if (is_directory) &.{} else payload_ptr[0..size];
        _ = try vfs.addEntry(&tar_header.name, if (is_directory) InodeKind.directory else InodeKind.file, data, null);

        const next_header_addr = addr + @sizeOf(TarHeader) + ((size + tar_block_size - 1) / tar_block_size) * tar_block_size;
        tar_header = @ptrFromInt(next_header_addr);
    }
}

fn parseOctal(raw: [12]u8) !usize {
    const trimmed = std.mem.trim(u8, &raw, &.{ 0, ' ' });
    if (trimmed.len == 0) {
        return 0;
    }
    return std.fmt.parseInt(usize, trimmed, 8);
}

pub const TarFile = struct {
    data: []const u8,
    offset: usize = 0,

    pub fn init(data: []const u8) TarFile {
        return TarFile{
            .data = data,
            .offset = 0,
        };
    }

    pub fn getDescriptor(self: TarFile, allocator: std.mem.Allocator) !*File {
        const file = try allocator.create(File);
        file.* = .{
            .implementation = .{ .tar = self },
        };
        return file;
    }

    pub fn read(self: *TarFile, buffer: []u8) !usize {
        if (self.offset >= self.data.len)
            return 0;

        const count = @min(
            buffer.len,
            self.data.len - self.offset,
        );

        @memcpy(
            buffer[0..count],
            self.data[self.offset..][0..count],
        );

        self.offset += count;
        return count;
    }

    pub fn write(self: *TarFile, buffer: []const u8) !usize {
        _ = self;
        _ = buffer;
        return error.ReadOnlyFilesystem;
    }

    pub fn seek(self: *TarFile, offset: i32, whence: File.Whence) !u32 {
        const base: i64 = switch (whence) {
            .set => 0,
            .cur => @intCast(self.offset),
            .end => @intCast(self.data.len),
        };
        const new_offset = base + offset;
        if (new_offset < 0 or new_offset > self.data.len) return error.InvalidSeek;

        self.offset = @intCast(new_offset);
        return @intCast(new_offset);
    }
};
