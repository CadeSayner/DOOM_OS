BITS 32
GLOBAL _start
EXTERN main
EXTERN exit

SECTION .text
_start:
    and esp, -16
    sub esp, 8
    push argv
    push 1
    call main
    add esp, 16
    sub esp, 12
    push eax
    call exit

SECTION .data
program_name: db "program", 0
argv: dd program_name, 0
