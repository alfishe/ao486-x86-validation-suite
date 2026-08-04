;============================================================================
; MODULE: cpu/80386/ring0.asm
; TIER:   RING0
; VENUE:  G
; GEN:    80386+
; ORACLE: manual
; DESC:   Protected-mode RING0 tests using pm32 infrastructure. Tests CR0/CR3
;         access, descriptor protection, segment exceptions, LAR/LSL/VERR/VERW,
;         #UD delivery, and paging (identity map, #PF, A/D bits).
;
; TESTS:
;   1.  CR0 PE bit verification
;   2.  CR3 read/write
;   3.  Selector beyond GDT limit -> #GP
;   4.  Not-present descriptor load -> #NP
;   5.  LSL effective limit
;   6.  LAR access rights
;   7.  VERR/VERW type checking
;   8.  #UD on undefined opcode (UD2)
;   9.  Paging enable + identity map verification
;   10. #PF on not-present page (CR2 check)
;   11. Accessed/Dirty bits set after read/write
;
; REFS:   Intel 80386 PRM ch.6 (Protection), ch.9 (Paging), ch.10 (Mode Switch)
;============================================================================

; --- Paging test constants ---
RING0_PD_ADDR   equ 0x00080000    ; page directory physical address (4K-aligned)
RING0_PT_ADDR   equ 0x00081000    ; page table physical address (4K-aligned)
RING0_PF_PAGE   equ 0x00040000    ; page to unmap for #PF test
RING0_AD_PAGE   equ 0x00030000    ; page for A/D bit test

;---------------------------------------------------------------------------
ring0_386_init:
    ret

;---------------------------------------------------------------------------
; ring0_386_run — Entry point from runner (16-bit real mode)
;---------------------------------------------------------------------------
ring0_386_run:
    push    bp
    push    bx
    push    cx
    push    dx
    push    si
    push    di

    mov     al, [g_cpu_type]
    cmp     al, CPU_80386
    jae     .cap_ok
    mov     al, STATUS_SKIP
    jmp     .done
.cap_ok:

    mov     dword [pm32_test_callback], ring0_386_test_main
    call    pm32_enter

    ; Check failmask — 0 means all passed
    mov     ax, word [ring0_386_failmask]
    test    ax, ax
    jz      .all_pass
    mov     al, STATUS_FAIL
    jmp     .done
.all_pass:
    mov     al, STATUS_PASS

.done:
    pop     di
    pop     si
    pop     dx
    pop     cx
    pop     bx
    pop     bp
    ret

;---------------------------------------------------------------------------
ring0_386_cleanup:
    ret

;===========================================================================
; 32-BIT PROTECTED MODE TEST CODE
;===========================================================================
[BITS 32]

%macro RING0_SETFAIL 1
    bts     dword [ring0_386_failmask], (%1 - 1)
%endmacro

ring0_386_test_main:
    mov     dword [ring0_386_failmask], 0

    ; ====== TEST 1: CR0 PE bit ======
    mov     eax, cr0
    test    eax, CR0_PE
    jnz     .t1_pass
    RING0_SETFAIL 1
.t1_pass:

    ; ====== TEST 2: CR3 read/write ======
    mov     eax, cr3
    mov     [ring0_386_save_cr3], eax
    mov     eax, 0x00099000
    mov     cr3, eax
    mov     ebx, cr3
    cmp     ebx, 0x00099000
    je      .t2_pass
    RING0_SETFAIL 2
.t2_pass:
    mov     eax, [ring0_386_save_cr3]
    mov     cr3, eax

    ; ====== TEST 3: Selector beyond GDT limit -> #GP ======
    mov     dword [pm32_exc_recovery], .t3_after
    mov     byte [pm32_exc_caught], 0
    mov     ax, 0x38
    mov     es, ax
.t3_after:
    mov     ax, PM32_DATA32_SEL
    mov     es, ax
    cmp     byte [pm32_exc_caught], 1
    jne     .t3_fail
    cmp     dword [pm32_exc_vector], EXC_GP
    jne     .t3_fail
    jmp     .t3_pass
.t3_fail:
    RING0_SETFAIL 3
.t3_pass:

    ; ====== TEST 4: Not-present descriptor -> #NP ======
    and     byte [pm32_gdt + 37], 0x7F
    mov     dword [pm32_exc_recovery], .t4_after
    mov     byte [pm32_exc_caught], 0
    mov     ax, PM32_TEST_SEL1
    mov     es, ax
.t4_after:
    mov     ax, PM32_DATA32_SEL
    mov     es, ax
    or      byte [pm32_gdt + 37], 0x80
    cmp     byte [pm32_exc_caught], 1
    jne     .t4_fail
    cmp     dword [pm32_exc_vector], EXC_NP
    jne     .t4_fail
    jmp     .t4_pass
.t4_fail:
    RING0_SETFAIL 4
.t4_pass:

    ; ====== TEST 5: LSL ======
    mov     eax, PM32_TEST_SEL1
    lsl     eax, eax
    jnz     .t5_fail
    cmp     eax, 0xFFFFFFFF
    je      .t5_pass
.t5_fail:
    RING0_SETFAIL 5
.t5_pass:

    ; ====== TEST 6: LAR ======
    mov     eax, PM32_TEST_SEL1
    lar     eax, eax
    jnz     .t6_fail
    and     eax, 0x0000FF00
    cmp     eax, 0x00009200
    je      .t6_pass
.t6_fail:
    RING0_SETFAIL 6
.t6_pass:

    ; ====== TEST 7: VERR/VERW ======
    mov     ax, PM32_CODE32_SEL
    verr    ax
    jnz     .t7_fail
    mov     ax, PM32_CODE32_SEL
    verw    ax
    jz      .t7_fail
    jmp     .t7_pass
.t7_fail:
    RING0_SETFAIL 7
.t7_pass:

    ; ====== TEST 8: #UD on UD2 ======
    mov     dword [pm32_exc_recovery], .t8_after
    mov     byte [pm32_exc_caught], 0
    db      0x0F, 0x0B
.t8_after:
    cmp     byte [pm32_exc_caught], 1
    jne     .t8_fail
    cmp     dword [pm32_exc_vector], EXC_UD
    jne     .t8_fail
    jmp     .t8_pass
.t8_fail:
    RING0_SETFAIL 8
.t8_pass:

    ;==============================================================
    ; PAGING TESTS (9-11)
    ;==============================================================

    ; --- Set up identity-mapped page tables using flat DS ---
    mov     ax, PM32_TEST_SEL2          ; flat data (base=0)
    mov     ds, ax
    cld

    ; Clear page directory (4096 bytes = 1024 dwords)
    mov     edi, RING0_PD_ADDR
    mov     ecx, 1024
    xor     eax, eax
    rep     stosd

    ; PDE 0 -> page table at RING0_PT_ADDR
    mov     dword [RING0_PD_ADDR], RING0_PT_ADDR | PTE_P | PTE_RW

    ; Identity-map first 4 MB (1024 PTEs)
    mov     edi, RING0_PT_ADDR
    mov     ecx, 1024
    xor     edx, edx
.pg_fill:
    mov     eax, edx
    or      eax, PTE_P | PTE_RW
    mov     [edi], eax
    add     edi, 4
    add     edx, 0x1000
    loop    .pg_fill

    ; Switch back to regular DS
    mov     ax, PM32_DATA32_SEL
    mov     ds, ax

    ; ====== TEST 9: Enable paging + identity map ======
    mov     eax, RING0_PD_ADDR
    mov     cr3, eax
    mov     eax, cr0
    or      eax, CR0_PG
    mov     cr0, eax
    jmp     $+2                        ; flush prefetch queue

    ; Paging is now active with identity mapping.
    ; Verify by reading a known memory location.
    mov     eax, [ring0_386_save_cr3]  ; read our own data (should work)
    ; If we got here without #PF, identity map works.
    ; Also verify PG bit is set.
    mov     eax, cr0
    test    eax, CR0_PG
    jnz     .t9_pass
    RING0_SETFAIL 9
.t9_pass:

    ; ====== TEST 10: #PF on not-present page ======
    ; Unmap page at RING0_PF_PAGE using flat DS.
    mov     dword [pm32_exc_recovery], .t10_after
    mov     byte [pm32_exc_caught], 0

    mov     ax, PM32_TEST_SEL2          ; flat DS for PTE modification
    mov     ds, ax
    mov     dword [RING0_PT_ADDR + (RING0_PF_PAGE >> 12) * 4], 0  ; clear P bit
    ; Flush TLB
    mov     eax, cr3
    mov     cr3, eax

    ; Access the unmapped page — should #PF
    mov     eax, [RING0_PF_PAGE]        ; linear addr via flat DS

.t10_after:
    ; DS is flat (exception handler restored it) — switch back
    mov     ax, PM32_DATA32_SEL
    mov     ds, ax

    cmp     byte [pm32_exc_caught], 1
    jne     .t10_fail
    cmp     dword [pm32_exc_vector], EXC_PF
    jne     .t10_fail
    cmp     dword [pm32_exc_cr2], RING0_PF_PAGE
    jne     .t10_fail
    jmp     .t10_pass
.t10_fail:
    RING0_SETFAIL 10
.t10_pass:

    ; ====== TEST 11: Accessed/Dirty bits ======
    ; Use flat DS for PTE manipulation and page access.
    mov     ax, PM32_TEST_SEL2
    mov     ds, ax

    ; Clear A/D bits for the test page
    mov     dword [RING0_PT_ADDR + (RING0_AD_PAGE >> 12) * 4], RING0_AD_PAGE | PTE_P | PTE_RW
    mov     eax, cr3
    mov     cr3, eax                    ; flush TLB

    ; Read from page — should set A bit, NOT D bit
    mov     eax, [RING0_AD_PAGE]
    mov     ebx, [RING0_PT_ADDR + (RING0_AD_PAGE >> 12) * 4]
    test    ebx, PTE_A
    jz      .t11_fail
    test    ebx, PTE_D
    jnz     .t11_fail                  ; D should NOT be set after read

    ; Clear A/D bits again
    mov     dword [RING0_PT_ADDR + (RING0_AD_PAGE >> 12) * 4], RING0_AD_PAGE | PTE_P | PTE_RW
    mov     eax, cr3
    mov     cr3, eax                    ; flush TLB

    ; Write to page — should set both A and D bits
    mov     dword [RING0_AD_PAGE], 0xDEADBEEF
    mov     ebx, [RING0_PT_ADDR + (RING0_AD_PAGE >> 12) * 4]
    test    ebx, PTE_A
    jz      .t11_fail
    test    ebx, PTE_D
    jz      .t11_fail
    jmp     .t11_pass
.t11_fail:
    RING0_SETFAIL 11
.t11_pass:

    ; Switch back to regular DS
    mov     ax, PM32_DATA32_SEL
    mov     ds, ax

    ; --- Disable paging before returning ---
    mov     eax, cr0
    and     eax, 0x7FFFFFFF             ; clear PG
    mov     cr0, eax
    jmp     $+2                        ; flush prefetch

    ret

;===========================================================================
; DATA
;===========================================================================
[BITS 16]

ring0_386_name:      db '80386 Ring0 PM Tests', 0
ring0_386_failmask:  dd 0
ring0_386_save_cr3:  dd 0
