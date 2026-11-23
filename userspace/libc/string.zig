const heap = @import("memory.zig");

pub export fn memcpy(dst: [*]u8, src: [*]const u8, n: usize) [*]u8 {
    for (0..n) |i| dst[i] = src[i];
    return dst;
}

pub export fn memmove(dst: [*]u8, src: [*]const u8, n: usize) [*]u8 {
    if (@intFromPtr(dst) > @intFromPtr(src)) {
        var i = n;
        while (i > 0) {
            i -= 1;
            dst[i] = src[i];
        }
    } else {
        for (0..n) |i| dst[i] = src[i];
    }
    return dst;
}

pub export fn memset(dst: [*]u8, value: c_int, n: usize) [*]u8 {
    const bytes: [*]volatile u8 = dst;
    for (0..n) |i| bytes[i] = @truncate(@as(c_uint, @bitCast(value)));
    return dst;
}

pub export fn strlen(s: [*:0]const u8) usize {
    var i: usize = 0;
    while (s[i] != 0) : (i += 1) {}
    return i;
}

pub export fn strcmp(a: [*:0]const u8, b: [*:0]const u8) c_int {
    var i: usize = 0;
    while (a[i] != 0 and a[i] == b[i]) : (i += 1) {}
    return @as(c_int, a[i]) - @as(c_int, b[i]);
}

pub export fn strncmp(a: [*:0]const u8, b: [*:0]const u8, n: usize) c_int {
    var i: usize = 0;
    while (i < n) : (i += 1) {
        if (a[i] != b[i] or a[i] == 0) return @as(c_int, a[i]) - @as(c_int, b[i]);
    }
    return 0;
}

pub export fn tolower(c: c_int) c_int {
    return if (c >= 'A' and c <= 'Z') c + 32 else c;
}

pub export fn toupper(c: c_int) c_int {
    return if (c >= 'a' and c <= 'z') c - 32 else c;
}

pub export fn isspace(c: c_int) c_int {
    return @intFromBool(c == ' ' or (c >= 9 and c <= 13));
}

pub export fn strncasecmp(a: [*:0]const u8, b: [*:0]const u8, n: usize) c_int {
    for (0..n) |i| {
        const x = tolower(a[i]);
        const y = tolower(b[i]);
        if (x != y or a[i] == 0) return x - y;
    }
    return 0;
}

pub export fn strcasecmp(a: [*:0]const u8, b: [*:0]const u8) c_int {
    return strncasecmp(a, b, @max(strlen(a), strlen(b)) + 1);
}

pub export fn strncpy(dst: [*]u8, src: [*:0]const u8, n: usize) [*]u8 {
    var ended = false;
    for (0..n) |i| {
        if (!ended and src[i] == 0) ended = true;
        dst[i] = if (ended) 0 else src[i];
    }
    return dst;
}

pub export fn strdup(src: [*:0]const u8) ?[*:0]u8 {
    const n = strlen(src) + 1;
    const dst: [*]u8 = @ptrCast(heap.malloc(n) orelse return null);
    _ = memcpy(dst, src, n);
    return @ptrCast(dst);
}

pub export fn strrchr(src: [*:0]const u8, c: c_int) ?[*:0]const u8 {
    const target: u8 = @truncate(@as(c_uint, @bitCast(c)));
    var result: ?[*:0]const u8 = null;
    var i: usize = 0;
    while (true) : (i += 1) {
        if (src[i] == target) result = @ptrCast(src + i);
        if (src[i] == 0) return result;
    }
}

pub export fn strstr(haystack: [*:0]const u8, needle: [*:0]const u8) ?[*:0]const u8 {
    const n = strlen(needle);
    var i: usize = 0;
    while (true) : (i += 1) {
        if (strncmp(@ptrCast(haystack + i), needle, n) == 0) return @ptrCast(haystack + i);
        if (haystack[i] == 0) return null;
    }
}

pub export fn parse_octal(s: [*]const u8, n: usize) u32 {
    var result: u32 = 0;
    for (0..n) |i| {
        if (s[i] < '0' or s[i] > '7') break;
        result = result *% 8 +% (s[i] - '0');
    }
    return result;
}
