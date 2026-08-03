;============================================================================
; MODULE: cpu/8086/multiply.asm
; TIER:   UNIVERSAL
; VENUE:  G
; GEN:    8086+
; ORACLE: manual
; DESC:   MUL/IMUL — unsigned and signed multiply, 8-bit and 16-bit forms.
;         Complements arith.asm which only covers MUL r/m8.
;         - MUL r/m16: DX:AX = AX * r/m16 (unsigned)
;         - IMUL r/m8: AX = AL * r/m8 (signed)
;         - IMUL r/m16: DX:AX = AX * r/m16 (signed)
;         - Flag behavior: CF/OF set if upper half is nonzero
;
; REFS:   Intel 8086 Family Users Manual §2.7 (MUL/IMUL)
;============================================================================

;---------------------------------------------------------------------------
mul_init:
    ret

;---------------------------------------------------------------------------
; mul_run
;---------------------------------------------------------------------------
mul_run:
    push    bx
    push    cx
    push    dx

    ; ========================================================================
    ; TEST 1: MUL r/m16 — 256 × 256 = 65536 (0x00010000)
    ; DX:AX = AX * BX. AX=256, BX=256 → DX:AX = 0x0001:0x0000
    ; CF=1, OF=1 (DX nonzero → upper half significant)
    ; ========================================================================
    mov     ax, 256
    mov     bx, 256
    mul     bx                              ; DX:AX = 65536
    pushf
    pop     cx
    cmp     ax, 0x0000                      ; low word = 0
    jne     .fail
    cmp     dx, 0x0001                      ; high word = 1
    jne     .fail
    test    cx, FLAG_CF                     ; CF=1 (DX nonzero)
    jz      .fail

    ; ========================================================================
    ; TEST 2: MUL r/m16 — no overflow (result fits in 16 bits)
    ; 100 × 200 = 20000 = 0x4E20
    ; DX=0, CF=0, OF=0
    ; ========================================================================
    mov     ax, 100
    mov     bx, 200
    mul     bx
    pushf
    pop     cx
    cmp     ax, 20000
    jne     .fail
    cmp     dx, 0                           ; DX must be 0
    jne     .fail
    test    cx, FLAG_CF                     ; CF=0
    jnz     .fail

    ; ========================================================================
    ; TEST 3: MUL r/m16 — multiply by zero
    ; 12345 × 0 = 0, DX:AX = 0, CF=0
    ; ========================================================================
    mov     ax, 12345
    mov     bx, 0
    mul     bx
    pushf
    pop     cx
    cmp     ax, 0
    jne     .fail
    cmp     dx, 0
    jne     .fail
    test    cx, FLAG_CF                     ; CF=0 (DX=0)
    jnz     .fail

    ; ========================================================================
    ; TEST 4: MUL r/m16 — large values
    ; 0xFFFF × 0xFFFF = 0xFFFE0001
    ; DX=0xFFFE, AX=0x0001
    ; ========================================================================
    mov     ax, 0xFFFF
    mov     bx, 0xFFFF
    mul     bx
    cmp     ax, 0x0001
    jne     .fail
    cmp     dx, 0xFFFE
    jne     .fail

    ; ========================================================================
    ; TEST 5: IMUL r/m8 — signed: AL=5, BL=3 → AX=15
    ; ========================================================================
    mov     al, 5
    mov     bl, 3
    imul    bl                              ; AX = AL * BL = 15
    cmp     ax, 15
    jne     .fail

    ; ========================================================================
    ; TEST 6: IMUL r/m8 — signed negative: AL=-5, BL=3 → AX=-15
    ; -15 = 0xFFF1, CF=0 (fits in signed 8-bit: AH=0xFF sign-extends AL)
    ; Actually: CF=1 because AH != sign-extension of AL
    ; AH=0xFF (which IS sign extension of AL=0xF1), so CF=0
    ; ========================================================================
    mov     al, -5                          ; 0xFB
    mov     bl, 3
    imul    bl                              ; AX = -15 = 0xFFF1
    cmp     ax, 0xFFF1
    jne     .fail
    ; AH = 0xFF which is sign extension of AL = 0xF1 → CF=0, OF=0
    pushf
    pop     cx
    test    cx, FLAG_CF                     ; CF=0 (AH = sign-extend of AL)
    jnz     .fail

    ; ========================================================================
    ; TEST 7: IMUL r/m8 — signed: AL=-5, BL=-3 → AX=15
    ; ========================================================================
    mov     al, -5                          ; 0xFB
    mov     bl, -3                          ; 0xFD
    imul    bl                              ; AX = 15
    cmp     ax, 15
    jne     .fail

    ; ========================================================================
    ; TEST 8: IMUL r/m8 — overflow: AL=100, BL=100 → AX=10000
    ; 100 * 100 = 10000 (0x2710). AH=0x27, AL=0x10
    ; AH != sign-extension of AL → CF=1, OF=1
    ; ========================================================================
    mov     al, 100
    mov     bl, 100
    imul    bl                              ; AX = 10000
    pushf
    pop     cx
    cmp     ax, 10000
    jne     .fail
    test    cx, FLAG_CF                     ; CF=1 (result doesn't fit in 8-bit signed)
    jz      .fail

    ; ========================================================================
    ; TEST 9: IMUL r/m16 — signed: AX=10, BX=20 → DX:AX=200
    ; CF=0 (DX=0)
    ; ========================================================================
    mov     ax, 10
    mov     bx, 20
    imul    bx                              ; DX:AX = 200
    pushf
    pop     cx
    cmp     ax, 200
    jne     .fail
    cmp     dx, 0
    jne     .fail
    test    cx, FLAG_CF                     ; CF=0
    jnz     .fail

    ; ========================================================================
    ; TEST 10: IMUL r/m16 — signed negative result
    ; AX=-10, BX=20 → DX:AX = -200
    ; DX=0xFFFF (sign extension), CF=0
    ; ========================================================================
    mov     ax, -10
    mov     bx, 20
    imul    bx                              ; DX:AX = -200
    pushf
    pop     cx
    ; -200 = 0xFF38 in 16-bit
    cmp     ax, 0xFF38
    jne     .fail
    cmp     dx, 0xFFFF                      ; sign-extended
    jne     .fail
    test    cx, FLAG_CF                     ; CF=0 (DX = sign-ext of AX)
    jnz     .fail

    ; ========================================================================
    ; TEST 11: IMUL r/m16 — both negative → positive
    ; AX=-100, BX=-100 → DX:AX = 10000
    ; ========================================================================
    mov     ax, -100
    mov     bx, -100
    imul    bx
    pushf
    pop     cx
    cmp     ax, 10000
    jne     .fail
    cmp     dx, 0                           ; positive result, DX=0
    jne     .fail
    test    cx, FLAG_CF                     ; CF=0
    jnz     .fail

    ; ========================================================================
    ; TEST 12: IMUL r/m16 — overflow (large positive × positive)
    ; AX=1000, BX=1000 → DX:AX = 1000000 = 0x000F:0x4240
    ; DX=0x000F (nonzero) → CF=1
    ; ========================================================================
    mov     ax, 1000
    mov     bx, 1000
    imul    bx                              ; DX:AX = 1000000
    pushf
    pop     cx
    cmp     ax, 0x4240                      ; 1000000 & 0xFFFF
    jne     .fail
    cmp     dx, 0x000F                      ; 1000000 >> 16
    jne     .fail
    test    cx, FLAG_CF                     ; CF=1 (overflow)
    jz      .fail

    ; ========================================================================
    ; TEST 13: MUL r/m16 using memory operand
    ; AX=4, [word]=5 → DX:AX = 20
    ; ========================================================================
    mov     word [mul_val16], 5
    mov     ax, 4
    mul     word [mul_val16]               ; DX:AX = 20
    pushf
    pop     cx
    cmp     ax, 20
    jne     .fail
    cmp     dx, 0
    jne     .fail
    test    cx, FLAG_CF
    jnz     .fail

    ; ========================================================================
    ; TEST 14: IMUL r/m16 — AX=0xFFFF(-1), BX=0xFFFF(-1) → DX:AX=1
    ; -1 * -1 = 1, DX=0, CF=0
    ; ========================================================================
    mov     ax, 0xFFFF                      ; -1
    mov     bx, 0xFFFF                      ; -1
    imul    bx
    pushf
    pop     cx
    cmp     ax, 1
    jne     .fail
    cmp     dx, 0
    jne     .fail
    test    cx, FLAG_CF                     ; CF=0
    jnz     .fail

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
mul_cleanup:
    ret

; --- multiply data ---
mul_name: db '8086 MUL/IMUL 16-bit', 0

mul_val16: dw 0
