global switch_context

switch_context:
; eax is the pointer to where to save the old stack and, edx has the new stack pointer
    mov eax, [esp + 4]
    mov edx, [esp + 8]
    push ebp
    push ebx
    push esi
    push edi
    mov [eax], esp ; ; pretty cool because eip will still be in here allowing all this to work
    mov esp, edx
    pop edi
    pop esi
    pop ebx
    pop ebp
    ret 

global irq_save
global irq_restore

; uint32_t irq_save(void): returns the old EFLAGS, then disables interrupts
irq_save:
    pushfd
    pop eax          ; eax = old EFLAGS (return value)
    cli
    ret

; void irq_restore(uint32_t flags): puts EFLAGS back, which re-enables interrupts only if they were on before
irq_restore:
    mov eax, [esp+4]
    push eax
    popfd
    ret