pub const Elf32Ehdr = extern struct {
    e_ident: [16]u8,
    e_type: u16,
    e_machine: u16,
    e_version: u32,
    e_entry: u32,
    e_phoff: u32,
    e_shoff: u32,
    e_flags: u32,
    e_ehsize: u16,
    e_phentsize: u16,
    e_phnum: u16,
    e_shentsize: u16,
    e_shnum: u16,
    e_shstrndx: u16,
};

pub const ProgramHeaderType = struct {
    pub const Null: u32 = 0;
    pub const Load: u32 = 1;
    pub const Dynamic: u32 = 2;
    pub const Interp: u32 = 3;
    pub const Note: u32 = 4;
    pub const Shlib: u32 = 5;
    pub const Phdr: u32 = 6;
};

pub const Elf32Phdr = extern struct {
    p_type: u32,
    p_offset: u32,
    p_vaddr: u32,
    p_paddr: u32,
    p_filesz: u32,
    p_memsz: u32,
    p_flags: u32,
    p_align: u32,
};

pub const Module = extern struct {
    module_entry: u32,
    module_size: u32,
    module_start: u32,
    module_end: u32,
    data_start: u32,
    data_offset: u32,
    module_name: [*:0]u8,
};

pub const Elf32Shdr = extern struct {
    sh_name: u32,
    sh_type: u32,
    sh_flags: u32,
    sh_addr: u32,
    sh_offset: u32,
    sh_size: u32,
    sh_link: u32,
    sh_info: u32,
    sh_addralign: u32,
    sh_entsize: u32,
};
