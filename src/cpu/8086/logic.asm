;============================================================================
; MODULE: cpu/8086/logic.asm
; TIER:   UNIVERSAL
; VENUE:  G
; GEN:    8086+
; ORACLE: manual
; DESC:   AND/OR/XOR/NOT/TEST — result and flag corners.
;         Key rules: AND/OR/XOR/TEST always clear CF=0 and OF=0.
;         AF is UNDEFINED after logic ops (varies by CPU gen).
;         SF, ZF, PF set according to result.
; REFS:   Intel 8086 Family Users Manual §2.4 (logic ops), §2.2.3 (flags)
;============================================================================

;---------------------------------------------------------------------------
; logic_init — Module initialization
;---------------------------------------------------------------------------
logic_init:
    ret

;---------------------------------------------------------------------------
; logic_run — Execute logic test cases
; OUT: AL = STATUS_PASS or STATUS_FAIL
;---------------------------------------------------------------------------
logic_run:
    push    bx
    push    cx
    push    dx

    ; ========================================================================
    ; TEST 1: AND — CF=0, OF=0 guaranteed
    ; 0xFF00 & 0x0FF0 = 0x0F00, SF=0, ZF=0, PF=1 (0x00 has even parity)
    ; ========================================================================
    stc                                 ; pre-set CF to verify it gets cleared
    mov     ax, 0xFF00
    mov     bx, 0x0FF0
    and     ax, bx
    pushf
    pop     cx
    cmp     ax, 0x0F00
    jne     .fail
    test    cx, FLAG_CF                 ; CF MUST be 0
    jnz     .fail
    test    cx, FLAG_OF                 ; OF MUST be 0
    jnz     .fail

    ; ========================================================================
    ; TEST 2: AND produces zero → ZF=1
    ; 0x00FF & 0xFF00 = 0x0000
    ; ========================================================================
    mov     ax, 0x00FF
    mov     bx, 0xFF00
    and     ax, bx
    pushf
    pop     cx
    cmp     ax, 0x0000
    jne     .fail
    test    cx, FLAG_ZF                 ; ZF must be 1
    jz      .fail
    test    cx, FLAG_SF                 ; SF must be 0
    jnz     .fail

    ; ========================================================================
    ; TEST 3: AND produces negative → SF=1
    ; 0xF0F0 & 0xF0F0 = 0xF0F0, SF=1
    ; ========================================================================
    mov     ax, 0xF0F0
    and     ax, 0xF0F0
    pushf
    pop     cx
    cmp     ax, 0xF0F0
    jne     .fail
    test    cx, FLAG_SF                 ; SF must be 1
    jz      .fail

    ; ========================================================================
    ; TEST 4: OR — CF=0, OF=0 guaranteed
    ; 0xF000 | 0x000F = 0xF00F
    ; ========================================================================
    stc
    mov     ax, 0xF000
    mov     bx, 0x000F
    or      ax, bx
    pushf
    pop     cx
    cmp     ax, 0xF00F
    jne     .fail
    test    cx, FLAG_CF                 ; CF MUST be 0
    jnz     .fail
    test    cx, FLAG_OF                 ; OF MUST be 0
    jnz     .fail
    test    cx, FLAG_SF                 ; SF=1 (MSB set)
    jz      .fail

    ; ========================================================================
    ; TEST 5: OR with self — no change, but flags update
    ; 0x1234 | 0x1234 = 0x1234
    ; ========================================================================
    mov     ax, 0x1234
    or      ax, ax
    pushf
    pop     cx
    cmp     ax, 0x1234
    jne     .fail
    test    cx, FLAG_ZF                 ; ZF=0 (nonzero result)
    jnz     .fail

    ; ========================================================================
    ; TEST 6: OR to zero from zero → ZF=1
    ; 0x0000 | 0x0000 = 0x0000
    ; ========================================================================
    mov     ax, 0x0000
    or      ax, ax
    pushf
    pop     cx
    test    cx, FLAG_ZF                 ; ZF must be 1
    jz      .fail

    ; ========================================================================
    ; TEST 7: XOR — CF=0, OF=0 guaranteed
    ; 0xFFFF ^ 0x000F = 0xFFF0
    ; ========================================================================
    stc
    mov     ax, 0xFFFF
    xor     ax, 0x000F
    pushf
    pop     cx
    cmp     ax, 0xFFF0
    jne     .fail
    test    cx, FLAG_CF                 ; CF MUST be 0
    jnz     .fail
    test    cx, FLAG_OF                 ; OF MUST be 0
    jnz     .fail

    ; ========================================================================
    ; TEST 8: XOR self = zero, ZF=1 (classic zeroing idiom)
    ; ========================================================================
    mov     ax, 0xBEEF
    xor     ax, ax
    pushf
    pop     cx
    cmp     ax, 0x0000
    jne     .fail
    test    cx, FLAG_ZF                 ; ZF=1
    jz      .fail

    ; ========================================================================
    ; TEST 9: TEST instruction — same flags as AND but result discarded
    ; TEST 0x00FF, 0xFF00 → result 0x0000, ZF=1
    ; ========================================================================
    mov     ax, 0x00FF
    test    ax, 0xFF00
    pushf
    pop     cx
    test    cx, FLAG_ZF                 ; ZF=1 (AND would be 0)
    jz      .fail
    test    cx, FLAG_CF                 ; CF=0
    jnz     .fail
    test    cx, FLAG_OF                 ; OF=0
    jnz     .fail

    ; ========================================================================
    ; TEST 10: TEST nonzero overlap → ZF=0
    ; TEST 0xF0F0, 0xF000 → result 0xF000, ZF=0, SF=1
    ; ========================================================================
    mov     ax, 0xF0F0
    test    ax, 0xF000
    pushf
    pop     cx
    test    cx, FLAG_ZF                 ; ZF=0
    jnz     .fail
    test    cx, FLAG_SF                 ; SF=1
    jz      .fail

    ; ========================================================================
    ; TEST 11: NOT — does NOT affect any flags
    ; NOT is one of the few instructions that leaves FLAGS completely untouched
    ; ========================================================================
    stc                                 ; CF=1
    mov     ax, 0x0000
    not     ax                          ; AX = 0xFFFF
    pushf
    pop     cx
    cmp     ax, 0xFFFF
    jne     .fail
    test    cx, FLAG_CF                 ; CF must still be 1
    jz      .fail

    ; ========================================================================
    ; TEST 12: NOT is its own inverse
    ; NOT(NOT(x)) == x
    ; ========================================================================
    mov     ax, 0xAAAA
    not     ax
    not     ax
    cmp     ax, 0xAAAA
    jne     .fail

    ; ========================================================================
    ; TEST 13: AND with 0xFFFF is identity (but flags still set)
    ; ========================================================================
    mov     ax, 0x8000
    and     ax, 0xFFFF
    pushf
    pop     cx
    cmp     ax, 0x8000
    jne     .fail
    test    cx, FLAG_SF                 ; SF=1
    jz      .fail

    ; All tests passed
    mov     al, STATUS_PASS
    jmp     .done

.fail:
    mov     al, STATUS_FAIL

.done:
    pop     dx
    pop     cx
    pop     bx
    ret

;---------------------------------------------------------------------------
; logic_cleanup — Module cleanup
;---------------------------------------------------------------------------
logic_cleanup:
    ret

; --- logic data ---
logic_name: db '8086 Logic/Bitwise', 0
