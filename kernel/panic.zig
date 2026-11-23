const std = @import("std");

pub fn panic(msg: []const u8) noreturn {
    std.log.err(msg);
    while (true) {
        asm volatile ("hlt");
    }
}
