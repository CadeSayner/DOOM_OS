const Grub = @import("../lib/grub.zig");

const max_physical_frames = 32768;
const kernel_offset = 0xC0000000;
const frame_size = 4096; // Assuming a frame size of 4KB

pub const FrameAllocator = struct {
    const Self = @This();
    var mmap: [max_physical_frames]bool = [_]bool{false} ** max_physical_frames;
    initial_allocation_frame: u32 = undefined,

    pub fn init(initial_frame: u32) Self {
        return .{
            .initial_allocation_frame = initial_frame,
        };
    }

    pub fn allocateFrame(self: *Self) u32 {
        for (&Self.mmap, 0..) |*page, frame_no| {
            if (!page.*) {
                page.* = true;
                return self.frameNoToKernelVirtualAddress(@intCast(frame_no));
            }
        }
        @panic("No free frames available");
    }

    pub fn allocateConsecutiveFrames(self: *Self, count: u32) u32 {
        if (count == 0) @panic("Cannot allocate 0 frames");

        var run: u32 = 0;
        var start: usize = 0;

        for (Self.mmap, 0..) |allocated, i| {
            if (allocated) {
                run = 0;
                start = i + 1;
                continue;
            }
            run += 1;
            if (run == count) {
                for (start..start + count) |f| Self.mmap[f] = true;
                return self.frameNoToKernelVirtualAddress(@intCast(start));
            }
        }
        @panic("No sufficient consecutive frames available");
    }

    pub fn freeFrame(frameNo: u32) void {
        Self.mmap[@intCast(frameNo)] = false;
    }

    pub fn freeVaddrFrame(self: *Self, vaddr: u32) void {
        const frame_no = self.kernelVirtualAddressToFrameNo(vaddr);
        Self.mmap[@intCast(frame_no)] = false;
    }

    pub fn freeVaddrFrames(self: *Self, vaddr: u32, count: u32) void {
        const first: usize = self.kernelVirtualAddressToFrameNo(vaddr);
        for (first..first + count) |f| Self.mmap[f] = false;
    }

    fn kernelVirtualAddressToFrameNo(self: *const Self, vaddr: u32) u32 {
        return @intCast((vaddr - kernel_offset) / frame_size - self.initial_allocation_frame);
    }

    fn frameNoToKernelVirtualAddress(self: *const Self, frameNo: u32) u32 {
        return self.virtualAddressToKernelAddress(self.frameNumberToVaddr(self.initial_allocation_frame + frameNo));
    }

    fn virtualAddressToKernelAddress(_: *const Self, vaddr: u32) u32 {
        return kernel_offset + vaddr;
    }

    fn frameNumberToVaddr(_: *const Self, frameNo: u32) u32 {
        return @intCast(frameNo * frame_size);
    }
};
