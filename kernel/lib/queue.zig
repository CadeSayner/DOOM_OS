pub fn Queue(comptime capacity: usize, T: type) type {
    return struct {
        const Self = @This();
        buf: [capacity]?T = .{null} ** capacity,
        head: usize = 0,
        tail: usize = 0,
        len: usize = 0,

        pub fn enqueue(self: *Self, object: T) !void {
            if (self.len == capacity) return error.QueueFull;
            self.buf[self.tail] = object;
            self.tail = self.tail + 1 % capacity;
            self.len += 1;
        }

        pub fn dequeue(self: *Self) ?T {
            if (self.len == 0) return null;
            const object: ?T = self.buf[self.head];
            self.head = (self.head + 1) % capacity;
            self.len -= 1;
            return object;
        }
    };
}
