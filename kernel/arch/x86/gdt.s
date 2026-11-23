global gdt_flush
global switch_to_user_mode_process
global load_page_table
global tss_flush

gdt_flush:
    MOV eax, [esp+4]
    LGDT [eax]
    MOV eax, 0x10 ; offset in bytes at which the code segment descriptor resides in the GDT
    MOV ds, eax
    MOV es, eax
    MOV fs, eax
    MOV gs, eax
    MOV ss, eax
    JMP 0x08:.flush

.flush:
    RET

switch_to_user_mode_process:
    MOV ebx, [esp+4]
    AND esp, 0xFFFFFFF0 ; align stack to 16 bytes
    CLI
    MOV ax, 0x23
    MOV ds, eax
    MOV es, eax
    MOV fs, eax
    MOV gs, eax

    PUSH dword 0x23
    PUSH dword (0xB0000000 + 8092)
    PUSHFD
    OR dword [esp], 0x200
    PUSH dword 0x1B
    PUSH ebx
    iret

load_page_table:
    MOV eax, [esp+4]
    MOV cr3, eax
    RET

tss_flush:
    MOV ax, 0x28
    LTR ax
    RET