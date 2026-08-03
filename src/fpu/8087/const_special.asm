;============================================================================
; MODULE: fpu/8087/const_special.asm
; TIER:   UNIVERSAL
; VENUE:  G
; GEN:    8086+ (requires 8087 FPU)
; ORACLE: manual + golden
; DESC:   8087 FPU constants and special operations:
;         - FLDZ/FLD1: load zero and one
;         - FLDPI: load pi (verify via known properties)
;         - FSQRT: square root of known values
;         - FRNDINT: round to nearest integer
;         - FSCALE: scale by power of 2
;         - FPREM: partial remainder
;
; Constants like pi can't be compared byte-exact across FPU generations
; (8087 vs 387+ differ in internal precision). Instead, verify known
; mathematical properties (e.g., sin(pi)=0, pi > 3.0, pi < 4.0).
;
; REFS:   Intel 8087 PRM §4 (constants, FSQRT, FRNDINT, FSCALE, FPREM)
;============================================================================

;---------------------------------------------------------------------------
fpu_cs_init:
    ret

;---------------------------------------------------------------------------
; fpu_cs_run
;---------------------------------------------------------------------------
fpu_cs_run:
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

    fnsave  [fpcs_save_buf]
    fninit

    ; ========================================================================
    ; TEST 1: FLDZ — load +0.0, verify it equals zero via FTST
    ; ========================================================================
    fninit
    fldz                                ; ST0 = +0.0
    ftst                                ; compare with 0.0
    fnstsw  ax
    and     ax, 0x4500
    cmp     ax, 0x4000                   ; equal
    jne     .fail
    ffree   st0

    ; ========================================================================
    ; TEST 2: FLD1 — load +1.0, verify via FCOM with 1.0 constant
    ; ========================================================================
    fninit
    fld1                                ; ST0 = +1.0
    fcom    dword [fpcs_r32_1p0]
    fnstsw  ax
    and     ax, 0x4500
    cmp     ax, 0x4000                   ; equal
    jne     .fail
    ffree   st0

    ; ========================================================================
    ; TEST 3: FLDPI — pi must be > 3.0 and < 4.0
    ; ========================================================================
    fninit
    fldpi                               ; ST0 = pi
    fcom    dword [fpcs_r32_3p0]         ; compare pi with 3.0
    fnstsw  ax
    and     ax, 0x4500
    cmp     ax, 0x0000                   ; pi > 3.0
    jne     .fail
    fcom    dword [fpcs_r32_4p0]         ; compare pi with 4.0
    fnstsw  ax
    and     ax, 0x4500
    cmp     ax, 0x0100                   ; pi < 4.0
    jne     .fail
    ffree   st0

    ; ========================================================================
    ; TEST 4: FLDL2T — log2(10) ≈ 3.3219, should be > 3 and < 4
    ; ========================================================================
    fninit
    fldl2t                              ; ST0 = log2(10)
    fcom    dword [fpcs_r32_3p0]
    fnstsw  ax
    and     ax, 0x4500
    cmp     ax, 0x0000                   ; > 3
    jne     .fail
    fcom    dword [fpcs_r32_4p0]
    fnstsw  ax
    and     ax, 0x4500
    cmp     ax, 0x0100                   ; < 4
    jne     .fail
    ffree   st0

    ; ========================================================================
    ; TEST 5: FLDL2E — log2(e) ≈ 1.4427, should be > 1 and < 2
    ; ========================================================================
    fninit
    fldl2e                              ; ST0 = log2(e)
    fcom    dword [fpcs_r32_1p0]
    fnstsw  ax
    and     ax, 0x4500
    cmp     ax, 0x0000                   ; > 1
    jne     .fail
    fcom    dword [fpcs_r32_2p0]
    fnstsw  ax
    and     ax, 0x4500
    cmp     ax, 0x0100                   ; < 2
    jne     .fail
    ffree   st0

    ; ========================================================================
    ; TEST 6: FSQRT — sqrt(16.0) = 4.0
    ; ========================================================================
    fninit
    fld     dword [fpcs_r32_16p0]        ; ST0 = 16.0
    fsqrt                               ; ST0 = 4.0
    fld     dword [fpcs_r32_4p0]
    fcompp
    fnstsw  ax
    and     ax, 0x4500
    cmp     ax, 0x4000                   ; equal
    jne     .fail

    ; ========================================================================
    ; TEST 7: FSQRT — sqrt(1.0) = 1.0
    ; ========================================================================
    fninit
    fld1                                ; ST0 = 1.0
    fsqrt                               ; ST0 = 1.0
    fld     dword [fpcs_r32_1p0]
    fcompp
    fnstsw  ax
    and     ax, 0x4500
    cmp     ax, 0x4000
    jne     .fail

    ; ========================================================================
    ; TEST 8: FSQRT — sqrt(0.0) = 0.0
    ; ========================================================================
    fninit
    fldz                                ; ST0 = 0.0
    fsqrt                               ; ST0 = 0.0
    ftst
    fnstsw  ax
    and     ax, 0x4500
    cmp     ax, 0x4000                   ; equal to zero
    jne     .fail

    ; ========================================================================
    ; TEST 9: FRNDINT — round 3.7 to nearest = 4.0
    ; ========================================================================
    fninit
    fld     dword [fpcs_r32_3p7]         ; ST0 = 3.7
    frndint                             ; ST0 = 4.0 (round to nearest)
    fld     dword [fpcs_r32_4p0]
    fcompp
    fnstsw  ax
    and     ax, 0x4500
    cmp     ax, 0x4000
    jne     .fail

    ; ========================================================================
    ; TEST 10: FRNDINT — round 2.3 to nearest = 2.0
    ; ========================================================================
    fninit
    fld     dword [fpcs_r32_2p3]         ; ST0 = 2.3
    frndint                             ; ST0 = 2.0
    fld     dword [fpcs_r32_2p0]
    fcompp
    fnstsw  ax
    and     ax, 0x4500
    cmp     ax, 0x4000
    jne     .fail

    ; ========================================================================
    ; TEST 11: FRNDINT — round -3.7 to nearest = -4.0
    ; ========================================================================
    fninit
    fld     dword [fpcs_r32_neg3p7]      ; ST0 = -3.7
    frndint                             ; ST0 = -4.0
    fld     dword [fpcs_r32_neg4p0]
    fcompp
    fnstsw  ax
    and     ax, 0x4500
    cmp     ax, 0x4000
    jne     .fail

    ; ========================================================================
    ; TEST 12: FSCALE — scale 1.0 by 2^3 = 8.0
    ; FSCALE: ST0 = ST0 × 2^ST1
    ; Push 3.0 (scaling factor) then 1.0 (value)
    ; After FSCALE: ST0 = 1.0 × 2^3.0 = 8.0, ST1 = 3.0
    ; ========================================================================
    fninit
    fld     dword [fpcs_r32_3p0]         ; ST1 = 3.0 (scaling factor)
    fld     dword [fpcs_r32_1p0]         ; ST0 = 1.0 (value to scale)
    fscale                              ; ST0 = 1.0 × 2^3 = 8.0
    fld     dword [fpcs_r32_8p0]
    fcompp                              ; compare 8.0 with result, pop both
    fnstsw  ax
    and     ax, 0x4500
    cmp     ax, 0x4000
    jne     .fail
    ffree   st0                          ; clean up remaining scaling factor

    ; ========================================================================
    ; TEST 13: FPREM — partial remainder of 10.0 / 3.0
    ; FPREM: ST0 = REM(ST0 / ST1), result is 10 mod 3 = 1
    ; Push 3.0 (divisor) then 10.0 (dividend)
    ; ========================================================================
    fninit
    fld     dword [fpcs_r32_3p0]         ; ST1 = 3.0
    fld     dword [fpcs_r32_10p0]        ; ST0 = 10.0
    fprem                               ; ST0 = 10 mod 3 = 1.0
    fld     dword [fpcs_r32_1p0]
    fcompp                              ; compare 1.0 with result, pop
    fnstsw  ax
    and     ax, 0x4500
    cmp     ax, 0x4000
    jne     .fail
    ffree   st0                          ; clean up divisor

    ; ========================================================================
    ; TEST 14: FLDLG2 — log10(2) ≈ 0.30103, should be > 0.3 and < 0.31
    ; ========================================================================
    fninit
    fldlg2                              ; ST0 = log10(2)
    fcom    dword [fpcs_r32_0p3]
    fnstsw  ax
    and     ax, 0x4500
    cmp     ax, 0x0000                   ; > 0.3
    jne     .fail
    fcom    dword [fpcs_r32_0p31]
    fnstsw  ax
    and     ax, 0x4500
    cmp     ax, 0x0100                   ; < 0.31
    jne     .fail
    ffree   st0

    ; ========================================================================
    ; TEST 15: FLDLN2 — ln(2) ≈ 0.6931, should be > 0.69 and < 0.70
    ; ========================================================================
    fninit
    fldln2                              ; ST0 = ln(2)
    fcom    dword [fpcs_r32_0p69]
    fnstsw  ax
    and     ax, 0x4500
    cmp     ax, 0x0000                   ; > 0.69
    jne     .fail
    fcom    dword [fpcs_r32_0p70]
    fnstsw  ax
    and     ax, 0x4500
    cmp     ax, 0x0100                   ; < 0.70
    jne     .fail
    ffree   st0

    ; ========================================================================
    ; All tests passed
    ; ========================================================================
    mov     al, STATUS_PASS
    jmp     .cleanup

.fail:
    mov     al, STATUS_FAIL

.cleanup:
    fninit
    frstor  [fpcs_save_buf]

    pop     dx
    pop     cx
    pop     bx
    ret

;---------------------------------------------------------------------------
fpu_cs_cleanup:
    ret

; --- data ---
fpu_cs_name: db '8087 FPU Constants/Special', 0

fpcs_save_buf:   times 108 db 0

fpcs_r32_0p3:    dd 0.30
fpcs_r32_0p31:   dd 0.31
fpcs_r32_0p69:   dd 0.69
fpcs_r32_0p70:   dd 0.70
fpcs_r32_1p0:    dd 1.0
fpcs_r32_2p0:    dd 2.0
fpcs_r32_2p3:    dd 2.3
fpcs_r32_3p0:    dd 3.0
fpcs_r32_3p7:    dd 3.7
fpcs_r32_4p0:    dd 4.0
fpcs_r32_8p0:    dd 8.0
fpcs_r32_10p0:   dd 10.0
fpcs_r32_16p0:   dd 16.0
fpcs_r32_neg3p7: dd -3.7
fpcs_r32_neg4p0: dd -4.0
