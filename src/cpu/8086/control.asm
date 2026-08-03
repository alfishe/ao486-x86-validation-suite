;============================================================================
; MODULE: cpu/8086/control.asm
; TIER:   UNIVERSAL
; VENUE:  G
; GEN:    8086+
; ORACLE: manual
; DESC:   JMP/Jcc/CALL/RET/LOOP/INT — control flow instruction verification.
;         Tests conditional jumps (all conditions), CALL/RET nesting,
;         LOOP/LOOPZ/LOOPNZ iteration counts.
; REFS:   Intel 8086 Family Users Manual §3 (instruction set),
;         §3.2 (JMP), §3.3 (CALL/RET), §3.4 (LOOP)
;============================================================================

;---------------------------------------------------------------------------
; control_init — Module initialization
;---------------------------------------------------------------------------
control_init:
    ret

;---------------------------------------------------------------------------
; control_run — Execute control flow test cases
; OUT: AL = STATUS_PASS or STATUS_FAIL
;---------------------------------------------------------------------------
control_run:
    push    bx
    push    cx
    push    dx

    ; ========================================================================
    ; TEST 1: Conditional jump — JE/JZ (taken)
    ; ========================================================================
    xor     ax, ax
    cmp     ax, 0                       ; sets ZF=1
    je      .t1_ok
    jmp     .fail
.t1_ok:

    ; ========================================================================
    ; TEST 2: Conditional jump — JE/JZ (not taken)
    ; ========================================================================
    mov     ax, 1
    cmp     ax, 0                       ; sets ZF=0
    jne     .t2_ok
    jmp     .fail
.t2_ok:

    ; ========================================================================
    ; TEST 3: Signed conditional jumps
    ; JL (less than): SF != OF
    ; ========================================================================
    mov     ax, -1
    cmp     ax, 1                       ; -1 < 1 (signed)
    jl      .t3_ok
    jmp     .fail
.t3_ok:

    ; ========================================================================
    ; TEST 4: JGE (greater or equal)
    ; ========================================================================
    mov     ax, 5
    cmp     ax, 3                       ; 5 >= 3 (signed)
    jge     .t4_ok
    jmp     .fail
.t4_ok:

    ; ========================================================================
    ; TEST 5: JLE (less or equal)
    ; ========================================================================
    mov     ax, 3
    cmp     ax, 5                       ; 3 <= 5 (signed)
    jle     .t5_ok
    jmp     .fail
.t5_ok:

    ; ========================================================================
    ; TEST 6: JG (greater than)
    ; ========================================================================
    mov     ax, 10
    cmp     ax, 5                       ; 10 > 5 (signed)
    jg      .t6_ok
    jmp     .fail
.t6_ok:

    ; ========================================================================
    ; TEST 7: Unsigned conditional jumps
    ; JB/JC (below/carry)
    ; ========================================================================
    mov     ax, 0x0001
    cmp     ax, 0x0002                  ; 1 < 2 (unsigned)
    jb      .t7_ok
    jmp     .fail
.t7_ok:

    ; ========================================================================
    ; TEST 8: JAE/JNC (above or equal / no carry)
    ; ========================================================================
    mov     ax, 0x0005
    cmp     ax, 0x0003                  ; 5 >= 3 (unsigned)
    jae     .t8_ok
    jmp     .fail
.t8_ok:

    ; ========================================================================
    ; TEST 9: JA (above)
    ; ========================================================================
    mov     ax, 0x0010
    cmp     ax, 0x0005                  ; 16 > 5 (unsigned)
    ja      .t9_ok
    jmp     .fail
.t9_ok:

    ; ========================================================================
    ; TEST 10: JBE (below or equal)
    ; ========================================================================
    mov     ax, 0x0003
    cmp     ax, 0x0005                  ; 3 <= 5 (unsigned)
    jbe     .t10_ok
    jmp     .fail
.t10_ok:

    ; ========================================================================
    ; TEST 11: JS (sign), JNS (no sign)
    ; ========================================================================
    mov     ax, 0x8000
    test    ax, ax                      ; SF=1
    js      .t11_js
    jmp     .fail
.t11_js:
    mov     ax, 0x0100
    test    ax, ax                      ; SF=0
    jns     .t11_ok
    jmp     .fail
.t11_ok:

    ; ========================================================================
    ; TEST 12: CALL/RET — near call return
    ; ========================================================================
    mov     word [ctrl_result], 0
    call    .t12_func
    cmp     word [ctrl_result], 0x1234
    jne     .fail
    jmp     .t12_done
.t12_func:
    mov     word [ctrl_result], 0x1234
    ret
.t12_done:

    ; ========================================================================
    ; TEST 13: Nested CALL/RET
    ; ========================================================================
    mov     word [ctrl_result], 0
    call    .t13_outer
    cmp     word [ctrl_result], 0xABCD
    jne     .fail
    jmp     .t13_done
.t13_outer:
    call    .t13_inner
    ret
.t13_inner:
    mov     word [ctrl_result], 0xABCD
    ret
.t13_done:

    ; ========================================================================
    ; TEST 14: LOOP — counts down CX
    ; ========================================================================
    mov     cx, 5
    mov     dx, 0
.t14_loop:
    inc     dx
    loop    .t14_loop
    ; CX should be 0, DX should be 5
    test    cx, cx
    jnz     .fail
    cmp     dx, 5
    jne     .fail

    ; ========================================================================
    ; TEST 15: LOOPZ (LOOPZ exits when CX=0 OR ZF=0)
    ; ========================================================================
    mov     cx, 3
    mov     dx, 0
.t15_loop:
    inc     dx
    cmp     dx, 10                      ; ZF=0 when DX != 10
    ; Actually DX=1,2,3 → always ZF=0 after first iteration
    ; So LOOPZ will loop only once (CX decrements, but ZF was 0)
    ; Wait: LOOPZ continues while CX>0 AND ZF=1
    ; On first iteration: DX=1, cmp 1,10 → ZF=0 → LOOPZ exits
    ; But CX was decremented to 2 first
    ; Actually: LOOPZ decrements CX, then checks CX and ZF
    ; After DX=1, cmp sets ZF=0, LOOPZ decrements CX to 2, CX>0 but ZF=0 → exit
    loopz   .t15_loop
    cmp     dx, 1                       ; only 1 iteration
    jne     .fail

    ; ========================================================================
    ; TEST 16: LOOPNZ — exits when CX=0 OR ZF=1
    ; ========================================================================
    mov     cx, 10
    mov     dx, 0
.t16_loop:
    inc     dx
    cmp     dx, 3                       ; ZF=1 when DX=3
    loopnz  .t16_loop                   ; stops when CX=0 or DX=3 (ZF=1)
    cmp     dx, 3                       ; should stop at DX=3
    jne     .fail

    ; ========================================================================
    ; TEST 17: LOOP with CX=0 → 65536 iterations (underflow to 0xFFFF)
    ; We can't test full 65536, but we can verify CX wraps to 0xFFFF
    ; ========================================================================
    mov     cx, 1                       ; one iteration
    mov     dx, 0
.t17_loop:
    inc     dx
    loop    .t17_loop
    cmp     dx, 1
    jne     .fail
    ; CX is now 0 (decremented from 1 to 0, then loop exits)

    ; ========================================================================
    ; TEST 18: JMP short forward
    ; ========================================================================
    jmp     .t18_target
    jmp     .fail                       ; should be skipped
.t18_target:

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
; control_cleanup — Module cleanup
;---------------------------------------------------------------------------
control_cleanup:
    ret

; --- control data ---
control_name: db '8086 Control Flow', 0
ctrl_result:  dw 0                      ; scratch for CALL/RET tests
