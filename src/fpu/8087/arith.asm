;============================================================================
; MODULE: fpu/8087/arith.asm
; TIER:   UNIVERSAL
; VENUE:  G
; GEN:    8086+ (requires 8087 FPU)
; ORACLE: manual
; DESC:   8087 FPU arithmetic operations:
;         - FADD/FSUB/FMUL/FDIV on register and memory operands
;         - FADDP/FSUBP/FMULP/FDIVP (pop variants)
;         - FIADD/FIMUL/FIDIV (integer memory operands)
;         - FSUBR/FSUBRP (reversed subtraction)
;         - FABS/FCHS (unary operations)
;
; Comparison pattern: push result + expected, FCOMPP, check C3=1,C2=0,C0=0
;
; REFS:   Intel 8087 PRM §4 (instruction set)
;============================================================================

;---------------------------------------------------------------------------
fpu_arith_init:
    ret

;---------------------------------------------------------------------------
; fpu_arith_run
;---------------------------------------------------------------------------
fpu_arith_run:
    push    bx
    push    cx
    push    dx
    push    si
    push    di

    ; Capability gate
    mov     al, [g_fpu_type]
    cmp     al, FPU_NONE
    jne     .cap_ok
    mov     al, STATUS_SKIP
    jmp     .cleanup
.cap_ok:

    fnsave  [fpa_save_buf]
    fninit

    ; TEST 1: FADD r32 — 1.5 + 2.5 = 4.0
    fninit
    fld     dword [fpa_r32_1p5]
    fadd    dword [fpa_r32_2p5]          ; ST0 = 4.0
    fld     dword [fpa_r32_4p0]          ; ST0=expected, ST1=result
    fcompp
    fnstsw  ax
    and     ax, 0x4500
    cmp     ax, 0x4000                   ; equal
    jne     .fail

    ; TEST 2: FSUB r32 — 10.0 - 3.0 = 7.0
    fninit
    fld     dword [fpa_r32_10p0]
    fsub    dword [fpa_r32_3p0]          ; ST0 = 7.0
    fld     dword [fpa_r32_7p0]
    fcompp
    fnstsw  ax
    and     ax, 0x4500
    cmp     ax, 0x4000
    jne     .fail

    ; TEST 3: FMUL r32 — 3.0 × 4.0 = 12.0
    fninit
    fld     dword [fpa_r32_3p0]
    fmul    dword [fpa_r32_4p0]          ; ST0 = 12.0
    fld     dword [fpa_r32_12p0]
    fcompp
    fnstsw  ax
    and     ax, 0x4500
    cmp     ax, 0x4000
    jne     .fail

    ; TEST 4: FDIV r32 — 15.0 / 3.0 = 5.0
    fninit
    fld     dword [fpa_r32_15p0]
    fdiv    dword [fpa_r32_3p0]          ; ST0 = 5.0
    fld     dword [fpa_r32_5p0]
    fcompp
    fnstsw  ax
    and     ax, 0x4500
    cmp     ax, 0x4000
    jne     .fail

    ; TEST 5: FADDP — push 1,1; FADD st1; FADDP st1 → result 3.0
    fninit
    fld1                                ; ST0=1.0
    fld1                                ; ST0=1.0, ST1=1.0
    fadd    st1                         ; ST0 = 2.0
    faddp   st1, st0                    ; ST1 = 3.0, pop → ST0=3.0
    fld     dword [fpa_r32_3p0]
    fcompp
    fnstsw  ax
    and     ax, 0x4500
    cmp     ax, 0x4000
    jne     .fail

    ; TEST 6: FSUBRP st1,st0 — reversed sub with pop
    ; Push 5,3: ST0=3, ST1=5. FSUBRP: ST1=ST0-ST1=3-5=-2, pop
    fninit
    fld     dword [fpa_r32_5p0]          ; ST0=5.0
    fld     dword [fpa_r32_3p0]          ; ST0=3.0, ST1=5.0
    fsubrp  st1, st0                    ; ST1=-2, pop → ST0=-2
    fld     dword [fpa_r32_neg2p0]
    fcompp
    fnstsw  ax
    and     ax, 0x4500
    cmp     ax, 0x4000
    jne     .fail

    ; TEST 7: FIADD i16 — 10.0 + 5 = 15.0
    fninit
    fld     dword [fpa_r32_10p0]
    fiadd   word [fpa_i16_5]             ; ST0 = 15.0
    fld     dword [fpa_r32_15p0]
    fcompp
    fnstsw  ax
    and     ax, 0x4500
    cmp     ax, 0x4000
    jne     .fail

    ; TEST 8: FIMUL i16 — 3.0 × 4 = 12.0
    fninit
    fld     dword [fpa_r32_3p0]
    fimul   word [fpa_i16_4]             ; ST0 = 12.0
    fld     dword [fpa_r32_12p0]
    fcompp
    fnstsw  ax
    and     ax, 0x4500
    cmp     ax, 0x4000
    jne     .fail

    ; TEST 9: FABS — |-3.0| = 3.0
    fninit
    fld     dword [fpa_r32_neg3p0]
    fabs                                ; ST0 = 3.0
    fld     dword [fpa_r32_3p0]
    fcompp
    fnstsw  ax
    and     ax, 0x4500
    cmp     ax, 0x4000
    jne     .fail

    ; TEST 10: FCHS — negate 5.0 → -5.0
    fninit
    fld     dword [fpa_r32_5p0]
    fchs                                ; ST0 = -5.0
    fld     dword [fpa_r32_neg5p0]
    fcompp
    fnstsw  ax
    and     ax, 0x4500
    cmp     ax, 0x4000
    jne     .fail

    ; TEST 11: FSUBR r32 — reversed: operand - ST0
    ; Load 10.0, FSUBR 3.0 = 3.0 - 10.0 = -7.0
    fninit
    fld     dword [fpa_r32_10p0]
    fsubr   dword [fpa_r32_3p0]          ; ST0 = 3.0 - 10.0 = -7.0
    fld     dword [fpa_r32_neg7p0]
    fcompp
    fnstsw  ax
    and     ax, 0x4500
    cmp     ax, 0x4000
    jne     .fail

    ; TEST 12: FMULP — 2.0 × 3.0 = 6.0
    fninit
    fld     dword [fpa_r32_2p0]          ; ST0=2.0
    fld     dword [fpa_r32_3p0]          ; ST0=3.0, ST1=2.0
    fmulp   st1, st0                    ; ST1=6, pop → ST0=6
    fld     dword [fpa_r32_6p0]
    fcompp
    fnstsw  ax
    and     ax, 0x4500
    cmp     ax, 0x4000
    jne     .fail

    ; TEST 13: FDIVP — 12.0 / 3.0 = 4.0
    fninit
    fld     dword [fpa_r32_12p0]         ; ST0=12.0
    fld     dword [fpa_r32_3p0]          ; ST0=3.0, ST1=12.0
    fdivp   st1, st0                    ; ST1=4, pop → ST0=4
    fld     dword [fpa_r32_4p0]
    fcompp
    fnstsw  ax
    and     ax, 0x4500
    cmp     ax, 0x4000
    jne     .fail

    ; TEST 14: FIDIV i16 — 20.0 / 5 = 4.0
    fninit
    fld     dword [fpa_r32_20p0]
    fidiv   word [fpa_i16_5]             ; ST0 = 4.0
    fld     dword [fpa_r32_4p0]
    fcompp
    fnstsw  ax
    and     ax, 0x4500
    cmp     ax, 0x4000
    jne     .fail

    mov     al, STATUS_PASS
    jmp     .cleanup

.fail:
    mov     al, STATUS_FAIL

.cleanup:
    fninit
    frstor  [fpa_save_buf]

    pop     di
    pop     si
    pop     dx
    pop     cx
    pop     bx
    ret

;---------------------------------------------------------------------------
fpu_arith_cleanup:
    ret

; --- data ---
fpu_arith_name: db '8087 FPU Arithmetic', 0

fpa_save_buf:   times 108 db 0

fpa_r32_1p5:    dd 1.5
fpa_r32_2p0:    dd 2.0
fpa_r32_2p5:    dd 2.5
fpa_r32_3p0:    dd 3.0
fpa_r32_4p0:    dd 4.0
fpa_r32_5p0:    dd 5.0
fpa_r32_6p0:    dd 6.0
fpa_r32_7p0:    dd 7.0
fpa_r32_10p0:   dd 10.0
fpa_r32_12p0:   dd 12.0
fpa_r32_15p0:   dd 15.0
fpa_r32_20p0:   dd 20.0
fpa_r32_neg2p0: dd -2.0
fpa_r32_neg3p0: dd -3.0
fpa_r32_neg5p0: dd -5.0
fpa_r32_neg7p0: dd -7.0

fpa_i16_5:      dw 5
fpa_i16_4:      dw 4
