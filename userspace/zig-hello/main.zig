const std = @import("std");
const os = @import("doom_os");

export fn main() c_int {
    run() catch return 1;
    return 0;
}

fn run() !void {
    var numbers: std.ArrayList(u32) = .empty;
    defer numbers.deinit(os.allocator);
    try numbers.append(os.allocator, 43);

    const message = try std.fmt.allocPrint(os.allocator, "Hello from Ziggyyyy The answer is {d}.\n", .{numbers.items[0]});
    defer os.allocator.free(message);
    try os.writeAll(1, message);
}
