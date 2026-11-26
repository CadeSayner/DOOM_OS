const std = @import("std");
const Port = @import("port.zig");
const InterruptRegisters = @import("../arch/x86/idt.zig").InterruptRegisters;
const CharacterDevice = @import("../fs/vfs/character_device.zig").CharacterDevice;

const kbd_data_port = 0x60;
const kbd_status_port = 0x64;

var shift_pressed: bool = false;

const KeyChar = struct {
    normal: u8,
    shifted: u8,
};

pub const KeyEvent = struct {
    scan_code: u8,
    ascii: ?u8,
    pressed: bool,
    shift: bool,
};

const keymap: [256]?KeyChar = blk: {
    var table: [256]?KeyChar = .{null} ** 256;

    table[0x10] = KeyChar{ .normal = 'q', .shifted = 'Q' };
    table[0x11] = KeyChar{ .normal = 'w', .shifted = 'W' };
    table[0x12] = KeyChar{ .normal = 'e', .shifted = 'E' };
    table[0x13] = KeyChar{ .normal = 'r', .shifted = 'R' };
    table[0x14] = KeyChar{ .normal = 't', .shifted = 'T' };
    table[0x15] = KeyChar{ .normal = 'y', .shifted = 'Y' };
    table[0x16] = KeyChar{ .normal = 'u', .shifted = 'U' };
    table[0x17] = KeyChar{ .normal = 'i', .shifted = 'I' };
    table[0x18] = KeyChar{ .normal = 'o', .shifted = 'O' };
    table[0x19] = KeyChar{ .normal = 'p', .shifted = 'P' };
    table[0x1E] = KeyChar{ .normal = 'a', .shifted = 'A' };
    table[0x1F] = KeyChar{ .normal = 's', .shifted = 'S' };
    table[0x20] = KeyChar{ .normal = 'd', .shifted = 'D' };
    table[0x21] = KeyChar{ .normal = 'f', .shifted = 'F' };
    table[0x22] = KeyChar{ .normal = 'g', .shifted = 'G' };
    table[0x23] = KeyChar{ .normal = 'h', .shifted = 'H' };
    table[0x24] = KeyChar{ .normal = 'j', .shifted = 'J' };
    table[0x25] = KeyChar{ .normal = 'k', .shifted = 'K' };
    table[0x26] = KeyChar{ .normal = 'l', .shifted = 'L' };
    table[0x2C] = KeyChar{ .normal = 'z', .shifted = 'Z' };
    table[0x2D] = KeyChar{ .normal = 'x', .shifted = 'X' };
    table[0x2E] = KeyChar{ .normal = 'c', .shifted = 'C' };
    table[0x2F] = KeyChar{ .normal = 'v', .shifted = 'V' };
    table[0x30] = KeyChar{ .normal = 'b', .shifted = 'B' };
    table[0x31] = KeyChar{ .normal = 'n', .shifted = 'N' };
    table[0x32] = KeyChar{ .normal = 'm', .shifted = 'M' };

    // numbers
    table[0x02] = KeyChar{ .normal = '1', .shifted = '!' };
    table[0x03] = KeyChar{ .normal = '2', .shifted = '@' };
    table[0x04] = KeyChar{ .normal = '3', .shifted = '#' };
    table[0x05] = KeyChar{ .normal = '4', .shifted = '$' };
    table[0x06] = KeyChar{ .normal = '5', .shifted = '%' };
    table[0x07] = KeyChar{ .normal = '6', .shifted = '^' };
    table[0x08] = KeyChar{ .normal = '7', .shifted = '&' };
    table[0x09] = KeyChar{ .normal = '8', .shifted = '*' };
    table[0x0A] = KeyChar{ .normal = '9', .shifted = '(' };
    table[0x0B] = KeyChar{ .normal = '0', .shifted = ')' };

    // whitespace and controls
    table[0x01] = KeyChar{ .normal = 27, .shifted = 27 }; // Escape
    table[0x0E] = KeyChar{ .normal = 0x08, .shifted = 0x08 }; // Backspace
    table[0x0F] = KeyChar{ .normal = '\t', .shifted = '\t' }; // Tab
    table[0x39] = KeyChar{ .normal = ' ', .shifted = ' ' }; // Space
    table[0x1C] = KeyChar{ .normal = '\n', .shifted = '\n' }; // Enter

    break :blk table;
};

fn scanCodeToAscii(scan_code: u8, shifted: bool) ?u8 {
    const mapped = keymap[scan_code] orelse return null;
    return if (shifted) mapped.shifted else mapped.normal;
}

pub fn kbdHandler(regs: *InterruptRegisters) void {
    _ = regs;
    const scan_code = Port.inb(kbd_data_port);
    switch (scan_code) {
        0x2A, 0x36 => shift_pressed = true,
        0xAA, 0xB6 => shift_pressed = false,
        else => {
            const ascii = scanCodeToAscii(scan_code, shift_pressed);
            if (ascii) |c| {
                _ = c;
                emit(.{ .ascii = ascii, .scan_code = scan_code, .pressed = true, .shift = shift_pressed });
            }
        },
    }
}

pub const Listener = CharacterDevice(KeyEvent);

const max_listeners = 1; // for now only one listener is allowed

var listeners: [max_listeners]?Listener = .{null} ** max_listeners;
var listener_count: usize = 0;

pub fn subscribe(listener: Listener) !void {
    for (listeners[0..listener_count]) |existing| {
        if (existing == listener) return; // already subscribed
    }
    if (listener_count >= max_listeners) {
        return error.TooManyListeners;
    }
    listeners[listener_count] = listener;
    listener_count += 1;
}


pub fn emit(event: KeyEvent) void {
    for (listeners[0..listener_count]) |*maybe_cb| {
        if (maybe_cb.*) |*cb| {
            cb.sequence_buffer.push(event);
        }
    }
}
