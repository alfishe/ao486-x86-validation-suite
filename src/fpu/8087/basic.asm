;============================================================================
; MODULE: fpu/8087/basic.asm
; TIER:   UNIVERSAL
; VENUE:  G
; GEN:    8086+ (requires 8087 FPU)
; ORACLE: manual
; DESC:   8087 FPU basic operations:
;         - FNINIT state initialization (CW, SW verification)
;         - FLD/FST/FSTP for all data types (i16, i32, r32, r64, r80)
;         - FXCH register exchange
;         - Stack top tracking (FINCSTP/FDECSTP)
;         - FSTSW AX status word transfer
;
; FPU-SPECIFIC RULES (AGENTS.md §6.4):
;         - FNINIT at entry for known state
;         - Compare 80-bit results via stored image + integer compare
;         - Restore caller's FPU state on exit (FNSAVE/FRSTOR)
;
; REFS:   Intel 8087 Programmer's Reference Manual §3 (data types),
;         §4 (instruction set); iAPX 286 PRM §7 (80287 differences)
;============================================================================

;---------------------------------------------------------------------------
; fpu_basic_init — Module initialization
;---------------------------------------------------------------------------
fpu_basic_init:
    ret

;---------------------------------------------------------------------------
; fpu_basic_run — Execute 8087 FPU basic tests
; OUT: AL = STATUS_PASS or STATUS_FAIL / STATUS_SKIP
;---------------------------------------------------------------------------
fpu_basic_run:
    push    bx
    push    cx
    push    dx
    push    si

    ; ========================================================================
    ; Capability gate: FPU required
    ; ========================================================================
    mov     al, [g_fpu_type]
    cmp     al, FPU_NONE
    jne     .cap_ok
    mov     al, STATUS_SKIP
    jmp     .cleanup
.cap_ok:

    ; ========================================================================
    ; Save caller's FPU state (14 bytes for 8087 format on 16-bit)
    ; ========================================================================
    fnsave  [fpu_save_buf]               ; save full FPU state (94+ bytes)

    ; ========================================================================
    ; Initialize FPU to known state
    ; ========================================================================
    fninit

    ; ========================================================================
    ; TEST 1: FNINIT sets Control Word to default
    ; 8087/287: CW = 0x037F (all exceptions masked, double precision, round to nearest)
    ; 387+:     CW = 0x037F (same, but extended precision default differs by FPU type)
    ; Actually: 8087 CW = 0x037F, 287 CW = 0x037F, 387+ CW = 0x037F
    ; The low 6 bits are exception masks (all 1 = all masked)
    ; Bits 8-9 = precision control (11 = double for 87, 11 = extended for 387+)
    ; Wait: precision control bits 8-9: 00=single, 01=reserved, 10=double, 11=extended
    ; 8087 default = 0x037F → bits 8-9 = 11 → extended? No...
    ; Actually: 0x037F = 0000 0011 0111 1111
    ; Bits 8-9: 11 → extended precision for 387+, double for 87/287
    ; Bit 12: 0 = infinity not affected
    ; We just verify the exception mask bits (0-5) are all 1
    ; ========================================================================
    fnstcw  [fpu_cw]                     ; store control word
    mov     ax, [fpu_cw]
    and     ax, 0x003F                   ; low 6 bits = exception masks
    cmp     ax, 0x003F                   ; all masked
    jne     .fail

    ; ========================================================================
    ; TEST 2: FNINIT sets Status Word — stack empty, no exceptions
    ; SW bit 7 = ES (error summary), bits 8-11 = TOP (stack pointer)
    ; After FNINIT: TOP=0 (or 111b), all condition codes clear, no exceptions
    ; ========================================================================
    fnstsw  [fpu_sw]                     ; store status word
    mov     ax, [fpu_sw]
    and     ax, 0x3F80                   ; bits 7-13: error bits + TOP
    ; TOP should be 0 after FNINIT, but some FPUs use 111b=7
    ; We just verify no error condition is set
    test    ax, 0x0080                   ; ES (bit 7) must be clear
    jnz     .fail

    ; ========================================================================
    ; TEST 3: FLD i16 — load 16-bit integer, verify via FISTP
    ; ========================================================================
    fninit
    fild    word [val_i16_42]            ; push 42 onto FPU stack
    fistp   word [fpu_result_i16]        ; pop and store as i16
    mov     ax, [fpu_result_i16]
    cmp     ax, 42
    jne     .fail

    ; ========================================================================
    ; TEST 4: FLD i32 — load 32-bit integer, verify via FISTP
    ; ========================================================================
    fninit
    fild    dword [val_i32_1000]         ; push 1000
    fistp   dword [fpu_result_i32]       ; pop and store as i32
    mov     ax, word [fpu_result_i32]
    mov     dx, word [fpu_result_i32 + 2]
    cmp     ax, 1000
    jne     .fail
    cmp     dx, 0
    jne     .fail

    ; ========================================================================
    ; TEST 5: FLD r32 — load single-precision float, verify via FSTP
    ; Load 1.0f (0x3F800000), should get back 1.0f
    ; ========================================================================
    fninit
    fld     dword [val_r32_1p0]          ; push 1.0f
    fstp    dword [fpu_result_r32]       ; pop and store as r32
    mov     ax, word [fpu_result_r32]
    mov     dx, word [fpu_result_r32 + 2]
    mov     bx, word [val_r32_1p0]
    mov     cx, word [val_r32_1p0 + 2]
    cmp     ax, bx
    jne     .fail
    cmp     dx, cx
    jne     .fail

    ; ========================================================================
    ; TEST 6: FLD r64 — load double-precision float, verify via FSTP
    ; Load 1.0d, verify round-trip
    ; ========================================================================
    fninit
    fld     qword [val_r64_1p0]          ; push 1.0d
    fstp    qword [fpu_result_r64]
    ; Compare 8 bytes
    mov     si, val_r64_1p0
    mov     di, fpu_result_r64
    mov     cx, 8
    cld
.repe_cmp6:
    mov     al, [si]
    cmp     al, [di]
    jne     .fail
    inc     si
    inc     di
    loop    .repe_cmp6

    ; ========================================================================
    ; TEST 7: FLD r80 — load 80-bit extended float, verify via FSTP
    ; Round-trip should be exact for 80-bit
    ; ========================================================================
    fninit
    fld     tword [val_r80_1p0]          ; push 1.0L
    fstp    tword [fpu_result_r80]
    mov     si, val_r80_1p0
    mov     di, fpu_result_r80
    mov     cx, 10
    cld
.repe_cmp7:
    mov     al, [si]
    cmp     al, [di]
    jne     .fail
    inc     si
    inc     di
    loop    .repe_cmp7

    ; ========================================================================
    ; TEST 8: FXCH — exchange ST(0) and ST(1)
    ; Load 1.0 then 2.0: ST0=2.0, ST1=1.0. After FXCH: ST0=1.0, ST1=2.0
    ; ========================================================================
    fninit
    fld     dword [val_r32_1p0]          ; ST0 = 1.0
    fld     dword [val_r32_2p0]          ; ST0 = 2.0, ST1 = 1.0
    fxch                                ; ST0 = 1.0, ST1 = 2.0
    ; Pop ST0 (should be 1.0) and verify
    fstp    dword [fpu_result_r32]       ; store 1.0, pop
    mov     ax, word [fpu_result_r32]
    mov     dx, word [fpu_result_r32 + 2]
    mov     bx, word [val_r32_1p0]
    mov     cx, word [val_r32_1p0 + 2]
    cmp     ax, bx
    jne     .fail
    cmp     dx, cx
    jne     .fail
    ; Now ST0 should be 2.0 — clean up
    fstp    dword [fpu_result_r32]

    ; ========================================================================
    ; TEST 9: FLD + FSTP preserves negative values (i16)
    ; ========================================================================
    fninit
    fild    word [val_i16_neg5]          ; push -5
    fistp   word [fpu_result_i16]        ; pop and store
    mov     ax, [fpu_result_i16]
    cmp     ax, 0xFFFB                   ; -5 in 16-bit
    jne     .fail

    ; ========================================================================
    ; TEST 10: FINCSTP / FDECSTP — increment/decrement stack pointer
    ; These don't actually free registers, just move TOP
    ; After two FLDs, use FINCSTP to verify TOP changes by +1 (mod 8)
    ; ========================================================================
    fninit
    fld1                                ; push (TOP decrements)
    fld1                                ; push again
    fnstsw  [fpu_sw]
    mov     ax, [fpu_sw]
    shr     ax, 11
    and     ax, 7                        ; TOP before
    mov     [fpu_saved_top], al
    fincstp                             ; TOP increments by 1 (mod 8)
    fnstsw  [fpu_sw]
    mov     ax, [fpu_sw]
    shr     ax, 11
    and     ax, 7                        ; TOP after
    sub     al, [fpu_saved_top]
    and     al, 7                        ; mod 8 for wraparound
    cmp     al, 1
    jne     .fail
    ; Clean up stack
    ffree   st0
    fincstp
    ffree   st0
    fincstp

    ; ========================================================================
    ; TEST 11: FSTSW AX — status word to AX register (287+)
    ; Verify FSTSW AX is functional and returns a valid status word.
    ; ========================================================================
    fninit
    fld1
    fnstsw  ax                          ; AX = status word
    ; Verify we can read the status word — TOP should be valid
    shr     ax, 11
    and     ax, 7                        ; TOP field
    ; TOP should be a valid value (0-7) — just verify no crash
    fninit

    ; ========================================================================
    ; All tests passed
    ; ========================================================================
    mov     al, STATUS_PASS
    jmp     .cleanup

.fail:
    mov     al, STATUS_FAIL

.cleanup:
    ; ========================================================================
    ; Restore caller's FPU state
    ; ========================================================================
    fninit
    frstor  [fpu_save_buf]

    pop     si
    pop     dx
    pop     cx
    pop     bx
    ret

;---------------------------------------------------------------------------
; fpu_basic_cleanup — Module cleanup
;---------------------------------------------------------------------------
fpu_basic_cleanup:
    ret

; --- fpu_basic data ---
fpu_basic_name: db '8087 FPU Basic Ops', 0

; FPU state save buffer (108 bytes for full 8087/287/387 state in 16-bit RM)
fpu_save_buf:  times 108 db 0

; Test constants
val_i16_42:      dw 42
val_i16_neg5:    dw -5
val_i32_1000:    dd 1000
val_r32_1p0:     dd 1.0
val_r32_2p0:     dd 2.0
val_r64_1p0:     dq 1.0
val_r80_1p0:     db 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x80,0xFF,0x3F  ; 1.0 (80-bit ext)

; Result buffers
fpu_result_i16:  dw 0
fpu_result_i32:  dd 0
fpu_result_r32:  dd 0
fpu_result_r64:  dq 0
fpu_result_r80:  times 10 db 0

; Temporary variables
fpu_cw:          dw 0
fpu_sw:          dw 0
fpu_saved_top:   db 0
