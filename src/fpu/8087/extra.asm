;============================================================================
; MODULE: fpu/8087/extra.asm
; TIER:   UNIVERSAL
; VENUE:  G
; GEN:    8086+ (requires 8087 FPU)
; ORACLE: manual
; DESC:   8087 FPU remaining opcode coverage — fills all gaps from audit:
;         - FISUB/FISUBR m16i: integer subtract (normal + reversed)
;         - FILD m64i / FISTP m64i: 64-bit integer load/store
;         - FST m32r: store without pop
;         - FLD ST(i): register-to-register copy
;         - FSUBP: subtract with pop (non-reversed)
;         - FIST m32i: store 32-bit integer without pop
;         - FFREE: free register (tag word verification)
;         - FNSTENV/FLDENV: environment save/restore
;         - FIADD/FIMUL/FISUB/FISUBR/FIDIV/FIDIVR/FICOM/FICOMP m32i (DA group)
;         - FADD/FMUL/FSUB/FSUBR/FDIV/FDIVR/FCOM/FCOMP m64r (DC group)
;
; REFS:   Intel 8087 PRM §3 (data types), §4 (instruction set)
;============================================================================

;---------------------------------------------------------------------------
fpu_extra_init:
    ret

;---------------------------------------------------------------------------
; fpu_extra_run
;---------------------------------------------------------------------------
fpu_extra_run:
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

    fnsave  [fpx_save_buf]
    fninit

    ; ========================================================================
    ; TEST 1: FISUB m16i — 10.0 - 5 = 5.0
    ; ========================================================================
    fninit
    fld     dword [fpx_r32_10p0]
    fisub   word [fpx_i16_5]              ; ST0 = 10.0 - 5 = 5.0
    fld     dword [fpx_r32_5p0]
    fcompp
    fnstsw  ax
    and     ax, 0x4500
    cmp     ax, 0x4000
    jne     .fail

    ; ========================================================================
    ; TEST 2: FISUBR m16i — 5 - 10.0 = -5.0
    ; ========================================================================
    fninit
    fld     dword [fpx_r32_10p0]
    fisubr  word [fpx_i16_5]             ; ST0 = 5 - 10.0 = -5.0
    fld     dword [fpx_r32_neg5p0]
    fcompp
    fnstsw  ax
    and     ax, 0x4500
    cmp     ax, 0x4000
    jne     .fail

    ; ========================================================================
    ; TEST 3: FILD m64i — load 64-bit integer (4294967296 = 2^32)
    ; Verify via FISTP m64i round-trip
    ; ========================================================================
    fninit
    fild    qword [fpx_i64_2pow32]       ; ST0 = 4294967296
    fistp   qword [fpx_result_i64]       ; store as 64-bit int
    ; Verify low dword = 0, high dword = 1
    mov     ax, word [fpx_result_i64]
    cmp     ax, 0
    jne     .fail
    mov     ax, word [fpx_result_i64 + 2]
    cmp     ax, 0
    jne     .fail
    mov     ax, word [fpx_result_i64 + 4]
    cmp     ax, 1
    jne     .fail
    mov     ax, word [fpx_result_i64 + 6]
    cmp     ax, 0
    jne     .fail

    ; ========================================================================
    ; TEST 4: FST m32r — store without pop
    ; FST stores ST0 to memory but leaves ST0 on stack
    ; ========================================================================
    fninit
    fld     dword [fpx_r32_5p0]          ; ST0 = 5.0
    fst     dword [fpx_result_r32]       ; store WITHOUT pop
    ; Verify memory has 5.0
    mov     ax, word [fpx_result_r32]
    mov     dx, word [fpx_result_r32 + 2]
    mov     bx, word [fpx_r32_5p0]
    mov     cx, word [fpx_r32_5p0 + 2]
    cmp     ax, bx
    jne     .fail
    cmp     dx, cx
    jne     .fail
    ; ST0 should still be 5.0 — pop and verify
    fstp    dword [fpx_result_r32]
    mov     ax, word [fpx_result_r32]
    mov     dx, word [fpx_result_r32 + 2]
    cmp     ax, bx
    jne     .fail
    cmp     dx, cx
    jne     .fail

    ; ========================================================================
    ; TEST 5: FSUBP ST(i),ST — subtract with pop (non-reversed)
    ; Push 10.0, 3.0: FSUBP st1,st0 → ST1=ST1-ST0=10-3=7, pop → ST0=7
    ; ========================================================================
    fninit
    fld     dword [fpx_r32_10p0]         ; ST0=10.0
    fld     dword [fpx_r32_3p0]          ; ST0=3.0, ST1=10.0
    fsubp   st1, st0                    ; ST1=10-3=7, pop → ST0=7
    fld     dword [fpx_r32_7p0]
    fcompp
    fnstsw  ax
    and     ax, 0x4500
    cmp     ax, 0x4000
    jne     .fail

    ; ========================================================================
    ; TEST 6: FLD ST(0) — duplicate top of stack
    ; FLD1 → ST0=1.0. FLD ST(0) → ST0=1.0, ST1=1.0. FADDP → 2.0
    ; ========================================================================
    fninit
    fld1                                ; ST0=1.0
    fld     st0                         ; ST0=1.0(copy), ST1=1.0
    faddp   st1, st0                   ; ST1=2.0, pop → ST0=2.0
    fld     dword [fpx_r32_2p0]
    fcompp
    fnstsw  ax
    and     ax, 0x4500
    cmp     ax, 0x4000
    jne     .fail

    ; ========================================================================
    ; TEST 7: FIST m32i — store 32-bit integer without pop
    ; Load 1000, FIST stores without pop, then FISTP pops
    ; ========================================================================
    fninit
    fild    dword [fpx_i32_1000]        ; ST0 = 1000
    fist    dword [fpx_result_i32]      ; store without pop
    mov     ax, word [fpx_result_i32]
    mov     dx, word [fpx_result_i32 + 2]
    cmp     ax, 1000
    jne     .fail
    cmp     dx, 0
    jne     .fail
    ; ST0 still valid — pop and verify
    fistp   dword [fpx_result_i32]
    mov     ax, word [fpx_result_i32]
    mov     dx, word [fpx_result_i32 + 2]
    cmp     ax, 1000
    jne     .fail
    cmp     dx, 0
    jne     .fail

    ; ========================================================================
    ; TEST 8: FIADD m32i — 10.0 + 5 (i32) = 15.0
    ; ========================================================================
    fninit
    fld     dword [fpx_r32_10p0]
    fiadd   dword [fpx_i32_5]           ; ST0 = 15.0
    fld     dword [fpx_r32_15p0]
    fcompp
    fnstsw  ax
    and     ax, 0x4500
    cmp     ax, 0x4000
    jne     .fail

    ; ========================================================================
    ; TEST 9: FIMUL m32i — 3.0 × 4 (i32) = 12.0
    ; ========================================================================
    fninit
    fld     dword [fpx_r32_3p0]
    fimul   dword [fpx_i32_4]           ; ST0 = 12.0
    fld     dword [fpx_r32_12p0]
    fcompp
    fnstsw  ax
    and     ax, 0x4500
    cmp     ax, 0x4000
    jne     .fail

    ; ========================================================================
    ; TEST 10: FISUB m32i — 10.0 - 3 (i32) = 7.0
    ; ========================================================================
    fninit
    fld     dword [fpx_r32_10p0]
    fisub   dword [fpx_i32_3]           ; ST0 = 7.0
    fld     dword [fpx_r32_7p0]
    fcompp
    fnstsw  ax
    and     ax, 0x4500
    cmp     ax, 0x4000
    jne     .fail

    ; ========================================================================
    ; TEST 11: FISUBR m32i — 3 - 10.0 = -7.0
    ; ========================================================================
    fninit
    fld     dword [fpx_r32_10p0]
    fisubr  dword [fpx_i32_3]          ; ST0 = 3 - 10.0 = -7.0
    fld     dword [fpx_r32_neg7p0]
    fcompp
    fnstsw  ax
    and     ax, 0x4500
    cmp     ax, 0x4000
    jne     .fail

    ; ========================================================================
    ; TEST 12: FIDIV m32i — 20.0 / 5 (i32) = 4.0
    ; ========================================================================
    fninit
    fld     dword [fpx_r32_20p0]
    fidiv   dword [fpx_i32_5]           ; ST0 = 4.0
    fld     dword [fpx_r32_4p0]
    fcompp
    fnstsw  ax
    and     ax, 0x4500
    cmp     ax, 0x4000
    jne     .fail

    ; ========================================================================
    ; TEST 13: FIDIVR m32i — 5 / 10.0 = 0.5
    ; ========================================================================
    fninit
    fld     dword [fpx_r32_10p0]
    fidivr  dword [fpx_i32_5]          ; ST0 = 5 / 10.0 = 0.5
    fld     dword [fpx_r32_0p5]
    fcompp
    fnstsw  ax
    and     ax, 0x4500
    cmp     ax, 0x4000
    jne     .fail

    ; ========================================================================
    ; TEST 14: FICOM m32i — 5.0 vs 3 (i32) → greater
    ; ========================================================================
    fninit
    fld     dword [fpx_r32_5p0]
    ficom   dword [fpx_i32_3]          ; compare ST0 with 3
    fnstsw  ax
    and     ax, 0x4500
    cmp     ax, 0x0000                  ; greater
    jne     .fail
    ffree   st0

    ; ========================================================================
    ; TEST 15: FICOMP m32i — 3.0 vs 5 (i32) → less, and pop
    ; ========================================================================
    fninit
    fld     dword [fpx_r32_3p0]
    ficomp  dword [fpx_i32_5]          ; compare ST0 with 5, pop
    fnstsw  ax
    and     ax, 0x4500
    cmp     ax, 0x0100                  ; less
    jne     .fail

    ; ========================================================================
    ; TEST 16: FADD m64r — 1.5 + 2.5 = 4.0 (double-precision operands)
    ; ========================================================================
    fninit
    fld     qword [fpx_r64_1p5]
    fadd    qword [fpx_r64_2p5]         ; ST0 = 4.0
    fld     dword [fpx_r32_4p0]
    fcompp
    fnstsw  ax
    and     ax, 0x4500
    cmp     ax, 0x4000
    jne     .fail

    ; ========================================================================
    ; TEST 17: FMUL m64r — 3.0 × 4.0 = 12.0 (double-precision operands)
    ; ========================================================================
    fninit
    fld     qword [fpx_r64_3p0]
    fmul    qword [fpx_r64_4p0]         ; ST0 = 12.0
    fld     dword [fpx_r32_12p0]
    fcompp
    fnstsw  ax
    and     ax, 0x4500
    cmp     ax, 0x4000
    jne     .fail

    ; ========================================================================
    ; TEST 18: FSUB m64r — 10.0 - 3.0 = 7.0 (double-precision operands)
    ; ========================================================================
    fninit
    fld     qword [fpx_r64_10p0]
    fsub    qword [fpx_r64_3p0]         ; ST0 = 7.0
    fld     dword [fpx_r32_7p0]
    fcompp
    fnstsw  ax
    and     ax, 0x4500
    cmp     ax, 0x4000
    jne     .fail

    ; ========================================================================
    ; TEST 19: FSUBR m64r — 3.0 - 10.0 = -7.0 (double-precision operands)
    ; ========================================================================
    fninit
    fld     qword [fpx_r64_10p0]
    fsubr   qword [fpx_r64_3p0]         ; ST0 = 3.0 - 10.0 = -7.0
    fld     dword [fpx_r32_neg7p0]
    fcompp
    fnstsw  ax
    and     ax, 0x4500
    cmp     ax, 0x4000
    jne     .fail

    ; ========================================================================
    ; TEST 20: FDIV m64r — 15.0 / 3.0 = 5.0 (double-precision operands)
    ; ========================================================================
    fninit
    fld     qword [fpx_r64_15p0]
    fdiv    qword [fpx_r64_3p0]         ; ST0 = 5.0
    fld     dword [fpx_r32_5p0]
    fcompp
    fnstsw  ax
    and     ax, 0x4500
    cmp     ax, 0x4000
    jne     .fail

    ; ========================================================================
    ; TEST 21: FDIVR m64r — 3.0 / 15.0... wait: FDIVR = operand/ST0
    ; Load 2.0, FDIVR [10.0] → 10.0/2.0 = 5.0
    ; ========================================================================
    fninit
    fld     qword [fpx_r64_2p0]
    fdivr   qword [fpx_r64_10p0]        ; ST0 = 10.0/2.0 = 5.0
    fld     dword [fpx_r32_5p0]
    fcompp
    fnstsw  ax
    and     ax, 0x4500
    cmp     ax, 0x4000
    jne     .fail

    ; ========================================================================
    ; TEST 22: FCOM m64r — 5.0 vs 3.0 → greater (double-precision)
    ; ========================================================================
    fninit
    fld     qword [fpx_r64_5p0]
    fcom    qword [fpx_r64_3p0]
    fnstsw  ax
    and     ax, 0x4500
    cmp     ax, 0x0000                  ; greater
    jne     .fail
    ffree   st0

    ; ========================================================================
    ; TEST 23: FCOMP m64r — 3.0 vs 5.0 → less, pop (double-precision)
    ; ========================================================================
    fninit
    fld     qword [fpx_r64_3p0]
    fcomp   qword [fpx_r64_5p0]
    fnstsw  ax
    and     ax, 0x4500
    cmp     ax, 0x0100                  ; less
    jne     .fail

    ; ========================================================================
    ; TEST 24: FFREE ST(0) — free register, verify tag word via FSTENV
    ; After FNINIT: all tags empty (TW=0xFFFF)
    ; After FLD1: one tag becomes valid (TW != 0xFFFF)
    ; After FFREE ST0: tag returns to empty (TW = 0xFFFF)
    ; ========================================================================
    fninit
    fnstenv [fpx_env_buf]               ; save env (14 bytes in 16-bit RM)
    mov     ax, [fpx_env_buf + 4]       ; tag word at offset 4
    mov     [fpx_saved_tw], ax          ; should be 0xFFFF (all empty)
    fld1                                ; push — one tag becomes valid
    fnstenv [fpx_env_buf]
    mov     ax, [fpx_env_buf + 4]
    cmp     ax, [fpx_saved_tw]          ; should differ (one reg now valid)
    je      .fail
    ffree   st0                         ; mark ST0 as empty
    fnstenv [fpx_env_buf]
    mov     ax, [fpx_env_buf + 4]
    cmp     ax, [fpx_saved_tw]          ; should be back to all-empty
    jne     .fail

    ; ========================================================================
    ; TEST 25: FNSTENV + FLDENV — environment save/restore round-trip
    ; Save env (CW=round-to-nearest), change CW to truncate, FLDENV restores
    ; ========================================================================
    fninit
    fnstenv [fpx_env_buf]               ; save env with default CW
    ; Change rounding mode via FLDCW
    mov     word [fpx_alt_cw], 0x0F7F   ; truncate rounding (bits 10-11 = 11)
    fldcw   [fpx_alt_cw]
    fnstcw  [fpx_verify_cw]
    mov     ax, [fpx_verify_cw]
    and     ax, 0x0C00                  ; rounding bits
    cmp     ax, 0x0C00                  ; truncate
    jne     .fail
    ; Restore environment via FLDENV — CW should go back to round-to-nearest
    fldenv  [fpx_env_buf]
    fnstcw  [fpx_verify_cw]
    mov     ax, [fpx_verify_cw]
    and     ax, 0x0C00                  ; rounding bits
    cmp     ax, 0x0000                  ; round-to-nearest restored
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
    frstor  [fpx_save_buf]

    pop     di
    pop     si
    pop     dx
    pop     cx
    pop     bx
    ret

;---------------------------------------------------------------------------
fpu_extra_cleanup:
    ret

; --- data ---
fpu_extra_name: db '8087 FPU Complete Coverage', 0

fpx_save_buf:   times 108 db 0

; --- r32 constants (for expected-value comparison) ---
fpx_r32_0p5:    dd 0.5
fpx_r32_2p0:    dd 2.0
fpx_r32_3p0:    dd 3.0
fpx_r32_4p0:    dd 4.0
fpx_r32_5p0:    dd 5.0
fpx_r32_7p0:    dd 7.0
fpx_r32_10p0:   dd 10.0
fpx_r32_12p0:   dd 12.0
fpx_r32_15p0:   dd 15.0
fpx_r32_20p0:   dd 20.0
fpx_r32_neg5p0: dd -5.0
fpx_r32_neg7p0: dd -7.0

; --- r64 constants (double-precision operands for DC group tests) ---
fpx_r64_1p5:    dq 1.5
fpx_r64_2p0:    dq 2.0
fpx_r64_2p5:    dq 2.5
fpx_r64_3p0:    dq 3.0
fpx_r64_4p0:    dq 4.0
fpx_r64_5p0:    dq 5.0
fpx_r64_10p0:   dq 10.0
fpx_r64_15p0:   dq 15.0

; --- i16 constants ---
fpx_i16_5:      dw 5

; --- i32 constants ---
fpx_i32_3:      dd 3
fpx_i32_4:      dd 4
fpx_i32_5:      dd 5
fpx_i32_1000:   dd 1000

; --- i64 constant ---
fpx_i64_2pow32: dq 4294967296            ; 2^32

; --- result buffers ---
fpx_result_r32:  dd 0
fpx_result_i32:  dd 0
fpx_result_i64:  dq 0

; --- environment test buffers ---
fpx_env_buf:    times 28 db 0            ; 14 bytes for 16-bit RM (extra for safety)
fpx_saved_tw:   dw 0
fpx_alt_cw:     dw 0
fpx_verify_cw:  dw 0
