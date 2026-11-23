const std = @import("std");
const strings = @import("string.zig");
const sys = @import("syscall.zig");
const heap = @import("memory.zig");
const stdio = @import("stdio.zig");

pub export fn atoi(s: [*:0]const u8) c_int {
    var i: usize = 0;
    while (strings.isspace(s[i]) != 0) : (i += 1) {}
    const neg = s[i] == '-';
    if (s[i] == '-' or s[i] == '+') i += 1;
    var value: c_int = 0;
    while (s[i] >= '0' and s[i] <= '9') : (i += 1) {
        value = value *% 10 +% @as(c_int, s[i] - '0');
    }
    return if (neg) -%value else value;
}

pub export fn atof(s: [*:0]const u8) f64 {
    var i: usize = 0;
    while (strings.isspace(s[i]) != 0) : (i += 1) {}
    const neg = s[i] == '-';
    if (s[i] == '-' or s[i] == '+') i += 1;
    var value: f64 = 0;
    while (s[i] >= '0' and s[i] <= '9') : (i += 1) {
        value = value * 10 + @as(f64, @floatFromInt(s[i] - '0'));
    }
    if (s[i] == '.') {
        i += 1;
        var place: f64 = 0.1;
        while (s[i] >= '0' and s[i] <= '9') : (i += 1) {
            value += @as(f64, @floatFromInt(s[i] - '0')) * place;
            place *= 0.1;
        }
    }
    return if (neg) -value else value;
}

pub export fn abs(value: c_int) c_int {
    return if (value < 0) -%value else value;
}

pub export fn fabs(value: f64) f64 {
    return @abs(value);
}

const Writer = struct {
    buffer: [*c]u8,
    capacity: usize,
    length: usize = 0,

    fn put(self: *Writer, c: u8) void {
        if (self.capacity > 0 and self.length < self.capacity - 1) self.buffer[self.length] = c;
        self.length += 1;
    }

    fn repeat(self: *Writer, c: u8, count: usize) void {
        for (0..count) |_| self.put(c);
    }
};

pub export fn vsnprintf(buffer: [*c]u8, capacity: usize, fmt: [*:0]const u8, args: std.builtin.VaList) c_int {
    var original = args;
    var ap = @cVaCopy(&original);
    defer @cVaEnd(&ap);
    var out = Writer{ .buffer = buffer, .capacity = capacity };
    var i: usize = 0;
    while (fmt[i] != 0) {
        if (fmt[i] != '%') {
            out.put(fmt[i]);
            i += 1;
            continue;
        }
        i += 1;
        if (fmt[i] == '%') {
            out.put('%');
            i += 1;
            continue;
        }
        var left = false;
        var zero = false;
        while (fmt[i] == '-' or fmt[i] == '0') : (i += 1) {
            if (fmt[i] == '-') left = true else zero = true;
        }
        var width: usize = 0;
        while (fmt[i] >= '0' and fmt[i] <= '9') : (i += 1) width = width * 10 + (fmt[i] - '0');
        var precision: ?usize = null;
        if (fmt[i] == '.') {
            i += 1;
            precision = 0;
            while (fmt[i] >= '0' and fmt[i] <= '9') : (i += 1) precision = precision.? * 10 + (fmt[i] - '0');
        }
        if (fmt[i] == 'l' or fmt[i] == 'z') i += 1;
        const spec = fmt[i];
        if (spec == 0) {
            sys.errno = 22;
            return -1;
        }
        i += 1;
        var digits: [32]u8 = undefined;
        var text: []const u8 = undefined;
        var negative = false;
        if (spec == 's') {
            const s = @cVaArg(&ap, ?[*:0]const u8) orelse "(null)";
            const len = strings.strlen(s);
            text = s[0..@min(len, precision orelse len)];
        } else if (spec == 'c') {
            digits[0] = @truncate(@as(c_uint, @bitCast(@cVaArg(&ap, c_int))));
            text = digits[0..1];
        } else if (spec == 'd' or spec == 'i' or spec == 'u' or spec == 'x' or spec == 'X' or spec == 'p') {
            var value: u32 = if (spec == 'd' or spec == 'i') blk: {
                const signed = @cVaArg(&ap, c_int);
                negative = signed < 0;
                break :blk if (negative) @as(u32, @bitCast(-%signed)) else @as(u32, @bitCast(signed));
            } else @cVaArg(&ap, c_uint);
            const base: u32 = if (spec == 'x' or spec == 'X' or spec == 'p') 16 else 10;
            var pos: usize = digits.len;
            while (true) {
                pos -= 1;
                const digit: u8 = @intCast(value % base);
                digits[pos] = if (digit < 10) '0' + digit else (if (spec == 'X') @as(u8, 'A') else @as(u8, 'a')) + digit - 10;
                value /= base;
                if (value == 0) break;
            }
            text = digits[pos..];
        } else {
            sys.errno = 22;
            return -1;
        }
        const numeric = spec == 'd' or spec == 'i' or spec == 'u' or spec == 'x' or spec == 'X' or spec == 'p';
        const leading_zeroes = if (numeric and precision != null) (precision.? -| text.len) else 0;
        const total = text.len + leading_zeroes + @as(usize, @intFromBool(negative));
        const padding = width -| total;
        if (!left and (!zero or precision != null)) out.repeat(' ', padding);
        if (negative) out.put('-');
        if (!left and zero and precision == null) out.repeat('0', padding);
        out.repeat('0', leading_zeroes);
        for (text) |c| out.put(c);
        if (left) out.repeat(' ', padding);
    }
    if (capacity > 0) buffer[@min(out.length, capacity - 1)] = 0;
    if (out.length > 0x7fffffff) return -1;
    return @intCast(out.length);
}

pub export fn snprintf(buffer: [*c]u8, capacity: usize, fmt: [*:0]const u8, ...) c_int {
    var ap = @cVaStart();
    defer @cVaEnd(&ap);
    return vsnprintf(buffer, capacity, fmt, ap);
}

pub export fn vfprintf(file: *stdio.File, fmt: [*:0]const u8, ap: std.builtin.VaList) c_int {
    const needed = vsnprintf(null, 0, fmt, ap);
    if (needed < 0) return -1;
    const count: usize = @intCast(needed);
    const buffer: [*]u8 = @ptrCast(heap.malloc(count + 1) orelse {
        sys.errno = 12;
        return -1;
    });
    defer heap.free(buffer);
    if (vsnprintf(buffer, count + 1, fmt, ap) < 0) return -1;
    if (stdio.fwrite(buffer, 1, count, file) != count) return -1;
    return needed;
}

pub export fn fprintf(file: *stdio.File, fmt: [*:0]const u8, ...) c_int {
    var ap = @cVaStart();
    defer @cVaEnd(&ap);
    return vfprintf(file, fmt, ap);
}

pub export fn printf(fmt: [*:0]const u8, ...) c_int {
    var ap = @cVaStart();
    defer @cVaEnd(&ap);
    return vfprintf(stdio.stdout, fmt, ap);
}

pub export fn puts(s: [*:0]const u8) c_int {
    const len = strings.strlen(s);
    if (stdio.fwrite(s, 1, len, stdio.stdout) != len) return -1;
    if (stdio.fwrite("\n", 1, 1, stdio.stdout) != 1) return -1;
    return 0;
}

pub export fn fflush(file: ?*stdio.File) c_int {
    _ = file;
    return 0;
}
