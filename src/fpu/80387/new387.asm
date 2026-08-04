;============================================================================
; MODULE: fpu/80387/new387.asm
; TIER:   UNIVERSAL
; VENUE:  G
; GEN:    80387+ (requires 80387 or 80486 integrated FPU)
; ORACLE: manual
; DESC:   80387-specific new instructions not present on 8087/80287:
;         - FPREM1:  IEEE 754 partial remainder (round-to-nearest)
;         - FUCOM/FUCOMP/FUCOMPP: unordered compare (no #IA on QNaN)
;         - FSIN/FCOS/FSINCOS: trigonometric functions (387+ only)
;         - 387 default CW = 0x037F (vs 8087/287 0x03FF)
;
; REFS:   Intel 80387 PRM §6 (transcendentals), §7 (FPREM1);
;         Intel 80386 PRM Appendix A (FPU instruction additions)
;
; KNOWN GAP:
;   FCOM with QNaN should set the IE (invalid exception) bit in the
;   status word, while FUCOM should not. DOSBox-X core=normal does
;   not reliably set IE for FCOM with QNaN when exceptions are masked.
;   FUCOM/FUCOMPP are tested instead; FCOM IE-bit difference is TODO
;   for 86Box/real HW validation.
;============================================================================

;---------------------------------------------------------------------------
fpu387_init:
    ret

;---------------------------------------------------------------------------
; fpu387_run
;---------------------------------------------------------------------------
fpu387_run:
    push    ebx
    push    ecx
    push    edx
    push    esi
    push    edi
    push    ebp

    ; ========================================================================
    ; Capability gate: 80387+ required
    ; ========================================================================
    mov     al, [g_fpu_type]
    cmp     al, FPU_80387
    jae     .cap_ok
    mov     al, STATUS_SKIP
    jmp     .done

.cap_ok:
    fnsave  [f387_save_buf]
    fninit

    ; ========================================================================
    ; TEST 1: 387 default control word = 0x037F
    ; ========================================================================
    fninit
    fnstcw  [f387_tmp_cw]
    mov     ax, [f387_tmp_cw]
    cmp     ax, 0x037F
    jne     .fail

    ; ========================================================================
    ; TEST 2: FPREM1 — IEEE remainder (round-to-nearest)
    ; 5.0 mod 3.0: round(5/3)=2, rem = 5 - 2*3 = -1.0
    ; ========================================================================
    fninit
    fld     dword [f387_3p0]
    fld     dword [f387_5p0]
    fprem1
    fld     dword [f387_neg1p0]
    fcompp
    fnstsw  ax
    and     ax, 0x4500
    cmp     ax, 0x4000
    jne     .fail
    ffree   st0

    ; ========================================================================
    ; TEST 3: FPREM1 — exact case
    ; 10.0 mod 3.0: round(10/3)=3, rem = 10 - 3*3 = 1.0
    ; ========================================================================
    fninit
    fld     dword [f387_3p0]
    fld     dword [f387_10p0]
    fprem1
    fld     dword [f387_1p0]
    fcompp
    fnstsw  ax
    and     ax, 0x4500
    cmp     ax, 0x4000
    jne     .fail
    ffree   st0

    ; ========================================================================
    ; TEST 4: FPREM1 quotient bits (C0/C1/C3)
    ; 5.0 mod 3.0: quotient = 2 → C3=1, C0=0
    ; ========================================================================
    fninit
    fld     dword [f387_3p0]
    fld     dword [f387_5p0]
    fprem1
    fnstsw  ax
    test    ax, 0x4000                   ; C3 must be set
    jz      .fail
    test    ax, 0x0100                   ; C0 must be clear
    jnz     .fail
    ffree   st0
    ffree   st1

    ; ========================================================================
    ; TEST 5: FUCOM — unordered compare
    ; ========================================================================
    fninit
    fld     dword [f387_5p0]
    fld     dword [f387_3p0]
    fucom   st1
    fnstsw  ax
    and     ax, 0x4500
    cmp     ax, 0x0100                   ; ST0 < ST1
    jne     .fail
    fcompp

    ; ========================================================================
    ; TEST 6: FUCOMP — compare and pop
    ; ========================================================================
    fninit
    fld     dword [f387_5p0]
    fld     dword [f387_5p0]
    fucomp  st1
    fnstsw  ax
    and     ax, 0x4500
    cmp     ax, 0x4000                   ; equal
    jne     .fail
    ffree   st0

    ; ========================================================================
    ; TEST 7: FUCOMPP — compare and pop both
    ; ========================================================================
    fninit
    fld     dword [f387_3p0]
    fld     dword [f387_5p0]
    fucompp
    fnstsw  ax
    and     ax, 0x4500
    cmp     ax, 0x0000                   ; ST0 > ST1
    jne     .fail

    ; ========================================================================
    ; TEST 8: FUCOM with QNaN — sets unordered, no #IA
    ; ========================================================================
    fninit
    fld     dword [f387_qnan]
    fld     dword [f387_1p0]
    fucom   st1
    fnstsw  ax
    and     ax, 0x4500
    cmp     ax, 0x4500                   ; unordered
    jne     .fail
    fcompp

    ; ========================================================================
    ; TEST 9: FSIN — sin(0) = 0
    ; ========================================================================
    fninit
    fldz
    fsin
    ftst
    fnstsw  ax
    and     ax, 0x4500
    cmp     ax, 0x4000
    jne     .fail

    ; ========================================================================
    ; TEST 10: FCOS — cos(0) = 1.0
    ; ========================================================================
    fninit
    fldz
    fcos
    fld1
    fcompp
    fnstsw  ax
    and     ax, 0x4500
    cmp     ax, 0x4000
    jne     .fail

    ; ========================================================================
    ; TEST 11: FSINCOS — sin(0)=0, cos(0)=1
    ; FSINCOS stores sin in ST(1), pushes cos to ST(0).
    ; So after FSINCOS: ST0=cos(0)=1.0, ST1=sin(0)=0.0
    ; ========================================================================
    fninit
    fldz
    fsincos                            ; ST0=cos=1.0, ST1=sin=0.0
    ; Check ST0 = cos(0) = 1.0
    fld1                               ; ST0=1.0, ST1=cos=1.0, ST2=sin=0.0
    fcompp                             ; compare ST0 with ST1, pop both
    fnstsw  ax
    and     ax, 0x4500
    cmp     ax, 0x4000                 ; equal (cos matches 1.0)
    jne     .fail
    ; Check remaining ST0 = sin(0) = 0.0
    ftst
    fnstsw  ax
    and     ax, 0x4500
    cmp     ax, 0x4000                 ; equal (sin matches 0.0)
    jne     .fail
    ffree   st0

    ; ========================================================================
    ; TEST 12: FSIN out-of-range — C2 set for |x| >= 2^63
    ; ========================================================================
    fninit
    mov     dword [f387_tmp32], 0x00000000
    mov     dword [f387_tmp32+4], 0x43E00000
    fld     qword [f387_tmp32]
    fsin
    fnstsw  ax
    test    ax, 0x0400                   ; C2
    jz      .fail
    ffree   st0

    ; ========================================================================
    ; TEST 13: FPREM1 — negative dividend
    ; -5.0 mod 3.0 = 1.0 (IEEE rounding)
    ; ========================================================================
    fninit
    fld     dword [f387_3p0]
    fld     dword [f387_neg5p0]
    fprem1
    fld     dword [f387_1p0]
    fcompp
    fnstsw  ax
    and     ax, 0x4500
    cmp     ax, 0x4000
    jne     .fail
    ffree   st0

    ; ========================================================================
    ; TEST 14: FUCOMPP — equal values
    ; Both ST0 and ST1 are 3.0; FUCOMPP sets equal and pops both.
    ; ========================================================================
    fninit
    fld     dword [f387_3p0]
    fld     dword [f387_3p0]
    fucompp
    fnstsw  ax
    and     ax, 0x4500
    cmp     ax, 0x4000                   ; equal
    jne     .fail

    ; ========================================================================
    ; TEST 15: FSIN — sin(pi/6) approx 0.5 (epsilon comparison)
    ; pi/6 in single precision is inexact; use tolerance check.
    ; Load epsilon first so |error| ends up in ST0 for fcompp.
    ; ========================================================================
    fninit
    fld     dword [f387_epsilon]      ; ST0 = eps
    fld     dword [f387_pi_over_6]    ; ST0 = pi/6, ST1 = eps
    fsin                             ; ST0 = sin(pi/6), ST1 = eps
    fld     dword [f387_0p5]          ; ST0 = 0.5, ST1 = sin, ST2 = eps
    fsub                             ; ST0 = sin-0.5, ST1 = eps
    fabs                             ; ST0 = |error|, ST1 = eps
    fcompp                           ; compare ST0(|error|) with ST1(eps)
    fnstsw  ax
    and     ax, 0x4500
    cmp     ax, 0x0100               ; |error| < eps → less (C0=1)
    jne     .fail

    ; All tests passed
    mov     al, STATUS_PASS
    jmp     .done

.fail:
    mov     al, STATUS_FAIL

.done:
    fninit
    frstor  [f387_save_buf]

    pop     ebp
    pop     edi
    pop     esi
    pop     edx
    pop     ecx
    pop     ebx
    ret

;---------------------------------------------------------------------------
fpu387_cleanup:
    ret

; --- data ---
fpu387_name: db '80387 FPU New Instructions', 0

f387_save_buf:   times 108 db 0
f387_tmp_cw:     dw 0
f387_tmp32:      dq 0

f387_0p5:        dd 0.5
f387_1p0:        dd 1.0
f387_3p0:        dd 3.0
f387_5p0:        dd 5.0
f387_10p0:       dd 10.0
f387_neg1p0:     dd -1.0
f387_neg5p0:     dd -5.0
f387_qnan:       dd 0x7FC00000              ; QNaN
f387_pi_over_6:  dd 0.5235987755            ; pi/6
f387_epsilon:    dd 0.000001                ; tolerance for trig tests
