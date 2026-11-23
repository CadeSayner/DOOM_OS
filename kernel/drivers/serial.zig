const std = @import("std");
const port = @import("port.zig");

const com1: u16 = 0x3F8;

pub fn init() void {
    port.outb(com1 + 1, 0x00); // Disable all interrupts
    port.outb(com1 + 3, 0x80); // Enable DLAB (set baud rate divisor)
    port.outb(com1 + 0, 0x03); // Divisor lo byte (38400 baud)
    port.outb(com1 + 1, 0x00); // Divisor hi byte
    port.outb(com1 + 3, 0x03); // 8 bits, no parity, one stop bit
    port.outb(com1 + 2, 0xC7); // Enable FIFO, clear them, 14-byte threshold
    port.outb(com1 + 4, 0x0B); // IRQs enabled, RTS/DSR set
}

fn isTransmitEmpty() bool {
    return (port.inb(com1 + 5) & 0x20) != 0;
}

pub fn writeByte(byte: u8) void {
    while (!isTransmitEmpty()) {}
    port.outb(com1, byte);
}

fn emit(bytes: []const u8) void {
    for (bytes) |b| {
        if (b == '\n') writeByte('\r');
        writeByte(b);
    }
}

fn drain(w: *std.Io.Writer, data: []const []const u8, splat: usize) std.Io.Writer.Error!usize {
    emit(w.buffered());
    w.end = 0;

    var consumed: usize = 0;
    for (data[0 .. data.len - 1]) |slice| {
        emit(slice);
        consumed += slice.len;
    }
    const last = data[data.len - 1];
    for (0..splat) |_| emit(last);
    consumed += last.len * splat;

    return consumed;
}

pub var writer: std.Io.Writer = .{
    .vtable = &.{ .drain = drain },
    .buffer = &.{},
};

pub fn print(comptime format: []const u8, args: anytype) void {
    writer.print(format, args) catch {};
}

pub fn kernelLogFn(
    comptime message_level: std.log.Level,
    comptime scope: @TypeOf(.enum_literal),
    comptime format: []const u8,
    args: anytype,
) void {
    const level_txt = comptime message_level.asText();
    const prefix = if (scope == .default) ": " else "(" ++ @tagName(scope) ++ "): ";
    print("[" ++ level_txt ++ "]" ++ prefix ++ format ++ "\n", args);
}
