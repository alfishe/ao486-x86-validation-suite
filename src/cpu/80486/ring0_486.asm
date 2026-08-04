;============================================================================
; MODULE: cpu/80486/ring0_486.asm
; TIER:   RING0
; VENUE:  G
; GEN:    80486+
; ORACLE: manual
; DESC:   80486-specific protected-mode RING0 tests using pm32 infrastructure.
;         Tests INVD/WBINVD, INVLPG (TLB invalidate), CR0.WP (write protect),
;         CR0.AM + #AC (alignment check), and CR0.CD/NW (cache control).
;
; TESTS:
;   1. INVD — cache invalidate instruction recognition (no #UD, no exception)
;   2. WBINVD — writeback + invalidate instruction recognition (no #UD, no exception)
;   3. INVLPG — single-page TLB invalidate instruction recognition (no #UD)
;         NOTE: Full TLB-flush verification requires 86Box; DOSBox-X may not
;         implement single-page TLB invalidation correctly.
;   4. CR0.WP — write-protect: ring 0 write to read-only page -> #PF when WP=1,
;         succeeds when WP=0
;   5. CR0.AM + EFLAGS.AC — bit set/clear/readback verification
;         NOTE: Actual #AC delivery requires 86Box; DOSBox-X may not implement it.
;   6. CR0.CD/NW — cache control bits set/clear/readback verification
;
; REFS:   Intel 80486 PRM ch.4 (Cache), ch.5 (Paging), ch.8 (Protection);
;         Intel SDM Vol.3 ch.2 (INVLPG, INVD, WBINVD), ch.3 (#AC)
;============================================================================

; --- Page addresses for paging-dependent tests ---
; Reuse the same physical addresses as ring0.asm (sequential PM excursions)
RING0_486_PF_PAGE  equ 0x00050000    ; page for INVLPG test
RING0_486_RO_PAGE  equ 0x00060000    ; read-only page for WP test

;---------------------------------------------------------------------------
ring0_486_init:
    ret

;---------------------------------------------------------------------------
; ring0_486_run — Entry point from runner (16-bit real mode)
;---------------------------------------------------------------------------
ring0_486_run:
    push    bp
    push    bx
    push    cx
    push    dx
    push    si
    push    di

    mov     al, [g_cpu_type]
    cmp     al, CPU_80486
    jae     .cap_ok
    mov     al, STATUS_SKIP
    jmp     .done
.cap_ok:

    mov     dword [pm32_test_callback], ring0_486_test_main
    call    pm32_enter

    mov     ax, word [ring0_486_failmask]
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
ring0_486_cleanup:
    ret

;===========================================================================
; 32-BIT PROTECTED MODE TEST CODE
;===========================================================================
[BITS 32]

%macro RING0_486_SETFAIL 1
    bts     dword [ring0_486_failmask], (%1 - 1)
%endmacro

ring0_486_test_main:
    mov     dword [ring0_486_failmask], 0
    mov     eax, cr0
    mov     [ring0_486_save_cr0], eax

    ; ====== TEST 1: INVD ======
    ; INVD invalidates the entire internal cache. On emulators it is
    ; typically a no-op, but it must not cause #UD or hang.
    ; Ref: Intel SDM Vol.2 — INVD is privileged (CPL 0).
    mov     dword [pm32_exc_recovery], .t1_after
    mov     byte [pm32_exc_caught], 0
    invd
.t1_after:
    cmp     byte [pm32_exc_caught], 0
    je      .t1_pass                   ; no exception = good
    RING0_486_SETFAIL 1
.t1_pass:

    ; ====== TEST 2: WBINVD ======
    ; WBINVD writes back modified cache lines then invalidates.
    ; Like INVD, must be a clean no-op on emulators.
    mov     dword [pm32_exc_recovery], .t2_after
    mov     byte [pm32_exc_caught], 0
    wbinvd
.t2_after:
    cmp     byte [pm32_exc_caught], 0
    je      .t2_pass
    RING0_486_SETFAIL 2
.t2_pass:

    ;==============================================================
    ; PAGING-DEPENDENT TESTS (3-4)
    ;==============================================================

    ; --- Set up identity-mapped page tables ---
    mov     ax, PM32_TEST_SEL2          ; flat data (base=0)
    mov     ds, ax
    cld

    ; Clear page directory
    mov     edi, RING0_PD_ADDR
    mov     ecx, 1024
    xor     eax, eax
    rep     stosd

    ; PDE 0 -> page table
    mov     dword [RING0_PD_ADDR], RING0_PT_ADDR | PTE_P | PTE_RW

    ; Identity-map first 4MB, but mark RING0_486_RO_PAGE as read-only
    mov     edi, RING0_PT_ADDR
    mov     ecx, 1024
    xor     edx, edx
.pg_fill:
    mov     eax, edx
    or      eax, PTE_P | PTE_RW
    ; Make the RO test page read-only (clear RW bit)
    cmp     edx, RING0_486_RO_PAGE
    jne     .not_ro
    and     eax, ~PTE_RW               ; clear RW for read-only page
.not_ro:
    mov     [edi], eax
    add     edi, 4
    add     edx, 0x1000
    loop    .pg_fill

    mov     ax, PM32_DATA32_SEL
    mov     ds, ax

    ; Enable paging
    mov     eax, RING0_PD_ADDR
    mov     cr3, eax
    mov     eax, cr0
    or      eax, CR0_PG
    mov     cr0, eax
    jmp     $+2

    ; ====== TEST 3: INVLPG instruction recognition ======
    ; INVLPG is a privileged instruction introduced on 486. Verify it
    ; executes without #UD. Full TLB-invalidation verification requires
    ; 86Box (DOSBox-X may not flush single-page TLB entries).
    ; Ref: Intel SDM Vol.2 — INVLPG.
    mov     dword [pm32_exc_recovery], .t3_after
    mov     byte [pm32_exc_caught], 0
    mov     eax, RING0_486_PF_PAGE
    invlpg  [eax]
.t3_after:
    cmp     byte [pm32_exc_caught], 0
    je      .t3_pass
    RING0_486_SETFAIL 3
.t3_pass:

    ; ====== TEST 4: CR0.WP (Write Protect) ======
    ; When WP=1, ring 0 writes to read-only pages cause #PF.
    ; When WP=0, ring 0 bypasses page write protection.
    ; Ref: Intel 80486 PRM §4.4.4 — WP bit.
    ; The RO page is at RING0_486_RO_PAGE (PTE has RW=0).

    ; First: set WP=1, write to RO page -> should #PF
    mov     eax, cr0
    or      eax, CR0_WP
    mov     cr0, eax

    mov     dword [pm32_exc_recovery], .t4_wp_after
    mov     byte [pm32_exc_caught], 0
    mov     ax, PM32_TEST_SEL2          ; flat DS for write
    mov     ds, ax
    mov     dword [RING0_486_RO_PAGE], 0x12345678   ; should #PF
.t4_wp_after:
    mov     ax, PM32_DATA32_SEL
    mov     ds, ax
    cmp     byte [pm32_exc_caught], 1
    jne     .t4_wp_fail
    cmp     dword [pm32_exc_vector], EXC_PF
    jne     .t4_wp_fail
    jmp     .t4_wp_pass
.t4_wp_fail:
    RING0_486_SETFAIL 4
.t4_wp_pass:

    ; Second: clear WP=0, write to RO page -> should succeed
    mov     eax, cr0
    and     eax, ~CR0_WP               ; clear WP
    mov     cr0, eax

    mov     dword [pm32_exc_recovery], .t4_nowp_after
    mov     byte [pm32_exc_caught], 0
    mov     ax, PM32_TEST_SEL2
    mov     ds, ax
    mov     dword [RING0_486_RO_PAGE], 0xDEADBEEF   ; should NOT #PF
.t4_nowp_after:
    mov     ax, PM32_DATA32_SEL
    mov     ds, ax
    ; Should NOT have caught an exception
    cmp     byte [pm32_exc_caught], 0
    je      .t4_nowp_pass
    RING0_486_SETFAIL 4                ; same test number, different sub-case
.t4_nowp_pass:

    ; --- Disable paging ---
    mov     eax, cr0
    and     eax, 0x7FFFFFFF             ; clear PG
    mov     cr0, eax
    jmp     $+2

    ;==============================================================
    ; NON-PAGING TESTS (5-6)
    ;==============================================================

    ; ====== TEST 5: CR0.AM + EFLAGS.AC bit manipulation ======
    ; #AC (vector 17) requires CR0.AM=1 AND EFLAGS.AC=1 AND misaligned access.
    ; Verify the bits can be set and read back. Actual #AC delivery
    ; requires 86Box (DOSBox-X may not implement it).
    ; Ref: Intel 80486 PRM §8.4 — alignment check.

    ; Set CR0.AM=1 and verify readback
    mov     eax, cr0
    or      eax, CR0_AM
    mov     cr0, eax
    mov     ebx, cr0
    test    ebx, CR0_AM
    jz      .t5_fail

    ; Set EFLAGS.AC=1 and verify readback
    pushfd
    or      dword [esp], EFLAGS_AC
    popfd
    pushfd
    pop     ebx
    test    ebx, EFLAGS_AC
    jz      .t5_fail

    ; Clear AM and AC
    pushfd
    and     dword [esp], ~EFLAGS_AC
    popfd
    mov     eax, cr0
    and     eax, ~CR0_AM
    mov     cr0, eax
    jmp     .t5_pass
.t5_fail:
    RING0_486_SETFAIL 5
.t5_pass:

    ; ====== TEST 6: CR0.CD/NW (Cache Control) ======
    ; CD (Cache Disable) and NW (Not Write-through) are 486+ CR0 bits.
    ; Test: set both bits, read back, verify, then clear.
    ; Ref: Intel 80486 PRM §4.4.2 — CD and NW bits.
    mov     eax, cr0
    mov     ebx, eax                   ; save original
    or      eax, CR0_CD | CR0_NW
    mov     cr0, eax
    ; Read back and check
    mov     eax, cr0
    test    eax, CR0_CD
    jz      .t6_fail
    test    eax, CR0_NW
    jz      .t6_fail
    ; Clear them
    mov     eax, cr0
    and     eax, ~(CR0_CD | CR0_NW)
    mov     cr0, eax
    mov     eax, cr0
    test    eax, CR0_CD
    jnz     .t6_fail
    test    eax, CR0_NW
    jnz     .t6_fail
    jmp     .t6_pass
.t6_fail:
    RING0_486_SETFAIL 6
.t6_pass:

    ; --- Restore original CR0 ---
    mov     eax, [ring0_486_save_cr0]
    mov     cr0, eax

    ret

;===========================================================================
; DATA
;===========================================================================
[BITS 16]

ring0_486_name:      db '80486 Ring0 PM Tests', 0
ring0_486_failmask:  dd 0
ring0_486_save_cr0:  dd 0
ring0_486_misalign:  dd 0, 0    ; 8 bytes for misaligned access test
