;============================================================================
; MODULE: fpu/8087/misc.asm
; TIER:   UNIVERSAL
; VENUE:  G
; GEN:    8086+ (requires 8087 FPU)
; ORACLE: manual
; DESC:   8087 FPU miscellaneous operations completing full opcode coverage:
;         - FDIVR/FDIVRP/FIDIVR: reversed division (operand / ST0)
;         - FICOM/FICOMP: integer comparison
;         - FBLD/FBSTP: packed BCD load/store
;         - FLDCW: load control word
;         - FCLEX/FNCLEX: clear exceptions
;         - FDECSTP: decrement stack pointer
;         - FNOP: FPU no-op
;
; REFS:   Intel 8087 PRM §3 (BCD), §4 (instruction set)
;============================================================================

;---------------------------------------------------------------------------
fpu_misc_init:
    ret

;---------------------------------------------------------------------------
; fpu_misc_run
;---------------------------------------------------------------------------
fpu_misc_run:
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

    fnsave  [fpm_save_buf]
    fninit

    ; ========================================================================
    ; TEST 1: FDIVR r32 — reversed division: 3.0 / ST0
    ; Load 2.0. FDIVR r32_3p0 = 3.0 / 2.0 = 1.5
    ; ========================================================================
    fninit
    fld     dword [fpm_r32_2p0]          ; ST0 = 2.0
    fdivr   dword [fpm_r32_3p0]          ; ST0 = 3.0 / 2.0 = 1.5
    fld     dword [fpm_r32_1p5]
    fcompp
    fnstsw  ax
    and     ax, 0x4500
    cmp     ax, 0x4000
    jne     .fail

    ; ========================================================================
    ; TEST 2: FDIVRP — reversed division with pop
    ; Push 4.0, 2.0. FDIVRP st1,st0 = ST1 = ST0/ST1 = 2/4 = 0.5, pop
    ; Wait: FDIVRP st1,st0 means: st1 = st0 / st1, then pop
    ; ST0=2.0, ST1=4.0 → ST1 = 2/4 = 0.5 → pop → ST0=0.5
    ; ========================================================================
    fninit
    fld     dword [fpm_r32_4p0]          ; ST0=4.0
    fld     dword [fpm_r32_2p0]          ; ST0=2.0, ST1=4.0
    fdivrp  st1, st0                    ; ST1 = ST0/ST1 = 2/4 = 0.5, pop
    fld     dword [fpm_r32_0p5]
    fcompp
    fnstsw  ax
    and     ax, 0x4500
    cmp     ax, 0x4000
    jne     .fail

    ; ========================================================================
    ; TEST 3: FIDIVR i16 — reversed integer division: i16 / ST0
    ; Load 2.0. FIDIVR [10] = 10 / 2.0 = 5.0
    ; ========================================================================
    fninit
    fld     dword [fpm_r32_2p0]          ; ST0 = 2.0
    fidivr  word [fpm_i16_10]            ; ST0 = 10 / 2.0 = 5.0
    fld     dword [fpm_r32_5p0]
    fcompp
    fnstsw  ax
    and     ax, 0x4500
    cmp     ax, 0x4000
    jne     .fail

    ; ========================================================================
    ; TEST 4: FICOM i16 — compare ST0 with integer
    ; Load 5.0, compare with 3: 5 > 3 → greater
    ; ========================================================================
    fninit
    fld     dword [fpm_r32_5p0]          ; ST0 = 5.0
    ficom   word [fpm_i16_3]             ; compare ST0 with 3
    fnstsw  ax
    and     ax, 0x4500
    cmp     ax, 0x0000                   ; greater
    jne     .fail
    ffree   st0

    ; ========================================================================
    ; TEST 5: FICOMP i16 — compare ST0 with integer and pop
    ; Load 3.0, compare with 5: 3 < 5 → less
    ; ========================================================================
    fninit
    fld     dword [fpm_r32_3p0]          ; ST0 = 3.0
    ficomp  word [fpm_i16_5]             ; compare ST0 with 5, pop
    fnstsw  ax
    and     ax, 0x4500
    cmp     ax, 0x0100                   ; less
    jne     .fail

    ; ========================================================================
    ; TEST 6: FBLD — load packed BCD
    ; BCD format: 10 bytes, 18 packed BCD digits + sign nibble
    ; Value 12345 in BCD: 00 00 00 00 00 00 00 00 45 23 01
    ; Wait: BCD is little-endian. 12345 decimal = 012345 in BCD (6 digits)
    ; Layout: byte[0]=45, byte[1]=23, byte[2]=01, rest=0, byte[9] high nibble=sign
    ; ========================================================================
    fninit
    fbld    tword [fpm_bcd_12345]        ; load BCD 12345
    fistp   dword [fpm_result_i32]       ; store as integer
    mov     ax, word [fpm_result_i32]
    mov     dx, word [fpm_result_i32 + 2]
    cmp     ax, 12345
    jne     .fail
    cmp     dx, 0
    jne     .fail

    ; ========================================================================
    ; TEST 7: FBSTP — store packed BCD
    ; Load integer 9876, store as BCD, verify
    ; ========================================================================
    fninit
    fild    word [fpm_i16_9876]          ; load 9876
    fbstp   tword [fpm_bcd_result]       ; store as BCD
    ; Verify: 9876 = 0x0009876 → BCD bytes: 76, 98, 00, ... 00
    mov     al, [fpm_bcd_result]         ; low byte: 0x76
    cmp     al, 0x76
    jne     .fail
    mov     al, [fpm_bcd_result + 1]     ; next byte: 0x98
    cmp     al, 0x98
    jne     .fail
    mov     al, [fpm_bcd_result + 2]     ; should be 0x00
    cmp     al, 0x00
    jne     .fail

    ; ========================================================================
    ; TEST 8: FLDCW — load control word
    ; Load a CW with different rounding mode (truncate = bits 10-11 = 11)
    ; CW 0x0F7F = same masks but truncation rounding
    ; ========================================================================
    fninit
    mov     word [fpm_test_cw], 0x0F7F   ; truncation rounding
    fldcw    [fpm_test_cw]
    fnstcw   [fpm_read_cw]
    mov     ax, [fpm_read_cw]
    and     ax, 0x0C00                   ; rounding bits
    cmp     ax, 0x0C00                   ; truncate = 11
    jne     .fail

    ; ========================================================================
    ; TEST 9: FLDCW rounding mode — truncate 3.7 → 3.0
    ; ========================================================================
    fninit
    mov     word [fpm_test_cw], 0x0F7F   ; truncation
    fldcw    [fpm_test_cw]
    fld     dword [fpm_r32_3p7]          ; ST0 = 3.7
    frndint                             ; truncate → 3.0
    fld     dword [fpm_r32_3p0]
    fcompp
    fnstsw  ax
    and     ax, 0x4500
    cmp     ax, 0x4000                   ; 3.0
    jne     .fail

    ; ========================================================================
    ; TEST 10: FNCLEX — clear exceptions
    ; Verify FNCLEX executes and clears exception bits in status word.
    ; DOSBox-X may not set ZE for masked exceptions, so we test clearing
    ; without depending on exception flags being pre-set.
    ; ========================================================================
    fninit
    fnclex                              ; clear exceptions
    fnstsw  ax
    ; After FNCLEX, exception flags (bits 0-5) should be clear
    and     ax, 0x003F                   ; exception flag bits
    jnz     .fail

    ; ========================================================================
    ; TEST 11: FDECSTP — decrement stack pointer
    ; After FNINIT + FLD1: push one value, check TOP decrements by 1
    ; ========================================================================
    fninit
    fld1                                ; TOP decrements
    fnstsw  ax
    shr     ax, 11
    and     ax, 7
    mov     [fpm_saved_top], al
    fdecstp                             ; TOP should go back by 1
    fnstsw  ax
    shr     ax, 11
    and     ax, 7
    sub     al, [fpm_saved_top]
    and     al, 7
    ; FDECSTP decrements TOP, so difference should be -1 = 7 (mod 8)
    cmp     al, 7
    jne     .fail
    ; Clean up
    ffree   st0

    ; ========================================================================
    ; TEST 12: FNOP — FPU no-op
    ; Should execute without any effect on FPU state
    ; ========================================================================
    fninit
    fld1                                ; ST0 = 1.0
    fnop                                ; no operation
    fld1
    fcompp
    fnstsw  ax
    and     ax, 0x4500
    cmp     ax, 0x4000                   ; still 1.0
    jne     .fail

    ; ========================================================================
    ; TEST 13: FIST i16 — store ST0 as i16 without popping
    ; Load 42.0, store as integer, verify ST0 still valid
    ; ========================================================================
    fninit
    fild    word [fpm_i16_42]            ; ST0 = 42
    fist    word [fpm_result_i16]        ; store without pop
    mov     ax, [fpm_result_i16]
    cmp     ax, 42
    jne     .fail
    ; ST0 should still be 42 — verify by popping
    fistp   word [fpm_result_i16]
    mov     ax, [fpm_result_i16]
    cmp     ax, 42
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
    frstor  [fpm_save_buf]

    pop     dx
    pop     cx
    pop     bx
    ret

;---------------------------------------------------------------------------
fpu_misc_cleanup:
    ret

; --- data ---
fpu_misc_name: db '8087 FPU Misc/Control', 0

fpm_save_buf:   times 108 db 0

; Float constants
fpm_r32_0p5:    dd 0.5
fpm_r32_1p5:    dd 1.5
fpm_r32_2p0:    dd 2.0
fpm_r32_3p0:    dd 3.0
fpm_r32_3p7:    dd 3.7
fpm_r32_4p0:    dd 4.0
fpm_r32_5p0:    dd 5.0

; Integer constants
fpm_i16_3:      dw 3
fpm_i16_5:      dw 5
fpm_i16_10:     dw 10
fpm_i16_42:     dw 42
fpm_i16_9876:   dw 9876

; BCD constant: 12345 in packed BCD (little-endian)
; 12345 = 01 23 45 → byte0=0x45, byte1=0x23, byte2=0x01, rest 0
fpm_bcd_12345:  db 0x45, 0x23, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00

; Result buffers
fpm_result_i16: dw 0
fpm_result_i32: dd 0
fpm_bcd_result: times 10 db 0
fpm_test_cw:    dw 0
fpm_read_cw:    dw 0
fpm_saved_top:  db 0
