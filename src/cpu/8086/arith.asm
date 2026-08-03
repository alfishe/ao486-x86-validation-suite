;============================================================================
; MODULE: cpu/8086/arith.asm
; TIER:   UNIVERSAL
; VENUE:  G
; GEN:    8086+
; ORACLE: manual
; DESC:   ADD/SUB/ADC/SBB/MUL/DIV/INC/DEC — result and flag corner cases.
;         Focuses on overflow, carry, sign, zero, auxiliary-carry edges.
; REFS:   Intel 8086 Family Users Manual §2.2 (ADD), §2.3 (SUB),
;         §2.7 (MUL/DIV), §2.2.3 (flags summary)
;============================================================================

;---------------------------------------------------------------------------
; arith_init — Module initialization
;---------------------------------------------------------------------------
arith_init:
    ret

;---------------------------------------------------------------------------
; arith_run — Execute arithmetic test cases
; OUT: AL = STATUS_PASS or STATUS_FAIL
;
; PATTERN: Every test does: operation -> pushf (immediate capture) ->
;         check result -> check saved flags. Never put cmp between
;         operation and pushf.
;---------------------------------------------------------------------------
arith_run:
    push    bx
    push    cx
    push    dx
    push    si

    mov     si, 0                       ; sub-test failure index

    ; ========================================================================
    ; TEST 1: ADD basic no-carry
    ; 0x1234 + 0x1111 = 0x2345, CF=0, OF=0, SF=0, ZF=0, AF=0, PF=0
    ; ========================================================================
    mov     ax, 0x1234
    mov     bx, 0x1111
    add     ax, bx
    pushf
    pop     cx                          ; CX = flags from ADD
    cmp     ax, 0x2345
    jne     .fail
    ; CF must be 0
    test    cx, FLAG_CF
    jnz     .fail
    ; OF must be 0 (no signed overflow)
    test    cx, FLAG_OF
    jnz     .fail

    ; ========================================================================
    ; TEST 2: ADD carry out (CF=1, no OF)
    ; 0xFFFF + 0x0001 = 0x0000, CF=1, OF=0, ZF=1, AF=1
    ; ========================================================================
    mov     ax, 0xFFFF
    mov     bx, 0x0001
    add     ax, bx
    pushf
    pop     cx
    cmp     ax, 0x0000
    jne     .fail
    test    cx, FLAG_CF                 ; CF must be 1
    jz      .fail
    test    cx, FLAG_ZF                 ; ZF must be 1
    jz      .fail
    test    cx, FLAG_OF                 ; OF must be 0
    jnz     .fail

    ; ========================================================================
    ; TEST 3: ADD signed overflow (OF=1, no CF)
    ; 0x7FFF + 0x0001 = 0x8000, OF=1, SF=1, CF=0
    ; Positive + positive = negative → signed overflow
    ; ========================================================================
    mov     ax, 0x7FFF
    mov     bx, 0x0001
    add     ax, bx
    pushf
    pop     cx
    cmp     ax, 0x8000
    jne     .fail
    test    cx, FLAG_OF                 ; OF must be 1
    jz      .fail
    test    cx, FLAG_SF                 ; SF must be 1
    jz      .fail
    test    cx, FLAG_CF                 ; CF must be 0
    jnz     .fail

    ; ========================================================================
    ; TEST 4: SUB basic no-borrow
    ; 0x8000 - 0x0001 = 0x7FFF, CF=0, OF=1 (pos - neg overflow)
    ; Wait: 0x8000 is negative in signed view. neg - pos → overflow.
    ; Actually: 0x8000 (-32768) - 0x0001 (+1) = -32769, overflows to +32767
    ; OF=1, SF=0, CF=0
    ; ========================================================================
    mov     ax, 0x8000
    mov     bx, 0x0001
    sub     ax, bx
    pushf
    pop     cx
    cmp     ax, 0x7FFF
    jne     .fail
    test    cx, FLAG_CF                 ; CF must be 0 (no borrow)
    jnz     .fail
    test    cx, FLAG_OF                 ; OF must be 1 (signed overflow)
    jz      .fail

    ; ========================================================================
    ; TEST 5: SUB with borrow (CF=1)
    ; 0x0000 - 0x0001 = 0xFFFF, CF=1, SF=1, OF=0
    ; ========================================================================
    mov     ax, 0x0000
    mov     bx, 0x0001
    sub     ax, bx
    pushf
    pop     cx
    cmp     ax, 0xFFFF
    jne     .fail
    test    cx, FLAG_CF                 ; CF must be 1 (borrow)
    jz      .fail
    test    cx, FLAG_OF                 ; OF must be 0
    jnz     .fail

    ; ========================================================================
    ; TEST 6: ADC with CF=0 (same as ADD)
    ; clc; 0x1000 + 0x2000 + 0 = 0x3000, CF=0
    ; ========================================================================
    clc
    mov     ax, 0x1000
    mov     bx, 0x2000
    adc     ax, bx
    pushf
    pop     cx
    cmp     ax, 0x3000
    jne     .fail
    test    cx, FLAG_CF
    jnz     .fail

    ; ========================================================================
    ; TEST 7: ADC with CF=1 (carry added in)
    ; stc; 0x1000 + 0x2000 + 1 = 0x3001
    ; ========================================================================
    stc
    mov     ax, 0x1000
    mov     bx, 0x2000
    adc     ax, bx
    pushf
    pop     cx
    cmp     ax, 0x3001
    jne     .fail
    test    cx, FLAG_CF                 ; should be 0 (no new carry)
    jnz     .fail

    ; ========================================================================
    ; TEST 8: SBB with CF=1
    ; stc; 0x1000 - 0x0001 - 1 = 0x0FFE
    ; ========================================================================
    stc
    mov     ax, 0x1000
    mov     bx, 0x0001
    sbb     ax, bx
    pushf
    pop     cx
    cmp     ax, 0x0FFE
    jne     .fail

    ; ========================================================================
    ; TEST 9: MUL r/m8 — AX = AL * r/m8
    ; AL=0x10, BL=0x10 → AX=0x0100, CF=OF=0 (upper byte nonzero but < 0x80?
    ; Actually for MUL r/m8: if AH != 0, CF=OF=1)
    ; AH=0x01 (nonzero) → CF=1, OF=1
    ; ========================================================================
    mov     al, 0x10
    mov     bl, 0x10
    mul     bl                          ; AX = AL * BL
    pushf
    pop     cx
    cmp     ax, 0x0100
    jne     .fail
    test    cx, FLAG_CF                 ; AH nonzero → CF=1
    jz      .fail

    ; ========================================================================
    ; TEST 10: MUL r/m8 — no overflow (AH=0)
    ; AL=0x02, BL=0x03 → AX=0x0006, CF=OF=0
    ; ========================================================================
    mov     al, 0x02
    mov     bl, 0x03
    mul     bl
    pushf
    pop     cx
    cmp     ax, 0x0006
    jne     .fail
    test    cx, FLAG_CF                 ; AH=0 → CF=0
    jnz     .fail

    ; ========================================================================
    ; TEST 11: INC does NOT affect CF
    ; stc; INC ax → CF preserved=1
    ; ========================================================================
    stc
    mov     ax, 0x0001
    inc     ax
    pushf
    pop     cx
    cmp     ax, 0x0002
    jne     .fail
    test    cx, FLAG_CF                 ; CF must still be 1
    jz      .fail

    ; ========================================================================
    ; TEST 12: INC overflow from 0x7FFF → OF=1
    ; ========================================================================
    mov     ax, 0x7FFF
    inc     ax
    pushf
    pop     cx
    cmp     ax, 0x8000
    jne     .fail
    test    cx, FLAG_OF                 ; signed overflow → OF=1
    jz      .fail

    ; ========================================================================
    ; TEST 13: DEC does NOT affect CF
    ; stc; DEC ax → CF preserved=1
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
    ; TEST 14: DEC underflow 0x8000 → 0x7FFF, OF=1
    ; 0x8000 (-32768) + 1 = 0x7FFF (+32767) → signed overflow
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
    ; TEST 15: NEG 0 → 0, ZF=1, CF=0 (NEG of 0 does NOT set CF on 8086)
    ; Ref: 8086 manual — NEG sets CF=0 when operand is 0
    ; ========================================================================
    mov     ax, 0x0000
    neg     ax
    pushf
    pop     cx
    cmp     ax, 0x0000
    jne     .fail
    test    cx, FLAG_ZF                 ; ZF=1
    jz      .fail
    test    cx, FLAG_CF                 ; CF=0 (operand was 0)
    jnz     .fail

    ; ========================================================================
    ; TEST 16: NEG nonzero → CF=1
    ; ========================================================================
    mov     ax, 0x0005
    neg     ax
    pushf
    pop     cx
    cmp     ax, 0xFFFB                  ; -5 in 16-bit
    jne     .fail
    test    cx, FLAG_CF                 ; CF=1 (operand nonzero)
    jz      .fail

    ; All tests passed
    mov     al, STATUS_PASS
    jmp     .done

.fail:
    mov     al, STATUS_FAIL

.done:
    pop     si
    pop     dx
    pop     cx
    pop     bx
    ret

;---------------------------------------------------------------------------
; arith_cleanup — Module cleanup
;---------------------------------------------------------------------------
arith_cleanup:
    ret

; --- arith data ---
arith_name: db '8086 Arithmetic', 0
