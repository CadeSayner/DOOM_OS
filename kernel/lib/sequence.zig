pub fn SequenceBuffer(comptime T: type, comptime capacity: usize) type {
    comptime {
        if (capacity == 0 or (capacity & (capacity - 1)) != 0) {
            @compileError("capacity must be a non-zero power of two");
        }
    }

    return struct {
        const Self = @This();
        const mask: u64 = capacity - 1;

        items: [capacity]T = undefined,
        next_seq: u64 = 0,

        pub fn push(self: *Self, item: T) void {
            const idx: usize = @intCast(self.next_seq & mask);
            self.items[idx] = item;
            self.next_seq += 1;
        }

        pub fn readOldest(self: *const Self) T {
            return self.items[@intCast(self.oldestSeq() & mask)];
        }

        pub fn oldestSeq(self: *const Self) u64 {
            return if (self.next_seq > capacity) self.next_seq - capacity else 0;
        }

        pub fn readAt(self: *const Self, seq: u64, out: *T) bool {
            if (seq < self.oldestSeq() or seq >= self.next_seq) {
                return false;
            }
            const idx: usize = @intCast(seq & mask);
            out.* = self.items[idx];
            return true;
        }
    };
}
