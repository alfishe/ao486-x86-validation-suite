;============================================================================
; MODULE: core/pm32.asm
; TIER:   RING0 (infrastructure — included by all RING0 test modules)
; VENUE:  G
; GEN:    80386+ (uses MOV CR0, 32-bit PM)
; ORACLE: manual
; DESC:   Shared 32-bit protected-mode infrastructure for all RING0 tests.
;
;         Provides reusable PM entry/exit, GDT/IDT construction, and a
;         generic exception handler that records vector/error/CR2 and
;         redirects EIP to a caller-specified recovery address.
;
;         Usage from a test module:
;           1. Set pm32_test_callback to your 32-bit test function
;           2. Call pm32_enter (never returns directly — goes through PM)
;           3. After PM excursion, returns to the instruction after call
;           4. Check pm32_result for PASS/FAIL
;
;         In 32-bit PM test code:
;           - Set pm32_exc_recovery to a label after the faulting instruction
;           - Clear pm32_exc_caught
;           - Execute the potentially faulting instruction
;           - Check pm32_exc_caught (1=exception fired, 0=no exception)
;           - Check pm32_exc_vector, pm32_exc_error, pm32_exc_cr2 for details
;
; REFS:   Intel 80386 PRM §10 (mode switching);
;         adding-tests.md "RING0 Self-Switching PM Pattern";
;         specs/80186-286/286-pm-infra.md (GDT/IDT layout)
;============================================================================

; --- Selector constants (available to all RING0 modules) ---
PM32_CODE32_SEL   equ 0x08    ; GDT entry 1: 32-bit code, DPL=0
PM32_DATA32_SEL   equ 0x10    ; GDT entry 2: 32-bit data, DPL=0
PM32_CODE16_SEL   equ 0x18    ; GDT entry 3: 16-bit code, DPL=0
PM32_TEST_SEL1    equ 0x20    ; GDT entry 4: test descriptor (modifiable)
PM32_TEST_SEL2    equ 0x28    ; GDT entry 5: test descriptor (modifiable)

; --- PM stack location (safe area in conventional memory) ---
PM32_STACK_TOP    equ 0x00090000

;---------------------------------------------------------------------------
pm32_init:
    ret

;===========================================================================
; pm32_enter — Enter 32-bit protected mode, run test callback, return to RM
; IN:   [pm32_test_callback] = 32-bit offset of test function
; OUT:  [pm32_result] = STATUS_PASS or STATUS_FAIL
; NOTE: Never returns via its own ret — exits through pm32_rm_done which
;       restores the original stack and rets to the caller.
;===========================================================================
pm32_enter:
    ; --- Save real-mode state inline (SP has only the return address) ---
    mov     [pm32_save_sp], sp
    mov     ax, ss
    mov     [pm32_save_ss], ax
    mov     ax, ds
    mov     [pm32_save_ds], ax
    mov     ax, es
    mov     [pm32_save_es], ax
    sidt    [pm32_save_idt]
    mov     ax, cs
    mov     [pm32_save_cs], ax

    ; --- Build GDT and IDT ---
    call    pm32_build_gdt
    call    pm32_build_idt

    ; --- Set up far pointer for PM entry ---
    mov     word [pm32_far_entry], pm32_pm_entry
    mov     word [pm32_far_entry+2], PM32_CODE32_SEL

    ; --- Set up far pointer for RM return ---
    mov     word [pm32_far_rmret], pm32_rm_done
    mov     ax, cs
    mov     word [pm32_far_rmret+2], ax

    ; --- Initialize result and exception state ---
    mov     dword [pm32_result], STATUS_PASS
    mov     byte [pm32_exc_caught], 0

    ; --- Switch to protected mode ---
    cli
    lgdt    [pm32_gdtr]
    mov     eax, cr0
    or      eax, CR0_PE
    mov     cr0, eax

    ; Far jump to flush prefetch and load 32-bit PM CS
    jmp     far [pm32_far_entry]
    ; --- Never reaches here ---

;===========================================================================
; pm32_build_gdt — Construct GDT at runtime (base = CS<<4)
;===========================================================================
pm32_build_gdt:
    push    eax
    push    ebx

    ; Compute linear base of our code segment
    xor     eax, eax
    mov     ax, cs
    shl     eax, 4
    mov     [pm32_lin_base], eax

    ; Entry 0 (0x00): null descriptor
    xor     eax, eax
    mov     dword [pm32_gdt + 0], eax
    mov     dword [pm32_gdt + 4], eax

    ; Entry 1 (0x08): 32-bit code, DPL=0, G=1, D=1, limit=0xFFFFF (4GB)
    mov     dword [pm32_gdt + 8], 0x0000FFFF     ; limit_lo=0xFFFF, base_lo=0
    mov     eax, [pm32_lin_base]
    mov     byte [pm32_gdt + 10], al              ; base 0-7
    mov     byte [pm32_gdt + 11], ah              ; base 8-15
    shr     eax, 16
    mov     byte [pm32_gdt + 12], al              ; base 16-23
    mov     byte [pm32_gdt + 13], 0x9A            ; P=1,DPL=0,S=1,code ER
    mov     byte [pm32_gdt + 14], 0xCF            ; G=1,D=1,limit_hi=0xF
    mov     byte [pm32_gdt + 15], ah              ; base 24-31

    ; Entry 2 (0x10): 32-bit data, DPL=0, G=1, D=1, limit=0xFFFFF (4GB)
    mov     dword [pm32_gdt + 16], 0x0000FFFF
    mov     eax, [pm32_lin_base]
    mov     byte [pm32_gdt + 18], al
    mov     byte [pm32_gdt + 19], ah
    shr     eax, 16
    mov     byte [pm32_gdt + 20], al
    mov     byte [pm32_gdt + 21], 0x92            ; P=1,DPL=0,S=1,data RW
    mov     byte [pm32_gdt + 22], 0xCF            ; G=1,D=1
    mov     byte [pm32_gdt + 23], ah

    ; Entry 3 (0x18): 16-bit code, DPL=0, G=0, D=0, limit=0xFFFFF (1MB)
    mov     dword [pm32_gdt + 24], 0x0000FFFF
    mov     eax, [pm32_lin_base]
    mov     byte [pm32_gdt + 26], al
    mov     byte [pm32_gdt + 27], ah
    shr     eax, 16
    mov     byte [pm32_gdt + 28], al
    mov     byte [pm32_gdt + 29], 0x9A            ; P=1,DPL=0,S=1,code ER
    mov     byte [pm32_gdt + 30], 0x0F            ; G=0,D=0,limit_hi=0xF
    mov     byte [pm32_gdt + 31], ah

    ; Entry 4 (0x20): test descriptor — copy of flat data (modifiable at runtime)
    mov     dword [pm32_gdt + 32], 0x0000FFFF
    mov     eax, [pm32_lin_base]
    mov     byte [pm32_gdt + 34], al
    mov     byte [pm32_gdt + 35], ah
    shr     eax, 16
    mov     byte [pm32_gdt + 36], al
    mov     byte [pm32_gdt + 37], 0x92            ; P=1,DPL=0,data RW
    mov     byte [pm32_gdt + 38], 0xCF            ; G=1,D=1
    mov     byte [pm32_gdt + 39], ah

    ; Entry 5 (0x28): flat data segment (base=0, limit=4GB, G=1, D=1)
    ; Used by paging tests to access physical memory at known addresses.
    mov     dword [pm32_gdt + 40], 0x0000FFFF    ; limit_lo=0xFFFF, base_lo=0
    mov     byte [pm32_gdt + 42], 0              ; base 0-7
    mov     byte [pm32_gdt + 43], 0              ; base 8-15
    mov     byte [pm32_gdt + 44], 0              ; base 16-23
    mov     byte [pm32_gdt + 45], 0x92            ; P=1,DPL=0,S=1,data RW
    mov     byte [pm32_gdt + 46], 0xCF            ; G=1,D=1,limit_hi=0xF
    mov     byte [pm32_gdt + 47], 0              ; base 24-31

    ; GDTR: limit=6*8-1=47, base=linear addr of GDT
    mov     word [pm32_gdtr], 47
    mov     eax, [pm32_lin_base]
    xor     ebx, ebx
    mov     bx, pm32_gdt
    add     eax, ebx
    mov     dword [pm32_gdtr + 2], eax

    pop     ebx
    pop     eax
    ret

;===========================================================================
; pm32_build_idt — Construct IDT with exception handlers
;===========================================================================
pm32_build_idt:
    push    eax
    push    ecx
    push    edi

    ; Fill all 32 entries with default handler
    mov     ecx, 32
    mov     edi, pm32_idt
.fill_loop:
    mov     word [edi], pm32_exc_default          ; offset_lo
    mov     word [edi+2], PM32_CODE32_SEL          ; selector
    mov     byte [edi+4], 0                        ; reserved
    mov     byte [edi+5], 0x8E                     ; P=1,DPL=0,386 int gate
    mov     word [edi+6], 0                        ; offset_hi
    add     edi, 8
    loop    .fill_loop

    ; Override with specific stubs for known exception vectors
    mov     word [pm32_idt + 0*8], pm32_exc_0      ; #DE
    mov     word [pm32_idt + 6*8], pm32_exc_6      ; #UD
    mov     word [pm32_idt + 8*8], pm32_exc_8      ; #DF
    mov     word [pm32_idt + 10*8], pm32_exc_10    ; #TS
    mov     word [pm32_idt + 11*8], pm32_exc_11    ; #NP
    mov     word [pm32_idt + 12*8], pm32_exc_12    ; #SS
    mov     word [pm32_idt + 13*8], pm32_exc_13    ; #GP
    mov     word [pm32_idt + 14*8], pm32_exc_14    ; #PF
    mov     word [pm32_idt + 17*8], pm32_exc_17    ; #AC

    ; IDTR: limit=32*8-1=255, base=linear addr of IDT
    mov     word [pm32_idtr], 255
    mov     eax, [pm32_lin_base]
    xor     ecx, ecx
    mov     cx, pm32_idt
    add     eax, ecx
    mov     dword [pm32_idtr + 2], eax

    pop     edi
    pop     ecx
    pop     eax
    ret

;===========================================================================
; 32-BIT PROTECTED MODE CODE
;===========================================================================
[BITS 32]

pm32_pm_entry:
    ; Load data segment registers
    mov     ax, PM32_DATA32_SEL
    mov     ds, ax
    mov     es, ax
    mov     ss, ax
    mov     esp, PM32_STACK_TOP

    ; Load PM IDT
    lidt    [pm32_idtr]

    ; Set default exception recovery to the post-callback exit
    mov     dword [pm32_exc_recovery], pm32_after_callback

    ; Call the test callback
    call    [pm32_test_callback]

pm32_after_callback:
    ; --- Exit PM (normal path) ---

    ; Switch to 16-bit code segment for safe RM transition
    jmp     PM32_CODE16_SEL:pm32_rm_transition

;===========================================================================
; Exception stubs — push vector number, jump to common handler
; Vectors WITH error code (CPU pushes it): 8,10,11,12,13,14,17
; Vectors WITHOUT error code: 0,6 and others (stub pushes dummy 0)
;===========================================================================

%macro PM32_STUB_ERR 1     ; vector with error code
pm32_exc_%1:
    push    byte %1
    jmp     pm32_exc_common
%endmacro

%macro PM32_STUB_NOERR 1   ; vector without error code
pm32_exc_%1:
    push    byte 0          ; dummy error code
    push    byte %1
    jmp     pm32_exc_common
%endmacro

PM32_STUB_NOERR 0          ; #DE - Divide Error
PM32_STUB_NOERR 6          ; #UD - Invalid Opcode
PM32_STUB_ERR   8          ; #DF - Double Fault
PM32_STUB_ERR   10         ; #TS - Invalid TSS
PM32_STUB_ERR   11         ; #NP - Segment Not Present
PM32_STUB_ERR   12         ; #SS - Stack Fault
PM32_STUB_ERR   13         ; #GP - General Protection
PM32_STUB_ERR   14         ; #PF - Page Fault
PM32_STUB_ERR   17         ; #AC - Alignment Check

pm32_exc_default:
    ; Default handler for unexpected vectors
    push    byte 0           ; dummy error code
    push    byte 0x7E        ; marker: unexpected vector (0x7E > 17)
    jmp     pm32_exc_common

;===========================================================================
; pm32_exc_common — Generic exception handler
;
; Stack on entry (top to bottom):
;   vector, error_code, EIP, CS, EFLAGS
;
; Records exception info, then redirects EIP to pm32_exc_recovery.
;===========================================================================
pm32_exc_common:
    push    eax
    push    ds                         ; save caller's DS (may be flat)
    ; Stack: ds(0), eax(4), vector(8), error(12), EIP(16), CS(20), EFLAGS(24)

    ; Ensure DS points to our data segment (caller may have flat DS)
    mov     ax, PM32_DATA32_SEL
    mov     ds, ax

    mov     byte [pm32_exc_caught], 1
    mov     eax, [esp+8]                ; vector number
    mov     [pm32_exc_vector], eax
    mov     eax, [esp+12]               ; error code
    mov     [pm32_exc_error], eax
    mov     eax, cr2                    ; save CR2 (meaningful for #PF)
    mov     [pm32_exc_cr2], eax

    ; Redirect saved EIP to recovery address
    mov     eax, [pm32_exc_recovery]
    mov     [esp+16], eax               ; overwrite saved EIP

    pop     ds                          ; restore caller's DS
    pop     eax                         ; restore caller's EAX
    add     esp, 8                      ; remove vector + error code
    iretd                                ; pop EIP(recovery), CS, EFLAGS

;===========================================================================
; 16-BIT CODE — PM→RM transition
;===========================================================================
[BITS 16]

pm32_rm_transition:
    ; Clear PE and PG bits
    mov     eax, cr0
    and     eax, 0x7FFFFFFE
    mov     cr0, eax

    ; Far jump to reload real-mode CS (flushes prefetch)
    jmp     far [pm32_far_rmret]

pm32_rm_done:
    ; --- Restore real-mode state ---
    ; CRITICAL: DS/SS still hold PM selectors. Use CS to get our segment.
    mov     ax, cs
    mov     ds, ax

    ; Restore SS:SP first (stack safety)
    mov     ax, [pm32_save_ss]
    mov     ss, ax
    mov     sp, [pm32_save_sp]

    ; Restore DS, ES
    mov     ax, [pm32_save_ds]
    mov     ds, ax
    mov     ax, [pm32_save_es]
    mov     es, ax

    ; Restore real-mode IDT
    lidt    [pm32_save_idt]
    sti

    ; Return to original caller (ret addr is on restored stack)
    ret

;---------------------------------------------------------------------------
pm32_cleanup:
    ret

;===========================================================================
; DATA SECTION
;===========================================================================

pm32_name:  db 'PM32 Infrastructure', 0

; GDT: 6 entries x 8 bytes = 48 bytes
pm32_gdt:   times 6 dq 0

; GDTR pseudo-descriptor (6 bytes)
pm32_gdtr:  dw 0
            dd 0

; IDT: 32 entries x 8 bytes = 256 bytes
pm32_idt:   times 32 dq 0

; IDTR pseudo-descriptor (6 bytes)
pm32_idtr:  dw 0
            dd 0

; Linear base address (CS << 4)
pm32_lin_base: dd 0

; Far pointers (offset + selector, 4 bytes each for 16-bit far jump)
pm32_far_entry: dw 0, 0
pm32_far_rmret: dw 0, 0

; Saved real-mode state
pm32_save_sp:  dw 0
pm32_save_ss:  dw 0
pm32_save_ds:  dw 0
pm32_save_es:  dw 0
pm32_save_cs:  dw 0
pm32_save_idt: dw 0, 0, 0

; Exception state
pm32_exc_caught:    dd 0
pm32_exc_vector:    dd 0
pm32_exc_error:     dd 0
pm32_exc_cr2:       dd 0
pm32_exc_recovery:  dd 0

; Test callback (32-bit offset within code segment)
pm32_test_callback: dd 0

; Result (STATUS_PASS or STATUS_FAIL)
pm32_result: dd 0
