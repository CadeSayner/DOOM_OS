const std = @import("std");
const os = @import("doom_os");

export fn main() c_int {
    var sink: u32 = 0x12345678;
    while (true) {
        var i: u32 = 0;
        while (i < 10_000_000) : (i += 1) {
            sink = (sink *% 1664525) +% 1013904223;
        }
    }
    return 0;
}
