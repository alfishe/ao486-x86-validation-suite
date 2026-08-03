;============================================================================
; MODULE: fpu/8087/transc.asm
; TIER:   UNIVERSAL
; VENUE:  G
; GEN:    8086+ (requires 8087 FPU)
; ORACLE: manual
; DESC:   8087 FPU transcendental instructions:
;         - FPTAN: partial tangent (tan(ST0)), pushes 1.0 afterward
;         - FPATAN: partial arctangent (arctan(ST1/ST0)), pops ST0
;         - F2XM1: (2^ST0) - 1, for ST0 in [-1, 0.5]
;         - FYL2X: ST1 × log2(ST0), pops ST0
;         - FYL2XP1: ST1 × log2(ST0 + 1), for ST0 near 0, pops ST0
;         - FXTRACT: extract exponent and significand
;
; Transcendentals produce approximate results. Tests verify known
; mathematical identities and bounds rather than byte-exact values.
;
; REFS:   Intel 8087 PRM §4 (transcendental instructions);
;         Intel 80387 PRM §6.3 (range restrictions)
;============================================================================

;---------------------------------------------------------------------------
fpu_trans_init:
    ret

;---------------------------------------------------------------------------
; fpu_trans_run
;---------------------------------------------------------------------------
fpu_trans_run:
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

    fnsave  [fpt_save_buf]
    fninit

    ; ========================================================================
    ; TEST 1: F2XM1 — (2^0) - 1 = 0.0
    ; ST0 = 0.0 → 2^0 - 1 = 1 - 1 = 0
    ; ========================================================================
    fninit
    fldz                                ; ST0 = 0.0
    f2xm1                               ; ST0 = 2^0 - 1 = 0.0
    ftst                                ; compare with 0
    fnstsw  ax
    and     ax, 0x4500
    cmp     ax, 0x4000                   ; equal to zero
    jne     .fail

    ; ========================================================================
    ; TEST 2: F2XM1 — (2^1) - 1 = 1.0
    ; ST0 = 1.0 → 2^1 - 1 = 2 - 1 = 1
    ; ========================================================================
    fninit
    fld1                                ; ST0 = 1.0
    f2xm1                               ; ST0 = 2^1 - 1 = 1.0
    fld1
    fcompp
    fnstsw  ax
    and     ax, 0x4500
    cmp     ax, 0x4000                   ; equal to 1.0
    jne     .fail

    ; ========================================================================
    ; TEST 3: F2XM1 — (2^(-1)) - 1 = -0.5
    ; ST0 = -1.0 → 2^(-1) - 1 = 0.5 - 1 = -0.5
    ; ========================================================================
    fninit
    fld1                                ; ST0 = 1.0
    fchs                                ; ST0 = -1.0
    f2xm1                               ; ST0 = 2^(-1) - 1 = -0.5
    fld     dword [fpt_r32_neg0p5]
    fcompp
    fnstsw  ax
    and     ax, 0x4500
    cmp     ax, 0x4000
    jne     .fail

    ; ========================================================================
    ; TEST 4: FYL2X — 1.0 × log2(2.0) = 1.0 × 1.0 = 1.0
    ; FYL2X: ST1 = ST1 × log2(ST0), pop ST0
    ; Push 1.0 (ST1), then 2.0 (ST0): result = 1.0 × log2(2.0) = 1.0
    ; ========================================================================
    fninit
    fld1                                ; ST1 = 1.0
    fld     dword [fpt_r32_2p0]         ; ST0 = 2.0
    fyl2x                               ; ST0 = 1.0 × log2(2.0) = 1.0
    fld1
    fcompp
    fnstsw  ax
    and     ax, 0x4500
    cmp     ax, 0x4000
    jne     .fail

    ; ========================================================================
    ; TEST 5: FYL2X — 1.0 × log2(8.0) = 3.0
    ; log2(8) = 3 exactly
    ; ========================================================================
    fninit
    fld1                                ; ST1 = 1.0
    fld     dword [fpt_r32_8p0]         ; ST0 = 8.0
    fyl2x                               ; ST0 = 1.0 × 3.0 = 3.0
    fld     dword [fpt_r32_3p0]
    fcompp
    fnstsw  ax
    and     ax, 0x4500
    cmp     ax, 0x4000
    jne     .fail

    ; ========================================================================
    ; TEST 6: FYL2XP1 — 1.0 × log2(0 + 1) = log2(1) = 0
    ; FYL2XP1: ST1 = ST1 × log2(ST0 + 1), pop ST0
    ; Valid range for ST0: 0 ≤ |ST0| < 0.293
    ; Push 1.0 (ST1), then 0.0 (ST0): result = 1.0 × log2(0+1) = 0
    ; ========================================================================
    fninit
    fld1                                ; ST1 = 1.0
    fldz                                ; ST0 = 0.0
    fyl2xp1                             ; ST0 = 1.0 × log2(1) = 0.0
    ftst
    fnstsw  ax
    and     ax, 0x4500
    cmp     ax, 0x4000                   ; equal to zero
    jne     .fail

    ; ========================================================================
    ; TEST 7: FPTAN — tan(0) = 0, and pushes 1.0
    ; FPTAN computes tan(ST0), result in ST0, then pushes 1.0
    ; After FPTAN: ST0=1.0, ST1=tan(angle)
    ; tan(0) = 0, so ST1=0 and ST0=1.0
    ; ========================================================================
    fninit
    fldz                                ; ST0 = 0.0
    fptan                               ; ST0=1.0, ST1=tan(0)=0.0
    ; Check ST0 = 1.0
    fld1
    fcompp                              ; compare ST0 (1.0 from FPTAN) with 1.0
    fnstsw  ax
    and     ax, 0x4500
    cmp     ax, 0x4000
    jne     .fail
    ; Now ST0 = tan(0) = 0.0
    ftst
    fnstsw  ax
    and     ax, 0x4500
    cmp     ax, 0x4000                   ; equal to zero
    jne     .fail
    ffree   st0                         ; clean up

    ; ========================================================================
    ; TEST 8: FPTAN — tan(pi/4) ≈ 1.0
    ; pi/4 ≈ 0.7854, tan(pi/4) = 1.0
    ; Use FLDPI then divide by 4: pi/4
    ; FPTAN pushes 1.0 afterward — pop it, then verify tan result
    ; ========================================================================
    fninit
    fldpi                               ; ST0 = pi
    fld     dword [fpt_r32_4p0]         ; ST0=4, ST1=pi
    fdivp                               ; ST0 = pi/4
    fptan                               ; ST0=1.0, ST1=tan(pi/4)≈1.0
    ; Pop the 1.0 that FPTAN pushed
    fstp    dword [fpt_tmp]             ; ST0 = tan(pi/4)
    ; Verify tan(pi/4) is close to 1.0 (may not be exact due to rounding)
    fcom    dword [fpt_r32_0p99]
    fnstsw  ax
    and     ax, 0x4500
    cmp     ax, 0x0000                   ; tan(pi/4) > 0.99
    jne     .fail
    fcom    dword [fpt_r32_1p01]
    fnstsw  ax
    and     ax, 0x4500
    cmp     ax, 0x0100                   ; tan(pi/4) < 1.01
    jne     .fail
    ffree   st0

    ; ========================================================================
    ; TEST 9: FPATAN — arctan(1.0/1.0) = pi/4 ≈ 0.7854
    ; FPATAN: ST1 = arctan(ST1/ST0), pop ST0
    ; Push 1.0 (ST1), 1.0 (ST0): result = arctan(1/1) = pi/4
    ; pi/4 ≈ 0.7854
    ; ========================================================================
    fninit
    fld1                                ; ST1 = 1.0
    fld1                                ; ST0 = 1.0
    fpatan                              ; ST0 = arctan(1.0) = pi/4 ≈ 0.7854
    ; Verify: pi/4 > 0.78 and pi/4 < 0.79
    fcom    dword [fpt_r32_0p78]
    fnstsw  ax
    and     ax, 0x4500
    cmp     ax, 0x0000                   ; pi/4 > 0.78
    jne     .fail
    fcom    dword [fpt_r32_0p79]
    fnstsw  ax
    and     ax, 0x4500
    cmp     ax, 0x0100                   ; pi/4 < 0.79
    jne     .fail
    ffree   st0

    ; ========================================================================
    ; TEST 10: FPATAN — arctan(0/1) = 0
    ; Push 1.0 (ST1), 0.0 (ST0): result = arctan(1/0)... wait
    ; FPATAN: arctan(ST1/ST0). ST1=1, ST0=0 → arctan(+Inf) = pi/2
    ; Let me test arctan(0/1)=0: ST1=0, ST0=1 → arctan(0/1)=0
    ; ========================================================================
    fninit
    fldz                                ; ST1 = 0.0
    fld1                                ; ST0 = 1.0
    fpatan                              ; ST0 = arctan(0/1) = 0.0
    ftst
    fnstsw  ax
    and     ax, 0x4500
    cmp     ax, 0x4000                   ; equal to zero
    jne     .fail

    ; ========================================================================
    ; TEST 11: FXTRACT — extract exponent and significand from 4.0
    ; 4.0 = 1.0 (significand) × 2^2 (exponent)
    ; Per Intel manual: ST(0)=significand, ST(1)=exponent after FXTRACT
    ; ========================================================================
    fninit
    fld     dword [fpt_r32_4p0]         ; ST0 = 4.0
    fxtract                             ; ST0=1.0 (sig), ST1=2.0 (exp)
    ; Check significand = 1.0 (ST0)
    fld1                                ; push 1.0 for comparison
    fcompp                              ; compare ST0 (1.0 from us) with ST1 (sig)
    fnstsw  ax
    and     ax, 0x4500
    cmp     ax, 0x4000                   ; significand = 1.0
    jne     .fail
    ; Now ST0 = exponent (2.0)
    fld     dword [fpt_r32_2p0]
    fcompp
    fnstsw  ax
    and     ax, 0x4500
    cmp     ax, 0x4000                   ; exponent = 2.0
    jne     .fail

    ; ========================================================================
    ; TEST 12: FXTRACT — extract from 8.0 = 1.0 × 2^3
    ; ========================================================================
    fninit
    fld     dword [fpt_r32_8p0]         ; ST0 = 8.0
    fxtract                             ; ST0=1.0 (sig), ST1=3.0 (exp)
    fld1
    fcompp                              ; check sig=1.0
    fnstsw  ax
    and     ax, 0x4500
    cmp     ax, 0x4000
    jne     .fail
    fld     dword [fpt_r32_3p0]
    fcompp                              ; check exp=3.0
    fnstsw  ax
    and     ax, 0x4500
    cmp     ax, 0x4000
    jne     .fail

    ; ========================================================================
    ; All tests passed
    ; ========================================================================
    mov     al, STATUS_PASS
    jmp     .cleanup

.fail:
    mov     al, STATUS_FAIL

.cleanup:
    fninit
    frstor  [fpt_save_buf]

    pop     dx
    pop     cx
    pop     bx
    ret

;---------------------------------------------------------------------------
fpu_trans_cleanup:
    ret

; --- data ---
fpu_trans_name: db '8087 FPU Transcendentals', 0

fpt_save_buf:   times 108 db 0

fpt_r32_0p78:   dd 0.78
fpt_r32_0p79:   dd 0.79
fpt_r32_0p99:   dd 0.99
fpt_r32_1p01:   dd 1.01
fpt_r32_2p0:    dd 2.0
fpt_r32_3p0:    dd 3.0
fpt_r32_4p0:    dd 4.0
fpt_r32_8p0:    dd 8.0
fpt_r32_neg0p5: dd -0.5
fpt_tmp:        dd 0
