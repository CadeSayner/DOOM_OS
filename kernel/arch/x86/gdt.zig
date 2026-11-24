const std = @import("std");

extern fn gdt_flush(ptr: *const GdtPtr) callconv(.c) void;
extern fn tss_flush() callconv(.c) void;
extern const stack_top: u32;

pub const sel = struct {
    pub const kernel_code: u16 = 0x08;
    pub const kernel_data: u16 = 0x10;
    pub const user_code: u16 = 0x18 | 3;
    pub const user_data: u16 = 0x20 | 3;
    pub const tss: u16 = 0x28;
};

const access = struct {
    const kernel_code: u8 = 0x9A;
    const kernel_data: u8 = 0x92;
    const user_code: u8 = 0xFA;
    const user_data: u8 = 0xF2;
    const tss_available: u8 = 0xE9;
};

const flags_flat_32: u4 = 0xC;

const GdtPtr = packed struct(u48) {
    limit: u16,
    base: u32,
};

const Tss = extern struct{
    prev_tss: u32,
    esp0: u32,
    ss0: u32,
    esp1: u32,
    ss1: u32,
    esp2: u32,
    ss2: u32,
    cr3: u32,
    eip: u32,
    eflags: u32,
    eax: u32,
    ecx: u32,
    edx: u32,
    ebx: u32,
    esp: u32,
    ebp: u32,
    esi: u32,
    edi: u32,
    es: u32,
    cs: u32,
    ss: u32,
    ds: u32,
    fs: u32,
    gs: u32,
    ldt: u32,
    trap: u16,
    iomap_base: u16,
};

const GdtEntry = packed struct(u64) {
    limit_low: u16,
    base_low: u16,
    base_middle: u8,
    access: u8,
    limit_high: u4,
    flags: u4,
    base_high: u8,

    fn init(base: u32, limit: u32, acc: u8, flags: u4) GdtEntry {
        return .{
            .limit_low = @truncate(limit),
            .base_low = @truncate(base),
            .base_middle = @truncate(base >> 16),
            .access = acc,
            .limit_high = @truncate(limit >> 16),
            .flags = flags,
            .base_high = @truncate(base >> 24),
        };
    }
};

var gdt: [6]GdtEntry = .{
    GdtEntry.init(0, 0, 0, 0), // Null segment
    GdtEntry.init(0, 0xFFFFFFFF, access.kernel_code, flags_flat_32), // Kernel Code segment
    GdtEntry.init(0, 0xFFFFFFFF, access.kernel_data, flags_flat_32), // Kernel Data segment
    GdtEntry.init(0, 0xFFFFFFFF, access.user_code, flags_flat_32), // User mode code segment
    GdtEntry.init(0, 0xFFFFFFFF, access.user_data, flags_flat_32), // User mode data segment
    GdtEntry.init(0, 0, 0, 0), // TSS segment to be filled in
};

var gdt_ptr: GdtPtr = undefined;
var tss: Tss = std.mem.zeroes(Tss);

pub fn init() void {
    writeTss(5, sel.kernel_data, @intCast(@intFromPtr(&stack_top)));

    gdt_ptr = .{
        .limit = @sizeOf(@TypeOf(gdt)) - 1,
        .base = @intCast(@intFromPtr(&gdt)),
    };

    gdt_flush(&gdt_ptr);
    tss_flush();
}

fn writeTss(comptime index: usize, ss0: u16, esp0: u32) void {
    const base: u32 = @intCast(@intFromPtr(&tss));
    const limit: u32 = @sizeOf(Tss) - 1;
    gdt[index] = GdtEntry.init(base, limit, access.tss_available, 0);
    tss = std.mem.zeroes(Tss);
    tss.ss0 = ss0;
    tss.esp0 = esp0;
    tss.cs = sel.kernel_code | 3;
    tss.ss = sel.kernel_data | 3;
    tss.ds = sel.kernel_data | 3;
    tss.es = sel.kernel_data | 3;
    tss.fs = sel.kernel_data | 3;
    tss.gs = sel.kernel_data | 3;
}

fn set_kernel_stack(esp0: u32) void {
    tss.esp0 = esp0;
}