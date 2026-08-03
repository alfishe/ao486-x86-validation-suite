;============================================================================
; MODULE: cpu/80286/protected.asm
; TIER:   RING0
; VENUE:  G
; GEN:    80386+ (uses 32-bit CR0 access)
; ORACLE: manual
; DESC:   Self-switched protected mode test. Enters PM, tests PM-only
;         instructions (VERR/VERW/LAR/LSL), returns to real mode.
;         No DPMI — does own mode switching per AGENTS.md §3.
;
; SAFETY: CLI during PM, STI after return. GDT and far pointers set up
;         before PE bit. All segment regs restored before exit.
;
; REFS:   Intel 80386 PRM §10 (mode switching)
;============================================================================

;---------------------------------------------------------------------------
pm286_init:
    ret

;---------------------------------------------------------------------------
; pm286_run — Execute protected mode tests
;---------------------------------------------------------------------------
pm286_run:
    push    bx
    push    cx
    push    dx
    push    si
    push    di

    ; Capability gate: 386+ (we use MOV CR0 for safe switching)
    mov     al, [g_cpu_type]
    cmp     al, CPU_80386
    jae     .cap_ok
    mov     al, STATUS_SKIP
    jmp     .done
.cap_ok:

    ; --- Save real-mode state ---
    mov     [pm286_save_sp], sp
    mov     ax, ss
    mov     [pm286_save_ss], ax
    mov     ax, ds
    mov     [pm286_save_ds], ax
    mov     ax, es
    mov     [pm286_save_es], ax
    sidt    [pm286_save_idt]
    mov     ax, cs
    mov     [pm286_save_cs], ax

    ; --- Build minimal GDT (3 entries) ---
    ; Entry 0: null (required)
    xor     eax, eax
    mov     dword [pm286_gdt + 0], eax
    mov     dword [pm286_gdt + 4], eax

    ; --- Compute our real-mode segment base as 32-bit linear addr ---
    ; In .COM: linear_base = CS * 16 = CS << 4
    xor     eax, eax
    mov     ax, cs
    shl     eax, 4
    mov     [pm286_lin_base], eax          ; save for GDT/GDTR setup

    ; Entry 0: null (required)
    xor     eax, eax
    mov     dword [pm286_gdt + 0], eax
    mov     dword [pm286_gdt + 4], eax

    ; Entry 1 (sel 0x08): data — base=our_segment_linear, limit=0xFFFFF, G=1
    ; Access 0x92 = P|S|data|RW,  Flags 0x4F = G|limit_hi=F
    mov     dword [pm286_gdt + 8],  0x0000FFFF
    mov     eax, [pm286_lin_base]
    mov     byte [pm286_gdt + 10], al        ; base 0-7
    mov     byte [pm286_gdt + 11], ah        ; base 8-15
    shr     eax, 16
    mov     byte [pm286_gdt + 12], al        ; base 16-23
    mov     byte [pm286_gdt + 13], 0x92       ; access byte
    mov     byte [pm286_gdt + 14], 0x0F       ; G=0, D=0(16-bit!), AVL=0, limit_hi=F
    mov     byte [pm286_gdt + 15], ah        ; base 24-31

    ; Entry 2 (sel 0x10): 16-bit code — same base, limit=0xFFFFF, G=1
    ; Access 0x9A = P|S|code|ER,  Flags 0x4F = G|0|0|limit_hi=F
    mov     dword [pm286_gdt + 16], 0x0000FFFF
    mov     eax, [pm286_lin_base]
    mov     byte [pm286_gdt + 18], al
    mov     byte [pm286_gdt + 19], ah
    shr     eax, 16
    mov     byte [pm286_gdt + 20], al
    mov     byte [pm286_gdt + 21], 0x9A
    mov     byte [pm286_gdt + 22], 0x0F       ; G=0, D=0(16-bit!), AVL=0, limit_hi=F
    mov     byte [pm286_gdt + 23], ah

    ; --- Prepare GDTR (linear address = lin_base + offset) ---
    mov     word [pm286_gdtr], 23          ; limit = 3*8-1
    mov     eax, [pm286_lin_base]
    xor     ebx, ebx
    mov     bx, pm286_gdt
    add     eax, ebx
    mov     dword [pm286_gdtr + 2], eax    ; 32-bit linear base

    ; --- Prepare far pointer for PM entry (offset + selector) ---
    mov     word [pm286_pm_entry], .pm_code
    mov     word [pm286_pm_entry + 2], 0x10    ; selector for entry 2

    ; --- Prepare far pointer for RM return ---
    mov     word [pm286_rm_ret], .rm_return
    mov     ax, [pm286_save_cs]
    mov     word [pm286_rm_ret + 2], ax

    ; --- Prepare far pointer for RM return (failure path) ---
    mov     word [pm286_rm_fail], .rm_fail
    mov     ax, [pm286_save_cs]
    mov     word [pm286_rm_fail + 2], ax

    ; ======================================================
    ; SWITCH TO PROTECTED MODE
    ; ======================================================
    cli
    lgdt    [pm286_gdtr]

    mov     eax, cr0
    or      eax, 1                        ; set PE
    mov     cr0, eax

    ; Far indirect jump to flush prefetch and load PM CS
    jmp     far [pm286_pm_entry]

    ; ======================================================
    ; PROTECTED MODE CODE — we arrive here after the far jump
    ; ======================================================
.pm_code:
    ; Load data segments with flat data selector (0x08)
    mov     ax, 0x08
    mov     ds, ax
    mov     es, ax
    mov     ss, ax
    mov     sp, 0xFFF0

    ; PM TEST 1: PE bit is set in CR0
    mov     eax, cr0
    test    eax, 1
    jz      .pm_test_fail

    ; PM TEST 2: VERR on valid data selector
    mov     ax, 0x08
    verr    ax
    jnz     .pm_test_fail

    ; PM TEST 3: VERW on valid data selector
    mov     ax, 0x08
    verw    ax
    jnz     .pm_test_fail

    ; PM TEST 4: VERR on null selector — must fail (ZF=0)
    xor     ax, ax
    verr    ax
    jz      .pm_test_fail

    ; PM TEST 5: LAR — load access rights of valid selector
    mov     ax, 0x08
    lar     bx, ax
    jnz     .pm_test_fail                ; ZF=1 on success
    ; LAR returns access byte in high byte of result
    mov     cx, bx
    shr     cx, 8
    cmp     cl, 0x92
    jne     .pm_test_fail

    ; PM TEST 6: LSL — load segment limit (16-bit result)
    ; Limit is 0xFFFFF but lsl bx only loads low 16 bits = 0xFFFF
    mov     ax, 0x08
    lsl     bx, ax
    jnz     .pm_test_fail
    cmp     bx, 0xFFFF
    jne     .pm_test_fail

    ; PM TEST 7: VERR on code selector (ER) — should be readable
    mov     ax, 0x10
    verr    ax
    jnz     .pm_test_fail

    ; PM TEST 8: VERW on code selector — NOT writable (ZF=0)
    mov     ax, 0x10
    verw    ax
    jz      .pm_test_fail

    ; ======================================================
    ; ALL PM TESTS PASSED — SWITCH BACK TO REAL MODE
    ; ======================================================
    mov     eax, cr0
    and     eax, 0x7FFFFFFE              ; clear PE and PG
    mov     cr0, eax

    ; Far indirect jump to flush and reload real-mode CS
    jmp     far [pm286_rm_ret]

    ; ======================================================
    ; PM TEST FAILURE — also switch back
    ; ======================================================
.pm_test_fail:
    mov     eax, cr0
    and     eax, 0x7FFFFFFE
    mov     cr0, eax
    jmp     far [pm286_rm_fail]

    ; ======================================================
    ; BACK IN REAL MODE — restore state
    ; ======================================================
.rm_return:
    ; CRITICAL: DS and SS still hold PM selector 0x08. In real mode
    ; that means segment 0x0080, NOT our code segment.
    ; Use mov ax,cs (no stack access) to set DS before touching data.
    mov     ax, cs
    mov     ds, ax
    ; Now DS points to our segment — restore SS:SP first for stack safety
    mov     ax, [pm286_save_ss]
    mov     ss, ax
    mov     sp, [pm286_save_sp]
    ; Now stack is correct, restore DS and ES
    mov     ax, [pm286_save_ds]
    mov     ds, ax
    mov     ax, [pm286_save_es]
    mov     es, ax
    lidt    [pm286_save_idt]
    sti
    mov     al, STATUS_PASS
    jmp     .done

.rm_fail:
    mov     ax, cs
    mov     ds, ax
    mov     ax, [pm286_save_ss]
    mov     ss, ax
    mov     sp, [pm286_save_sp]
    mov     ax, [pm286_save_ds]
    mov     ds, ax
    mov     ax, [pm286_save_es]
    mov     es, ax
    lidt    [pm286_save_idt]
    sti
    mov     al, STATUS_FAIL
    jmp     .done

.done:
    pop     di
    pop     si
    pop     dx
    pop     cx
    pop     bx
    ret

;---------------------------------------------------------------------------
pm286_cleanup:
    ret

; --- pm286 data ---
pm286_name: db '80286 Protected Mode', 0

; GDT: 3 entries × 8 bytes
pm286_gdt:   times 3 dq 0

; GDTR pseudo-descriptor (6 bytes, padded)
pm286_gdtr:  dw 0, 0, 0

; Far pointers (4 bytes each: offset + segment/selector)
pm286_pm_entry: dw 0, 0
pm286_rm_ret:   dw 0, 0
pm286_rm_fail:  dw 0, 0

; Saved real-mode state
pm286_lin_base: dd 0                  ; CS << 4 (32-bit linear base)
pm286_save_sp:  dw 0
pm286_save_ss:  dw 0
pm286_save_ds:  dw 0
pm286_save_es:  dw 0
pm286_save_cs:  dw 0
pm286_save_idt: dw 0, 0, 0
