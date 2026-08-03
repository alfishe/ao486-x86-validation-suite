;============================================================================
; MODULE: cpu/8086/shift.asm
; TIER:   UNIVERSAL
; VENUE:  G
; GEN:    8086+
; ORACLE: manual + golden
; DESC:   SHL/SHR/SAR/ROL/ROR/RCL/RCR — result and flag corners.
;         Key 8086 behavior: shift count is NOT masked (full 8-bit CL value
;         used, though hardware effectively does count mod 32 for performance).
;         On 286+, count is masked to 5 bits (mod 32).
;         Count=0 is a no-op including flags.
; REFS:   Intel 8086 Family Users Manual §2.6 (shifts/rotates);
;         iAPX286 PRM §3 (count mask = 5 bits)
; DIVERGE: 8086 uses full CL count; 286+ masks to 5 bits.
;============================================================================

;---------------------------------------------------------------------------
; shift_init — Module initialization
;---------------------------------------------------------------------------
shift_init:
    ret

;---------------------------------------------------------------------------
; shift_run — Execute shift/rotate test cases
; OUT: AL = STATUS_PASS or STATUS_FAIL
;---------------------------------------------------------------------------
shift_run:
    push    bx
    push    cx
    push    dx

    ; ========================================================================
    ; TEST 1: SHL by 1 — CF gets the shifted-out bit
    ; 0x8001 << 1 = 0x0002, CF=1 (MSB shifted out), OF=0 (signs differ)
    ; ========================================================================
    mov     ax, 0x8001
    shl     ax, 1
    pushf
    pop     cx
    cmp     ax, 0x0002
    jne     .fail
    test    cx, FLAG_CF                 ; CF=1 (bit 15 was 1)
    jz      .fail

    ; ========================================================================
    ; TEST 2: SHL by 1 — CF=0 when MSB is 0
    ; 0x4000 << 1 = 0x8000, CF=0, OF=1 (sign changed)
    ; ========================================================================
    mov     ax, 0x4000
    shl     ax, 1
    pushf
    pop     cx
    cmp     ax, 0x8000
    jne     .fail
    test    cx, FLAG_CF                 ; CF=0
    jnz     .fail
    test    cx, FLAG_OF                 ; OF=1 (sign changed on 8086 for shift by 1)
    jz      .fail

    ; ========================================================================
    ; TEST 3: SHR by 1 — CF gets the shifted-out bit
    ; 0x0002 >> 1 = 0x0001, CF=0
    ; ========================================================================
    mov     ax, 0x0002
    shr     ax, 1
    pushf
    pop     cx
    cmp     ax, 0x0001
    jne     .fail
    test    cx, FLAG_CF                 ; CF=0 (bit 0 was 0)
    jnz     .fail

    ; ========================================================================
    ; TEST 4: SHR by 1 — CF=1 when LSB is 1
    ; 0x0003 >> 1 = 0x0001, CF=1
    ; ========================================================================
    mov     ax, 0x0003
    shr     ax, 1
    pushf
    pop     cx
    cmp     ax, 0x0001
    jne     .fail
    test    cx, FLAG_CF                 ; CF=1
    jz      .fail

    ; ========================================================================
    ; TEST 5: SAR by 1 — sign bit preserved
    ; 0x8000 SAR 1 = 0xC000, CF=0
    ; ========================================================================
    mov     ax, 0x8000
    sar     ax, 1
    pushf
    pop     cx
    cmp     ax, 0xC000
    jne     .fail
    test    cx, FLAG_CF                 ; CF=0 (bit 0 was 0)
    jnz     .fail

    ; ========================================================================
    ; TEST 6: SAR preserves sign — 0x8000 SAR 15 = 0xFFFF
    ; ========================================================================
    mov     ax, 0x8000
    mov     cl, 15
    sar     ax, cl
    pushf
    pop     cx
    cmp     ax, 0xFFFF
    jne     .fail

    ; ========================================================================
    ; TEST 7: SHL by count > 1 — OF is undefined (don't test)
    ; 0x0001 << 4 = 0x0010
    ; ========================================================================
    mov     ax, 0x0001
    mov     cl, 4
    shl     ax, cl
    cmp     ax, 0x0010
    jne     .fail

    ; ========================================================================
    ; TEST 8: SHR by count > 1
    ; 0xFF00 >> 4 = 0x0FF0
    ; ========================================================================
    mov     ax, 0xFF00
    mov     cl, 4
    shr     ax, cl
    cmp     ax, 0x0FF0
    jne     .fail

    ; ========================================================================
    ; TEST 9: ROL by 1 — bit wraps around to LSB, old MSB goes to CF
    ; 0x8001 ROL 1 = 0x0003, CF=1
    ; ========================================================================
    mov     ax, 0x8001
    rol     ax, 1
    pushf
    pop     cx
    cmp     ax, 0x0003
    jne     .fail
    test    cx, FLAG_CF                 ; CF = old MSB = 1
    jz      .fail

    ; ========================================================================
    ; TEST 10: ROR by 1 — bit wraps to MSB, old LSB goes to CF
    ; 0x0001 ROR 1 = 0x8000, CF=1
    ; ========================================================================
    mov     ax, 0x0001
    ror     ax, 1
    pushf
    pop     cx
    cmp     ax, 0x8000
    jne     .fail
    test    cx, FLAG_CF                 ; CF = old LSB = 1
    jz      .fail

    ; ========================================================================
    ; TEST 11: RCL by 1 — CF goes to LSB, old MSB goes to CF
    ; CLC; 0x8000 RCL 1 = 0x0000 + CF=1
    ; ========================================================================
    clc
    mov     ax, 0x8000
    rcl     ax, 1
    pushf
    pop     cx
    cmp     ax, 0x0000
    jne     .fail
    test    cx, FLAG_CF                 ; CF = old MSB = 1
    jz      .fail

    ; ========================================================================
    ; TEST 12: RCR by 1 — CF goes to MSB, old LSB goes to CF
    ; STC; 0x0000 RCR 1 = 0x8000 + CF=0
    ; ========================================================================
    stc
    mov     ax, 0x0000
    rcr     ax, 1
    pushf
    pop     cx
    cmp     ax, 0x8000
    jne     .fail
    test    cx, FLAG_CF                 ; CF = old LSB = 0
    jnz     .fail

    ; ========================================================================
    ; TEST 13: Shift by CL=0 — ALL flags unchanged (no-op)
    ; This is a critical corner: shift by 0 does not modify flags at all.
    ; ========================================================================
    stc                                 ; CF=1
    mov     ax, 0x1234
    mov     cl, 0
    shl     ax, cl                      ; no-op, flags unchanged
    pushf
    pop     cx
    cmp     ax, 0x1234                  ; result unchanged
    jne     .fail
    test    cx, FLAG_CF                 ; CF must still be 1
    jz      .fail

    ; ========================================================================
    ; TEST 14: Shift by CL=0 with CF=0 — CF preserved
    ; ========================================================================
    clc
    mov     ax, 0x5678
    mov     cl, 0
    shr     ax, cl
    pushf
    pop     cx
    cmp     ax, 0x5678
    jne     .fail
    test    cx, FLAG_CF                 ; CF must still be 0
    jnz     .fail

    ; ========================================================================
    ; TEST 15: SHL to zero — 0x0001 << 1 = 0x0002, not zero
    ; But 0xFFFF << 1 = 0xFFFE, CF=1
    ; ========================================================================
    mov     ax, 0xFFFF
    shl     ax, 1
    pushf
    pop     cx
    cmp     ax, 0xFFFE
    jne     .fail
    test    cx, FLAG_CF                 ; CF=1
    jz      .fail

    ; ========================================================================
    ; TEST 16: SHR of zero — 0 >> 1 = 0, CF=0, ZF=1
    ; ========================================================================
    mov     ax, 0x0000
    shr     ax, 1
    pushf
    pop     cx
    cmp     ax, 0x0000
    jne     .fail
    test    cx, FLAG_CF                 ; CF=0
    jnz     .fail
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
; shift_cleanup — Module cleanup
;---------------------------------------------------------------------------
shift_cleanup:
    ret

; --- shift data ---
shift_name: db '8086 Shift/Rotate', 0
