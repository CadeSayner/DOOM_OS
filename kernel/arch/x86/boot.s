MBOOT_PAGE_ALIGN EQU 1<<0
MBOOT_MEM_INFO EQU 1<<1
MBOOT_USE_GFX EQU 1<<2

MBOOT_MAGIC EQU 0x1BADB002
MBOOT_FLAGS EQU MBOOT_PAGE_ALIGN | MBOOT_MEM_INFO | MBOOT_USE_GFX
MBOOT_CHECKSUM EQU -(MBOOT_MAGIC + MBOOT_FLAGS)

%macro page_table 1
    DD (%1 << 22) | 10000011b
%endmacro

section .multiboot
ALIGN 4
    DD MBOOT_MAGIC
    DD MBOOT_FLAGS
    DD MBOOT_CHECKSUM
    DD 0, 0, 0, 0, 0

    ; graphics initialisations
    DD 0
    DD 800 ; width
    DD 600 ; height
    DD 32

section .bss
ALIGN 16

global stack_top
stack_bottom:
    RESB 512 * 1024
stack_top:

section .boot
global _start ; Make the symbol accessible to other files

_start:
    MOV ecx, (initial_page_dir - 0xC0000000) ; get the physical address of the pd
    MOV cr3, ecx

    ; Turn on PAE
    MOV ecx, cr4
    OR ecx, 0x10
    MOV cr4, ecx

    ; Turn on paging
    MOV ecx, cr0
    OR ecx, 0x80000000
    MOV cr0, ecx

    JMP higher_half

section .text
higher_half:
    MOV esp, stack_top
    PUSH ebx
    PUSH eax
    XOR ebp, ebp
    extern kmain
    CALL kmain

halt:
    hlt
    JMP halt

section .data
align 4096
global initial_page_dir
initial_page_dir:
    page_table 0
    page_table 1
    page_table 2
    page_table 3
    TIMES 768-4 DD 0

    %assign i 0
    %rep 1008 - 768
        page_table i
        %assign i i+1
    %endrep

    %assign p 1008
    %rep 8
        page_table p
        %assign p p+1
    %endrep

    %assign i 0
    %rep 1024 - 1016
        page_table i
        %assign i i+1
    %endrep