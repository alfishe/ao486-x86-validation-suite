;============================================================================
; MODULE: cpu/8086/inc_dec.asm
; TIER:   UNIVERSAL
; VENUE:  G
; GEN:    8086+
; ORACLE: manual
; DESC:   INC/DEC/NED — increment, decrement, negate edge cases.
;         Critical: INC/DEC do NOT affect CF (unlike ADD/SUB).
;         INC/DEC DO affect OF, SF, ZF, AF, PF.
;         NEG sets CF=1 for all nonzero operands, CF=0 for zero.
; REFS:   Intel 8086 Family Users Manual §2.3 (SUB/INC/DEC), §2.2.3 (flags)
;============================================================================

;---------------------------------------------------------------------------
; incdec_init — Module initialization
;---------------------------------------------------------------------------
incdec_init:
    ret

;---------------------------------------------------------------------------
; incdec_run — Execute INC/DEC test cases
; OUT: AL = STATUS_PASS or STATUS_FAIL
;---------------------------------------------------------------------------
incdec_run:
    push    bx
    push    cx
    push    dx

    ; ========================================================================
    ; TEST 1: INC preserves CF (CF=1 set before, must stay 1)
    ; ========================================================================
    stc                                 ; CF=1
    mov     ax, 0x0001
    inc     ax
    pushf
    pop     cx
    cmp     ax, 0x0002
    jne     .fail
    test    cx, FLAG_CF                 ; CF must still be 1
    jz      .fail

    ; ========================================================================
    ; TEST 2: INC preserves CF (CF=0 set before, must stay 0)
    ; ========================================================================
    clc
    mov     ax, 0x00FF
    inc     ax
    pushf
    pop     cx
    cmp     ax, 0x0100
    jne     .fail
    test    cx, FLAG_CF                 ; CF must still be 0
    jnz     .fail

    ; ========================================================================
    ; TEST 3: INC signed overflow 0x7FFF → 0x8000 (OF=1)
    ; 0x7FFF is max positive signed word. INC wraps to min negative.
    ; ========================================================================
    mov     ax, 0x7FFF
    inc     ax
    pushf
    pop     cx
    cmp     ax, 0x8000
    jne     .fail
    test    cx, FLAG_OF                 ; OF=1 (signed overflow)
    jz      .fail
    test    cx, FLAG_SF                 ; SF=1 (result is negative)
    jz      .fail

    ; ========================================================================
    ; TEST 4: INC zero → 1, ZF=0
    ; ========================================================================
    mov     ax, 0x0000
    inc     ax
    pushf
    pop     cx
    cmp     ax, 0x0001
    jne     .fail
    test    cx, FLAG_ZF                 ; ZF=0
    jnz     .fail

    ; ========================================================================
    ; TEST 5: INC 0xFFFF → 0x0000, ZF=1, AF=1
    ; ========================================================================
    mov     ax, 0xFFFF
    inc     ax
    pushf
    pop     cx
    cmp     ax, 0x0000
    jne     .fail
    test    cx, FLAG_ZF                 ; ZF=1
    jz      .fail

    ; ========================================================================
    ; TEST 6: DEC preserves CF (CF=1 set before)
    ; ========================================================================
    stc
    mov     ax, 0x0010
    dec     ax
    pushf
    pop     cx
    cmp     ax, 0x000F
    jne     .fail
    test    cx, FLAG_CF                 ; CF must still be 1
    jz      .fail

    ; ========================================================================
    ; TEST 7: DEC preserves CF (CF=0 set before)
    ; ========================================================================
    clc
    mov     ax, 0x0010
    dec     ax
    pushf
    pop     cx
    cmp     ax, 0x000F
    jne     .fail
    test    cx, FLAG_CF                 ; CF must still be 0
    jnz     .fail

    ; ========================================================================
    ; TEST 8: DEC signed underflow 0x8000 → 0x7FFF (OF=1)
    ; 0x8000 is min negative. DEC to max positive = signed overflow.
    ; ========================================================================
    mov     ax, 0x8000
    dec     ax
    pushf
    pop     cx
    cmp     ax, 0x7FFF
    jne     .fail
    test    cx, FLAG_OF                 ; OF=1
    jz      .fail

    ; ========================================================================
    ; TEST 9: DEC zero → 0xFFFF, ZF=0, SF=1, AF=1
    ; ========================================================================
    mov     ax, 0x0000
    dec     ax
    pushf
    pop     cx
    cmp     ax, 0xFFFF
    jne     .fail
    test    cx, FLAG_ZF                 ; ZF=0
    jnz     .fail
    test    cx, FLAG_SF                 ; SF=1
    jz      .fail

    ; ========================================================================
    ; TEST 10: DEC to zero → ZF=1
    ; ========================================================================
    mov     ax, 0x0001
    dec     ax
    pushf
    pop     cx
    cmp     ax, 0x0000
    jne     .fail
    test    cx, FLAG_ZF                 ; ZF=1
    jz      .fail

    ; ========================================================================
    ; TEST 11: NEG zero → zero, CF=0, ZF=1
    ; ========================================================================
    mov     ax, 0x0000
    neg     ax
    pushf
    pop     cx
    cmp     ax, 0x0000
    jne     .fail
    test    cx, FLAG_CF                 ; CF=0 (special case for NEG of 0)
    jnz     .fail
    test    cx, FLAG_ZF                 ; ZF=1
    jz      .fail

    ; ========================================================================
    ; TEST 12: NEG nonzero → CF=1
    ; ========================================================================
    mov     ax, 0x0001
    neg     ax
    pushf
    pop     cx
    cmp     ax, 0xFFFF                  ; -1 in 16-bit
    jne     .fail
    test    cx, FLAG_CF                 ; CF=1
    jz      .fail

    ; ========================================================================
    ; TEST 13: NEG 0x8000 → 0x8000 (overflow, OF=1)
    ; -(-32768) can't be represented in signed 16-bit
    ; ========================================================================
    mov     ax, 0x8000
    neg     ax
    pushf
    pop     cx
    cmp     ax, 0x8000                  ; result is same as input!
    jne     .fail
    test    cx, FLAG_OF                 ; OF=1
    jz      .fail

    ; ========================================================================
    ; TEST 14: INC byte register — AL
    ; ========================================================================
    mov     al, 0xFF
    inc     al
    pushf
    pop     cx
    cmp     al, 0x00
    jne     .fail
    test    cx, FLAG_ZF                 ; ZF=1
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
; incdec_cleanup — Module cleanup
;---------------------------------------------------------------------------
incdec_cleanup:
    ret

; --- inc_dec data ---
incdec_name: db '8086 INC/DEC/NEG', 0
