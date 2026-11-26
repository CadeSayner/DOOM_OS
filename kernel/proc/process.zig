const std = @import("std");
const File = @import("../fs/vfs/vfs.zig").File;
const Constants = @import("../lib/constants.zig");
const FrameAllocator = @import("../mm/frame_allocator.zig").FrameAllocator;
const Timer = @import("../drivers/timer.zig");
const OpenFlags = @import("../syscalls/io.zig").OpenFlags;

const Vga = @import("../drivers/vga.zig");
const Vfs = @import("../fs/vfs/vfs.zig").Vfs;
const Elf = @import("../lib/elf.zig");
const Context = @import("../context.zig");

pub const Status = enum {
    Ready,
    Running,
    Waiting,
    Terminated,
};

pub const max_open_files = 32;
const first_free_fd = 2; // 0 and 1 are the process's ttys
const process_start_virtual_address = 0x08048000;
const page_directory_entry_flags = 0b10000011;
const page_table_flags = 0b00000111; // Present, Read/Write, User
const linear_frame_buffer_virtual_address = 0xA0000000;
const user_space_end = Constants.kernel_offset;
const stack_base_virtual_address = 0xB0000000;
const stack_pages_above_base = 5;
const stack_pages_below_base = 59; // the initial user esp sits just above the base
const frames_per_kernel_stack = 2;

// chore: come and make Constants.frame_size a global constant for page_size it is used everywhere
const kernel_stack_size = Constants.frame_size * frames_per_kernel_stack;

extern fn switch_to_user_mode_process(e_entry: u32) callconv(.c) void;
extern fn load_page_table(page_dir_phys: u32) void;
extern fn switch_context(old_esp: *u32, new_esp: u32) callconv(.c) void;

const PageTable = [1024]u32;

pub const PageDirectory = struct {
    page_directory_table: [1024]u32,
    pub fn init(self: *PageDirectory) *PageDirectory {
        self.page_directory_table = [_]u32{0} ** 1024;
        self.mapKernel();
        return self;
    }

    fn mapKernel(self: *PageDirectory) void {
        for (0..255) |i| {
            self.page_directory_table[768 + i] = (i << 22) | page_directory_entry_flags; // Present, Read/Write, User
        }
    }

    pub fn addMapping(self: *PageDirectory, page_number: u32, frame_number: u32, allocator: std.mem.Allocator) !void {
        const pde_index: usize = @intCast((page_number >> 10) & 0x3FF);
        const pte_index: usize = @intCast(page_number & 0x3FF);

        if (self.page_directory_table[pde_index] == 0) {
            const pt_slice = try allocator.alignedAlloc(u32, .fromByteUnits(Constants.frame_size), 1024);
            @memset(pt_slice, 0);

            const pt_virt: usize = @intFromPtr(pt_slice.ptr);
            const pt_phys: u32 = @intCast(Constants.virtToPhys(pt_virt));
            self.page_directory_table[pde_index] = (pt_phys & ~@as(u32, 0xFFF)) | page_table_flags;
        }

        const pde: u32 = self.page_directory_table[pde_index];
        const pt_phys_addr: u32 = pde & ~@as(u32, 0xFFF);
        const pt_virt_addr: usize = @intCast(pt_phys_addr + 0xC0000000);
        const page_table: [*]volatile u32 = @ptrFromInt(pt_virt_addr);

        page_table[pte_index] = ((frame_number << 12) & ~@as(u32, 0xFFF)) | page_table_flags;
    }

    /// Returns the frame number a page is mapped to, if any.
    pub fn lookup(self: *const PageDirectory, page_number: u32) ?u32 {
        const pde = self.page_directory_table[(page_number >> 10) & 0x3FF];
        if (pde & 1 == 0 or pde & 0x80 != 0) return null;
        const page_table: [*]const volatile u32 = @ptrFromInt((pde & ~@as(u32, 0xFFF)) + Constants.kernel_offset);
        const pte = page_table[page_number & 0x3FF];
        if (pte & 1 == 0) return null;
        return pte >> 12;
    }

    pub fn mapLinearFrameBuffer(self: *PageDirectory, allocator: std.mem.Allocator) !u32 {
        const fb = Vga.getLinearFrameBuffer();
        const physical_address: u32 = @intCast(fb.fb_linear_address);
        const physical_base = physical_address & ~@as(u32, 0xFFF);
        const offset = physical_address & 0xFFF;
        const bytes = fb.pitch_pixels * fb.fb_height + offset;
        const num_pages: u32 = (bytes + 0xFFF) / 0x1000;
        for (0..num_pages) |i| {
            const n: u32 = @intCast(i);
            try self.addMapping((linear_frame_buffer_virtual_address >> 12) + n, (physical_base >> 12) + n, allocator);
        }
        return linear_frame_buffer_virtual_address + offset;
    }
};

pub const Process = struct {
    pid: u32,
    entry_point: u32, // wont need this remove it later when the starting point will be defined when it gets schedules or do i still need it?
    status: Status,
    page_directory: *PageDirectory, // owns the page directory
    saved_esp: u32,
    kernel_stack_base: u32,
    kernel_stack_top: u32,
    sbrk: u32,
    brk: u32,
    start_time_ms: u64,
    file_descriptors: [max_open_files]?*File,
    allocator: std.mem.Allocator,
    ticks_allocated: u32,
    ticks_remaining: u32,

    pub fn create(entry_point: u32, start_time_ms: u64, process_file_size: usize, image_end: u32, page_directory: *PageDirectory, allocator: std.mem.Allocator, quantum: u32) !*Process {
        const process = try allocator.create(Process);

        var open_fds = [_]?*File{null} ** max_open_files;

        open_fds[0] = try Context.ctx.vfs.open("tty0", OpenFlags.rdwr, allocator);
        open_fds[1] = try Context.ctx.vfs.open("tty1", OpenFlags.rdwr, allocator);

        const heap_start: u32 = @max(
            std.mem.alignForward(u32, @intCast(process_start_virtual_address + process_file_size + 0x1000), 0x1000),
            std.mem.alignForward(u32, image_end, 0x1000),
        );

        // this should be inside of a member method
        const base = Context.ctx.frame_allocator.allocateConsecutiveFrames(frames_per_kernel_stack);
        const kernel_stack_current = prepareKernelStack(base + kernel_stack_size, &taskEntry);

        process.* = .{
            .pid = next_pid,
            .entry_point = entry_point,
            .status = .Ready,
            .kernel_stack_base = base,
            .kernel_stack_top = base + kernel_stack_size,
            .saved_esp = kernel_stack_current,
            .page_directory = page_directory,
            .ticks_remaining = quantum,
            .ticks_allocated = quantum,
            .sbrk = heap_start,
            .brk = heap_start,
            .start_time_ms = start_time_ms,
            .file_descriptors = open_fds,
            .allocator = allocator,
        };

        return process;
    }

    pub fn getFile(self: *Process, fd: u32) ?*File {
        if (fd >= max_open_files) return null;
        return self.file_descriptors[fd];
    }

    pub fn addFile(self: *Process, file: *File) ?u32 {
        for (first_free_fd..max_open_files) |fd| {
            if (self.file_descriptors[fd] == null) {
                self.file_descriptors[fd] = file;
                return @intCast(fd);
            }
        }
        return null;
    }

    pub fn closeFile(self: *Process, fd: u32) !void {
        const file = self.getFile(fd) orelse return error.BadFileDescriptor;
        self.file_descriptors[fd] = null;
        try file.close(self.allocator);
    }

    pub fn setBrk(self: *Process, new_brk: u32) bool {
        if (new_brk < self.sbrk or new_brk >= linear_frame_buffer_virtual_address) return false;
        self.brk = new_brk;
        return true;
    }

    pub fn isUserRangeValid(self: *const Process, addr: u32, len: u32) bool {
        if (len == 0) return true;
        const end = std.math.add(u32, addr, len) catch return false;
        if (end > user_space_end) return false;
        var page = addr >> 12;
        const last_page = (end - 1) >> 12;
        while (page <= last_page) : (page += 1) {
            if (self.page_directory.lookup(page) != null) continue;
            const page_start = page << 12;
            if (page_start + 0xFFF >= self.sbrk and page_start <= self.brk) continue;
            return false;
        }
        return true;
    }

    pub fn userBuffer(self: *const Process, addr: u32, len: u32) ?[]u8 {
        if (len == 0 or !self.isUserRangeValid(addr, len)) return null;
        const ptr: [*]u8 = @ptrFromInt(addr);
        return ptr[0..len];
    }

    pub fn userString(self: *const Process, addr: u32, max_len: u32) ?[]const u8 {
        var len: u32 = 0;
        while (len < max_len) : (len += 1) {
            const byte_addr = std.math.add(u32, addr, len) catch return null;
            if (!self.isUserRangeValid(byte_addr, 1)) return null;
            const ptr: [*]const u8 = @ptrFromInt(addr);
            if (ptr[len] == 0) return ptr[0..len];
        }
        return null;
    }

    pub fn prepareKernelStack(stack_top: u32, entry: *const fn () callconv(.c) noreturn) u32 {
        var sp: [*]u32 = @ptrFromInt(stack_top);
        sp -= 1;
        sp[0] = 0; // fake return address for entry
        sp -= 1;
        sp[0] = @intFromPtr(entry); // popped by 'ret' in switch_context
        sp -= 1;
        sp[0] = 0; // ebp
        sp -= 1;
        sp[0] = 0; // ebx
        sp -= 1;
        sp[0] = 0; // esi
        sp -= 1;
        sp[0] = 0; // edi (first pop)
        return @intFromPtr(sp);
    }
};

pub export fn taskEntry() callconv(.c) noreturn {
    const executing_process = Context.ctx.scheduler.executing_process orelse
        @panic("taskEntry was entered before a process was scheduled!");
    switch_to_user_mode_process(executing_process.entry_point);
    unreachable;
}

// TODO fix this since process exit should do something
fn halt() noreturn {
    while (true) asm volatile ("sti; hlt" ::: .{ .memory = true });
}

var next_pid: u32 = 1;

pub fn page_fault_handler(faulting_address: u32) i32 {
    const proc = Context.ctx.scheduler.executing_process orelse return -1;
    // We need the context allocator because this is executed in an interrupt
    if (faulting_address <= proc.brk and faulting_address >= proc.sbrk) {
        const new_page_frame_vaddr = Context.ctx.frame_allocator.allocateFrame();
        const frame: [*]u8 = @ptrFromInt(new_page_frame_vaddr);
        @memset(frame[0..Constants.frame_size], 0);
        proc.page_directory.addMapping(faulting_address >> 12, Constants.virtToPhys(new_page_frame_vaddr) >> 12, Context.ctx.allocator) catch return -1;
        return 0;
    }
    @panic("A page fault occured outside of the heap, this cannot be handled by the kernel!");
}

pub fn elf32_parse_file(file_name: []const u8, allocator: std.mem.Allocator) !*Process {
    const exec_file_inode = Context.ctx.vfs.lookup(file_name) orelse return error.FileNotFound;
    const file_base = @intFromPtr(exec_file_inode.data.ptr);
    const header: *const Elf.Elf32Ehdr = @ptrFromInt(file_base);

    if (exec_file_inode.data.len < @sizeOf(Elf.Elf32Ehdr) or !std.mem.eql(u8, header.e_ident[0..4], "\x7fELF") or header.e_ident[4] != 1) {
        return error.InvalidElf;
    }

    // Create the address space.
    const page_directory = try allocator.create(PageDirectory);
    _ = page_directory.init();

    const phdr: [*]const Elf.Elf32Phdr = @ptrFromInt(
        file_base + header.e_phoff,
    );

    var image_end: u32 = 0;
    for (phdr[0..header.e_phnum]) |segment| {
        if (segment.p_type != Elf.ProgramHeaderType.Load) continue;

        const start = segment.p_vaddr;
        const end = start + segment.p_memsz;
        if (end > linear_frame_buffer_virtual_address) return error.InvalidElf;
        image_end = @max(image_end, end);

        const first_page = start / Constants.frame_size;
        const last_page = (end + 4095) / Constants.frame_size;

        for (first_page..last_page) |page| {
            // A page shared with a previous segment keeps its frame and contents.
            var frame: u32 = undefined;
            if (page_directory.lookup(@intCast(page))) |existing| {
                frame = Constants.physToVirt(existing * Constants.frame_size);
            } else {
                frame = Context.ctx.frame_allocator.allocateFrame();
                const frame_zero: [*]u8 = @ptrFromInt(frame);
                @memset(frame_zero[0..Constants.frame_size], 0);
                try page_directory.addMapping(@intCast(page), Constants.virtToPhys(frame) / Constants.frame_size, allocator);
            }

            const frame_ptr: [*]u8 = @ptrFromInt(frame);

            const page_start = page * Constants.frame_size;
            const copy_start = @max(page_start, start);
            const copy_end = @min(page_start + Constants.frame_size, start + segment.p_filesz);

            if (copy_start >= copy_end) continue;

            const bytes = copy_end - copy_start;
            const source_offset = segment.p_offset + copy_start - start;
            const dest_offset = copy_start - page_start;

            const source: [*]const u8 = @ptrFromInt(file_base + source_offset);

            @memcpy(
                frame_ptr[dest_offset..][0..bytes],
                source[0..bytes],
            );
        }
    }

    // User stack, the initial esp is set by switch_to_user_mode_process.
    const stack_first_page = (stack_base_virtual_address >> 12) - stack_pages_below_base;
    for (0..stack_pages_below_base + stack_pages_above_base) |i| {
        const stack_frame = Context.ctx.frame_allocator.allocateFrame();
        const stack_ptr: [*]u8 = @ptrFromInt(stack_frame);
        @memset(stack_ptr[0..Constants.frame_size], 0);
        try page_directory.addMapping(stack_first_page + @as(u32, @intCast(i)), Constants.virtToPhys(stack_frame) / Constants.frame_size, allocator);
    }

    return try Process.create(
        header.e_entry,
        Timer.get_ticks(),
        exec_file_inode.size,
        image_end,
        page_directory,
        allocator,
        10
    );
}
