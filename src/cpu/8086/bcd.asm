;============================================================================
; MODULE: cpu/8086/bcd.asm
; TIER:   UNIVERSAL
; VENUE:  G
; GEN:    8086+
; ORACLE: manual
; DESC:   DAA/DAS/AAA/AAS/AAM/AAD — BCD and ASCII adjust instructions.
;         DAA: Decimal Adjust after Addition (packed BCD)
;         DAS: Decimal Adjust after Subtraction (packed BCD)
;         AAA: ASCII Adjust after Addition (unpacked BCD)
;         AAS: ASCII Adjust after Subtraction (unpacked BCD)
;         AAM: ASCII Adjust after Multiplication (unpacked BCD)
;         AAD: ASCII Adjust before Division (unpacked BCD)
;         These instructions are notoriously CPU-dependent for undefined
;         flag bits. We test the documented behavior only.
; REFS:   Intel 8086 Family Users Manual §2.10 (decimal adjusts)
;============================================================================

;---------------------------------------------------------------------------
; bcd_init — Module initialization
;---------------------------------------------------------------------------
bcd_init:
    ret

;---------------------------------------------------------------------------
; bcd_run — Execute BCD test cases
; OUT: AL = STATUS_PASS or STATUS_FAIL
;---------------------------------------------------------------------------
bcd_run:
    push    bx
    push    cx
    push    dx

    ; ========================================================================
    ; TEST 1: DAA — packed BCD addition adjust
    ; 0x29 + 0x11 = 0x3A (invalid BCD), DAA → 0x40
    ; ========================================================================
    mov     al, 0x29                    ; BCD 29
    mov     bl, 0x11                    ; BCD 11
    add     al, bl                      ; AL = 0x3A (binary)
    daa                                 ; adjust: AL should be 0x40 (BCD 40)
    cmp     al, 0x40
    jne     .fail

    ; ========================================================================
    ; TEST 2: DAA — simple addition no adjust needed
    ; 0x11 + 0x22 = 0x33 (valid BCD)
    ; ========================================================================
    mov     al, 0x11
    add     al, 0x22                    ; 0x33, already valid BCD
    daa                                 ; no adjustment needed
    cmp     al, 0x33
    jne     .fail

    ; ========================================================================
    ; TEST 3: DAA — carry from low nibble
    ; 0x09 + 0x01 = 0x0A → DAA → 0x10, AF=1
    ; ========================================================================
    mov     al, 0x09
    add     al, 0x01                    ; AL = 0x0A
    daa                                 ; low nibble > 9, add 6
    cmp     al, 0x10                    ; 0x0A + 0x06 = 0x10
    jne     .fail

    ; ========================================================================
    ; TEST 4: DAS — packed BCD subtraction adjust
    ; 0x32 - 0x11 = 0x21 (valid BCD)
    ; ========================================================================
    mov     al, 0x32
    sub     al, 0x11                    ; 0x21, valid BCD
    das
    cmp     al, 0x21
    jne     .fail

    ; ========================================================================
    ; TEST 5: DAS — borrow from low nibble
    ; 0x21 - 0x09 = 0x18 → DAS → 0x12
    ; 0x21 - 0x09 = 0x18 in binary, but BCD should be 0x12
    ; ========================================================================
    mov     al, 0x21
    sub     al, 0x09                    ; AL = 0x18 (binary)
    das                                 ; low nibble had borrow, subtract 6
    cmp     al, 0x12                    ; 0x18 - 0x06 = 0x12
    jne     .fail

    ; ========================================================================
    ; TEST 6: AAA — unpacked BCD addition
    ; AL=3, BL=4: 3+4=7, no adjust needed
    ; ========================================================================
    mov     al, 0x03
    mov     ah, 0x00
    add     al, 0x04                    ; AL = 0x07
    aaa                                 ; no adjustment (AL < 10)
    cmp     al, 0x07
    jne     .fail
    cmp     ah, 0x00                    ; AH unchanged (no carry)
    jne     .fail

    ; ========================================================================
    ; TEST 7: AAA — adjust needed (AL >= 10)
    ; AL=7, AL+5=12: AAA → AL=2, AH=AH+1
    ; ========================================================================
    mov     ax, 0x0007                  ; AH=0, AL=7
    add     al, 0x05                    ; AL = 0x0C (12)
    aaa                                 ; AL > 9: AL -= 6, AL &= 0x0F, AH++
    cmp     al, 0x02                    ; (0x0C + 0x06) & 0x0F = 0x12 & 0x0F = 0x02
    jne     .fail
    cmp     ah, 0x01                    ; AH incremented
    jne     .fail

    ; ========================================================================
    ; TEST 8: AAS — unpacked BCD subtraction
    ; AL=3 - 4 = -1: need borrow
    ; ========================================================================
    mov     ax, 0x0003                  ; AH=0, AL=3
    sub     al, 0x04                    ; AL = 0xFF (-1)
    aas                                 ; AL < 6 (after sub, AF=1): AL += 6, AL &= 0x0F, AH--
    ; On 8086: AAS on 0xFF: AL becomes (0xFF+6)&0x0F = 0x09, AH=0xFF (-1)
    cmp     ah, 0xFF                    ; AH decremented
    jne     .fail
    cmp     al, 0x09                    ; adjusted low nibble
    jne     .fail

    ; ========================================================================
    ; TEST 9: AAM — unpacked BCD adjust after multiply
    ; AL = 3 * 4 = 12 → AH=1, AL=2
    ; ========================================================================
    mov     al, 0x03
    mov     bl, 0x04
    mul     bl                          ; AX = 0x000C (12)
    aam                                 ; AH = 12/10 = 1, AL = 12%10 = 2
    cmp     ah, 0x01
    jne     .fail
    cmp     al, 0x02
    jne     .fail

    ; ========================================================================
    ; TEST 10: AAD — unpacked BCD adjust before divide
    ; AX = 0x0102 (AH=1, AL=2 = BCD 12) → AL = 12, AH = 0
    ; ========================================================================
    mov     ax, 0x0102                  ; BCD 12
    aad                                 ; AL = AH*10 + AL = 1*10+2 = 12, AH=0
    cmp     al, 0x0C                    ; 12 decimal
    jne     .fail
    cmp     ah, 0x00
    jne     .fail

    ; ========================================================================
    ; TEST 11: AAM then AAD — round trip
    ; Multiply then undo: AAM(7*8) → AH=5,AL=6; AAD → AL=56
    ; ========================================================================
    mov     al, 0x07
    mov     bl, 0x08
    mul     bl                          ; AX = 56
    aam                                 ; AH=5, AL=6
    aad                                 ; AL = 5*10+6 = 56
    cmp     al, 56
    jne     .fail

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
; bcd_cleanup — Module cleanup
;---------------------------------------------------------------------------
bcd_cleanup:
    ret

; --- bcd data ---
bcd_name: db '8086 BCD Adjust', 0
