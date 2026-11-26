const std = @import("std");

const Allocator = std.mem.Allocator;
const TarFile = @import("../tarfs/tarfs.zig").TarFile;
const Ps2 = @import("../../drivers/ps2.zig");
const CharacterDevice = @import("character_device.zig");
const Ps2CharacterDevice = CharacterDevice.CharacterDevice(Ps2.KeyEvent);
const Ps2CharacterDeviceFile = CharacterDevice.CharacterDeviceFile(Ps2.KeyEvent);

pub const Inode = struct {
    inode_number: usize,
    kind: Kind,
    size: usize,
    data: []const u8,
    device: ?Device = null,
    refs: usize = 0,
    nlinks: usize = 0,
    pub const Kind = enum { file, directory, device };

    pub fn addLink(self: *Inode) void {
        self.nlinks += 1;
    }

    pub fn removeLink(self: *Inode, allocator: std.mem.Allocator) void {
        self.nlinks -= 1;
        if (self.nlinks == 0 and self.refs == 0) {
            allocator.destroy(self);
        }
    }

    pub fn addRef(self: *Inode) void {
        self.refs += 1;
    }

    pub fn removeRef(self: *Inode, allocator: std.mem.Allocator) void {
        self.refs -= 1;
        if (self.nlinks == 0 and self.refs == 0) {
            allocator.destroy(self);
        }
    }
};

pub const Device = union(enum) {
    ps2_event_char: *Ps2CharacterDevice,
    tty: *void,
    null: void,
    zero: void,
};

pub const Dentry = struct {
    name: []const u8,
    inode: *Inode,
    next: ?*Dentry = null,
};

// Represents an open file in the vfs, every type of implementation should provide a function which creates this type
pub const File = struct {
    implementation: Implementation,

    pub const Implementation = union(enum) { tty: void, tar: TarFile, ps2_char_file: Ps2CharacterDeviceFile };

    pub fn read(self: *File, buffer: []u8) !usize {
        return switch (self.implementation) {
            .tty => error.NotImplemented,
            .tar => |*tar| tar.read(buffer),
            .ps2_char_file => |*char| char.read(@ptrCast(buffer)),
        };
    }

    pub fn write(self: *File, buffer: []const u8) !usize {
        return switch (self.implementation) {
            .tty => error.NotImplemented,
            .tar => |*tar| tar.write(buffer),
            .ps2_char_file => error.NotImplemented,
        };
    }

    pub const Whence = enum {
        set,
        cur,
        end,
    };
    pub fn seek(self: *File, offset: i32, whence: Whence) !u32 {
        return switch (self.implementation) {
            .tty => error.NotImplemented,
            .tar => |*tar| tar.seek(offset, whence),
            .ps2_char_file => error.NotImplemented,
        };
    }

    pub fn close(self: *File, allocator: Allocator) !void {
        // in future this should not be able to throw
        try switch (self.implementation) {
            .tty => error.NotImplemented,
            .ps2_char_file => |*char| {
                char.close(allocator);
            } ,
            .tar => |*tar| {
                tar.close(allocator);
            },
            
        };
        allocator.destroy(self);
    }
};

pub const Vfs = struct {
    allocator: Allocator,
    root: *Inode,
    dentries: ?*Dentry = null,
    next_inode_number: usize = 1,

    pub fn init(allocator: Allocator) !Vfs {
        const root = try allocator.create(Inode);
        root.* = .{
            .inode_number = 0,
            .kind = Inode.Kind.directory,
            .size = 0,
            .data = &.{},
            .device = null,
        };
        return .{
            .allocator = allocator,
            .root = root,
        };
    }

    // adds an inode to the vfs directly, the caller must provide a valid inode created by createInode
    pub fn addInode(self: *Vfs, name: []const u8, inode: *Inode) !*Inode {
        const dentry = try self.allocator.create(Dentry);
        dentry.* = .{
            .name = name,
            .inode = inode,
            .next = self.dentries,
        };
        inode.addLink();
        self.dentries = dentry;
        return inode;
    }

    // create an inode in the vfs
    pub fn createInode(self: *Vfs, kind: Inode.Kind, size: usize, data: []const u8) !*Inode {
        const inode = try self.allocator.create(Inode);
        inode.* = .{
            .inode_number = self.next_inode_number,
            .kind = kind,
            .size = size,
            .data = data,
        };
        self.next_inode_number += 1;
        return inode;
    }

    pub fn addEntry(self: *Vfs, name: []const u8, kind: Inode.Kind, data: []const u8, size: usize) !*Inode {
        const inode = try self.createInode(kind, size, data);
        _ = try self.addInode(name, inode);
        return inode;
    }

    pub fn lookup(self: *Vfs, name: []const u8) ?*Inode {
        var dentry = self.dentries;
        while (dentry) |entry| {
            const clean_entry = std.mem.sliceTo(entry.name, 0);
            if (std.mem.eql(u8, clean_entry, name)) {
                return entry.inode;
            }
            dentry = entry.next;
        }
        return null;
    }

    // TODO: Instead of just freeing everything like this the inode should be reference counted, the dentry can be removed without incident
    pub fn removeEntry(self: *Vfs, name: []const u8) !void {
        var link = &self.dentries;
        while (link.*) |entry| {
            if (std.mem.eql(u8, entry.name, name)) {
                link.* = entry.next;
                // self.allocator.free(entry.inode.data);
                // self.allocator.destroy(entry.inode);
                self.allocator.free(entry.name);
                self.allocator.destroy(entry);
                entry.inode.removeLink();
                return;
            }
            link = &entry.next;
        }
        return error.NotFound;
    }

    pub fn open(self: *Vfs, name: []const u8, flags: u32, allocator: std.mem.Allocator) !*File {
        const inode = self.lookup(name) orelse return error.FileNotFound;
        const file = switch (inode.kind) {
            .file => try TarFile.init(inode).getDescriptor(allocator),
            .device => {
                const device = inode.device orelse return error.DeviceNotFound;
                return switch (device) {
                    .ps2_event_char => |ps2_device| blk: {
                        const f = try ps2_device.getDescriptor(allocator, flags);
                        inode.addRef();
                        break :blk f;
                    },
                    .tty => error.DeviceNotFound,
                    .null => error.DeviceNotFound,
                    .zero => error.DeviceNotFound,
                };
            },
            .directory => return error.IsDirectory,
        };
        inode.addRef();
        return file;
    }

    pub fn ls(self: *Vfs) void {
        var dentry = self.dentries;
        while (dentry) |entry| {
            std.log.info("{s}", .{entry.name});
            dentry = entry.next;
        }
    }
};
