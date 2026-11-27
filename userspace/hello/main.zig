const std = @import("std");
const os = @import("doom_os");

extern fn sleep(ms: u32) void;

export fn main() c_int {
    while (true) {
        sleep(5000);
    }
    return 0;
}
