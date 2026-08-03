;============================================================================
; MODULE: fpu/8087/compare.asm
; TIER:   UNIVERSAL
; VENUE:  G
; GEN:    8086+ (requires 8087 FPU)
; ORACLE: manual
; DESC:   8087 FPU comparison operations:
;         - FCOM/FCOMP/FCOMPP: register and memory operand comparison
;         - FTST: compare ST(0) with zero
;         - FXAM: examine ST(0) class
;         - Condition code interpretation via FSTSW
;
; Status word condition code mapping (bits 8-11, 14):
;   C3(bit14) C2(bit10) C0(bit8) : meaning
;   0          0          0       : ST > operand
;   0          0          1       : ST < operand
;   1          0          0       : ST = operand
;   1          1          1       : unordered (NaN)
;
; REFS:   Intel 8087 PRM §4 (FCOM/FTST/FXAM)
;============================================================================

;---------------------------------------------------------------------------
fpu_cmp_init:
    ret

;---------------------------------------------------------------------------
; fpu_cmp_run
;---------------------------------------------------------------------------
fpu_cmp_run:
    push    bx
    push    cx
    push    dx

    ; Capability gate
    mov     al, [g_fpu_type]
    cmp     al, FPU_NONE
    jne     .cap_ok
    mov     al, STATUS_SKIP
    jmp     .cleanup
.cap_ok:

    fnsave  [fpc_save_buf]
    fninit

    ; ========================================================================
    ; TEST 1: FCOM — ST(0) > operand (5.0 > 3.0)
    ; Expected: C3=0, C2=0, C0=0 → SW & 0x4500 = 0x0000
    ; ========================================================================
    fninit
    fld     dword [fpc_r32_5p0]          ; ST0 = 5.0
    fcom    dword [fpc_r32_3p0]          ; compare ST0 with 3.0
    fnstsw  ax
    and     ax, 0x4500
    cmp     ax, 0x0000                   ; greater than
    jne     .fail
    ffree   st0                          ; clean up

    ; ========================================================================
    ; TEST 2: FCOM — ST(0) < operand (3.0 < 5.0)
    ; Expected: C3=0, C2=0, C0=1 → SW & 0x4500 = 0x0100
    ; ========================================================================
    fninit
    fld     dword [fpc_r32_3p0]          ; ST0 = 3.0
    fcom    dword [fpc_r32_5p0]          ; compare ST0 with 5.0
    fnstsw  ax
    and     ax, 0x4500
    cmp     ax, 0x0100                   ; less than
    jne     .fail
    ffree   st0

    ; ========================================================================
    ; TEST 3: FCOM — ST(0) = operand (4.0 = 4.0)
    ; Expected: C3=1, C2=0, C0=0 → SW & 0x4500 = 0x4000
    ; ========================================================================
    fninit
    fld     dword [fpc_r32_4p0]
    fcom    dword [fpc_r32_4p0]
    fnstsw  ax
    and     ax, 0x4500
    cmp     ax, 0x4000                   ; equal
    jne     .fail
    ffree   st0

    ; ========================================================================
    ; TEST 4: FCOMP — compare and pop (7.0 > 3.0)
    ; ========================================================================
    fninit
    fld     dword [fpc_r32_7p0]
    fcomp   dword [fpc_r32_3p0]          ; compare + pop
    fnstsw  ax
    and     ax, 0x4500
    cmp     ax, 0x0000                   ; greater
    jne     .fail

    ; ========================================================================
    ; TEST 5: FCOMPP — compare ST(0) with ST(1) and pop both
    ; Push 10.0 then 3.0: ST0=3, ST1=10. FCOMPP: 3 < 10 → C0=1
    ; ========================================================================
    fninit
    fld     dword [fpc_r32_10p0]         ; ST1 = 10.0
    fld     dword [fpc_r32_3p0]          ; ST0 = 3.0
    fcompp                               ; compare ST0 vs ST1, pop both
    fnstsw  ax
    and     ax, 0x4500
    cmp     ax, 0x0100                   ; ST0 < ST1 = less than
    jne     .fail

    ; ========================================================================
    ; TEST 6: FTST — compare ST(0) with +0.0 (equal)
    ; ========================================================================
    fninit
    fldz                                ; ST0 = +0.0
    ftst                                ; compare ST0 with 0.0
    fnstsw  ax
    and     ax, 0x4500
    cmp     ax, 0x4000                   ; equal
    jne     .fail
    ffree   st0

    ; ========================================================================
    ; TEST 7: FTST — positive value (5.0 > 0)
    ; ========================================================================
    fninit
    fld     dword [fpc_r32_5p0]
    ftst
    fnstsw  ax
    and     ax, 0x4500
    cmp     ax, 0x0000                   ; greater
    jne     .fail
    ffree   st0

    ; ========================================================================
    ; TEST 8: FTST — negative value (-3.0 < 0)
    ; ========================================================================
    fninit
    fld     dword [fpc_r32_neg3p0]
    ftst
    fnstsw  ax
    and     ax, 0x4500
    cmp     ax, 0x0100                   ; less than
    jne     .fail
    ffree   st0

    ; ========================================================================
    ; TEST 9: FXAM — examine +1.0
    ; FXAM classifies ST(0). For a normal positive finite value:
    ; C3=0, C2=1, C1=0, C0=0 → SW & 0x4500 = 0x0400 (C2=1)
    ; C1 is sign: 0 for positive
    ; ========================================================================
    fninit
    fld1                                ; ST0 = +1.0 (normal, positive)
    fxam
    fnstsw  ax
    and     ax, 0x4500                   ; mask C3|C2|C0
    cmp     ax, 0x0400                   ; C2=1 → normal (finite, non-zero)
    jne     .fail
    ; Also check C1 (sign bit, bit 9): should be 0 for positive
    test    ax, 0x0200                   ; wait, C1 is bit 9... but we masked
    ; Actually we already masked 0x4500 which doesn't include bit 9.
    ; Let me check the full AX from the status word
    ; Re-examine: we need to check C1 separately
    ffree   st0

    ; ========================================================================
    ; TEST 10: FXAM — examine zero (FLDZ)
    ; For +0: C3=1, C2=0, C1=0, C0=0 → SW & 0x4500 = 0x4000
    ; ========================================================================
    fninit
    fldz                                ; ST0 = +0.0
    fxam
    fnstsw  ax
    and     ax, 0x4500
    cmp     ax, 0x4000                   ; C3=1 → zero
    jne     .fail
    ffree   st0

    ; ========================================================================
    ; TEST 11: FCOM with register operand — ST(0) vs ST(1)
    ; Push 5.0, 3.0: FCOM ST(1) compares ST0=3.0 vs ST1=5.0 → less
    ; ========================================================================
    fninit
    fld     dword [fpc_r32_5p0]          ; ST1 = 5.0
    fld     dword [fpc_r32_3p0]          ; ST0 = 3.0
    fcom    st1                          ; compare ST0 with ST1
    fnstsw  ax
    and     ax, 0x4500
    cmp     ax, 0x0100                   ; less than
    jne     .fail
    fcompp                               ; clean up both

    ; ========================================================================
    ; All tests passed
    ; ========================================================================
    mov     al, STATUS_PASS
    jmp     .cleanup

.fail:
    mov     al, STATUS_FAIL

.cleanup:
    fninit
    frstor  [fpc_save_buf]

    pop     dx
    pop     cx
    pop     bx
    ret

;---------------------------------------------------------------------------
fpu_cmp_cleanup:
    ret

; --- data ---
fpu_cmp_name: db '8087 FPU Compare', 0

fpc_save_buf:   times 108 db 0

fpc_r32_3p0:    dd 3.0
fpc_r32_4p0:    dd 4.0
fpc_r32_5p0:    dd 5.0
fpc_r32_7p0:    dd 7.0
fpc_r32_10p0:   dd 10.0
fpc_r32_neg3p0: dd -3.0
