const std = @import("std");

const Grub = @import("../lib/grub.zig");
const MultibootInfo = @import("../lib/grub.zig").MultibootInfo;
const color8_black = 0;
const color8_blue = 1;
const color8_green = 2;
const color8_cyan = 3;
const color8_red = 4;
const color8_magenta = 5;
const color8_brown = 6;
const color8_light_gray = 7;
const color8_dark_gray = 8;
const color8_light_blue = 9;
const color8_light_green = 10;
const color8_light_cyan = 11;
const color8_light_red = 12;
const color8_light_magenta = 13;
const color8_yellow = 14;
const color8_white = 15;

pub const LinearFrameBuffer = struct { fb_width: u32, fb_height: u32, pitch_pixels: u32, fb_linear_address: u64 };

var linear_framebuffer: ?LinearFrameBuffer = null;

pub fn init(multiboot_info: *MultibootInfo) void {
    linear_framebuffer = LinearFrameBuffer{
        .fb_width = multiboot_info.framebuffer_width,
        .fb_height = multiboot_info.framebuffer_height,
        .pitch_pixels = multiboot_info.framebuffer_pitch,
        .fb_linear_address = multiboot_info.framebuffer_addr,
    };
}

pub fn getLinearFrameBuffer() LinearFrameBuffer {
    return linear_framebuffer orelse {
        std.log.err("getLinearFrameBuffer: linear_framebuffer is null", .{});
        @panic("linear_framebuffer is null");
    };
}

pub fn testDrawBox() void {
    const fb = linear_framebuffer orelse {
        std.log.warn("testDrawBox: linear_framebuffer is null", .{});
        return;
    };
    if (fb.fb_linear_address == 0 or fb.fb_linear_address > std.math.maxInt(usize) or fb.fb_width == 0 or fb.fb_height == 0) {
        std.log.warn("testDrawBox: invalid fb addr or size", .{});
        return;
    }

    const addr: usize = @intCast(fb.fb_linear_address);
    const pixels: [*]volatile u32 = @ptrFromInt(addr);

    // pitch_pixels is actually bytes per scanline (e.g. 3200), so divide by 4 for u32 indexing
    const stride_u32: u32 = if (fb.pitch_pixels != 0) fb.pitch_pixels / 4 else fb.fb_width;

    const x0: u32 = @min(40, fb.fb_width -| 1);
    const y0: u32 = @min(40, fb.fb_height -| 1);
    const x1: u32 = @min(x0 + 160, fb.fb_width);
    const y1: u32 = @min(y0 + 100, fb.fb_height);

    var y: u32 = y0;
    while (y < y1) : (y += 1) {
        var x: u32 = x0;
        while (x < x1) : (x += 1) {
            const is_border = (x == x0 or x == x1 - 1 or y == y0 or y == y1 - 1);
            const color: u32 = if (is_border) 0x00FFFFFF else 0x00FF3366;
            const idx: usize = @as(usize, y) * @as(usize, stride_u32) + @as(usize, x);
            pixels[idx] = color;
        }
    }
}
