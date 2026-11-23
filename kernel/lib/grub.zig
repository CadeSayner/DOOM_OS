pub const MultibootAoutSymbolTable = extern struct {
    tabSize: u32,
    strSize: u32,
    address: u32,
    reserved: u32,
};

pub const MultibootElfSectionHeaderTable = extern struct {
    num: u32,
    size: u32,
    addr: u32,
    shndx: u32,
};

pub const MultibootSymbolUnion = extern union {
    aout_sym: MultibootAoutSymbolTable,
    elf_sec: MultibootElfSectionHeaderTable,
};

pub const MultibootInfo = extern struct {
    flags: u32,
    mem_lower: u32,
    mem_upper: u32,
    boot_device: u32,

    cmdline: u32,
    mods_count: u32,
    mods_addr: u32,

    u: MultibootSymbolUnion,

    mmap_length: u32,
    mmap_addr: u32,

    drives_length: u32,
    drives_addr: u32,

    config_table: u32,
    boot_loader_name: u32,

    apm_table: u32,

    vbe_control_info: u32,
    vbe_mode_info: u32,
    vbe_mode: u16,
    vbe_interface_seg: u16,
    vbe_interface_off: u16,
    vbe_interface_len: u16,

    framebuffer_addr: u64,
    framebuffer_pitch: u32,
    framebuffer_width: u32,
    framebuffer_height: u32,
    framebuffer_bpp: u8,
    framebuffer_type: u8,
};

pub const MultibootMmapEntry = packed struct {
    size: u32,
    addr_low: u32,
    addr_high: u32,
    len_low: u32,
    len_high: u32,
    typ: u32,
};

pub const MultibootMemoryType = struct {
    pub const Available: u32 = 1;
    pub const Reserved: u32 = 2;
    pub const AcpiReclaimable: u32 = 3;
    pub const Nvs: u32 = 4;
    pub const BadRam: u32 = 5;
};

pub const Module = extern struct {
    module_start: u32,
    module_end: u32,
    module_name: u32,
    reserved: u32,
};
