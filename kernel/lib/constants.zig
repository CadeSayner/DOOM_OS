pub const max_physical_frames = 32768;
pub const kernel_offset = 0xC0000000;
pub const frame_size = 4096; // Assuming a frame size of 4KB

/// Converts a physical address to a higher-half virtual address
pub fn physToVirt(phys_addr: u32) u32 {
    return phys_addr + kernel_offset;
}

pub fn virtToPhys(virt_addr: u32) u32 {
    return virt_addr - kernel_offset;
}  

/// Helper to cast a physical address directly to a typed pointer
pub fn p2v(comptime T: type, phys_addr: u32) *T {
    return @ptrFromInt(phys_addr + kernel_offset);
}