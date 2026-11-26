const std = @import("std");
const os = @import("doom_os");

export fn main() c_int {
    run() catch return 1;

    return 0;
}

const screen_width = 1280;
const screen_height = 720;
const left_screen_width = screen_width / 2;

fn run() !void {
    const framebuffer = os.mapLinearFramebuffer();
    const pixels: [*]u32 = @ptrCast(@alignCast(framebuffer));
    var frame: u32 = 0;
    while (true) : (frame +%= 1) {
        drawRightPattern(pixels, screen_width, frame);
    }
}

fn drawRightPattern(pixels: [*]u32, stride_pixels: usize, frame: u32) void {
    var y: u32 = 0;
    while (y < screen_height) : (y += 1) {
        const row_offset = y * stride_pixels;
        var x: u32 = left_screen_width;
        while (x < screen_width) : (x += 1) {
            const wave = ((x ^ (y +% frame)) +% (frame >> 1)) & 0xFF;
            const pulse = (((x *% 3) ^ (y *% 5)) +% (frame *% 7)) & 0xFF;
            const blue = @max(wave, pulse);
            pixels[row_offset + x] = 0xFF000000 | (blue);
        }
    }
}
