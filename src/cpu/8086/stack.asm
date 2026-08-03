;============================================================================
; MODULE: cpu/8086/stack.asm
; TIER:   UNIVERSAL
; VENUE:  G
; GEN:    8086+
; ORACLE: manual
; DESC:   PUSH/POP/XCHG/LEA — stack operations and data exchange.
;         Tests SP decrement/increment, word alignment, register save/restore.
;         XCHG with memory implies LOCK on 8086 (implicit).
; REFS:   Intel 8086 Family Users Manual §2.1 (PUSH/POP), §2.9 (XCHG)
;============================================================================

;---------------------------------------------------------------------------
; stack_init — Module initialization
;---------------------------------------------------------------------------
stack_init:
    ret

;---------------------------------------------------------------------------
; stack_run — Execute stack/XCHG test cases
; OUT: AL = STATUS_PASS or STATUS_FAIL
;---------------------------------------------------------------------------
stack_run:
    push    bx
    push    cx
    push    dx
    push    si
    push    di

    ; ========================================================================
    ; TEST 1: PUSH/POP word round-trip
    ; ========================================================================
    mov     ax, 0xDEAD
    push    ax
    pop     dx
    cmp     dx, 0xDEAD
    jne     .fail

    ; ========================================================================
    ; TEST 2: PUSH decrement SP by 2, POP restores
    ; ========================================================================
    mov     bx, sp                      ; save SP
    mov     ax, 0xBEEF
    push    ax
    mov     cx, sp
    add     cx, 2
    cmp     cx, bx                      ; SP should have been BX-2, now BX-2+2=BX
    jne     .fail
    pop     ax                          ; restore AX and SP
    cmp     ax, 0xBEEF
    jne     .fail
    cmp     sp, bx                      ; SP fully restored
    jne     .fail

    ; ========================================================================
    ; TEST 3: Multiple PUSH/POP — LIFO order
    ; push 1, 2, 3 → pop should get 3, 2, 1
    ; ========================================================================
    push    word 0x1111
    push    word 0x2222
    push    word 0x3333
    pop     ax
    cmp     ax, 0x3333
    jne     .fail
    pop     ax
    cmp     ax, 0x2222
    jne     .fail
    pop     ax
    cmp     ax, 0x1111
    jne     .fail

    ; ========================================================================
    ; TEST 4: PUSH register / POP different register
    ; ========================================================================
    mov     cx, 0xCAFE
    push    cx
    pop     si                          ; SI should now = 0xCAFE
    cmp     si, 0xCAFE
    jne     .fail

    ; ========================================================================
; TEST 5: PUSHF/POPF — save and restore flags
    ; ========================================================================
    mov     ax, 0x0000
    push    ax
    popf                                ; clear all flags
    pushf
    pop     cx
    ; IF should be whatever DOS had; just verify pushf/popf round-trips
    push    cx
    popf
    pushf
    pop     dx
    cmp     cx, dx                      ; flags should be same both times
    jne     .fail

    ; ========================================================================
    ; TEST 6: XCHG reg, reg
    ; ========================================================================
    mov     ax, 0x1111
    mov     bx, 0x2222
    xchg    ax, bx
    cmp     ax, 0x2222
    jne     .fail
    cmp     bx, 0x1111
    jne     .fail

    ; ========================================================================
    ; TEST 7: XCHG with memory
    ; ========================================================================
    mov     word [stack_buf], 0xAAAA
    mov     ax, 0xBBBB
    xchg    ax, [stack_buf]
    cmp     ax, 0xAAAA                  ; AX got old memory value
    jne     .fail
    cmp     word [stack_buf], 0xBBBB    ; memory got AX
    jne     .fail

    ; ========================================================================
    ; TEST 8: XCHG AX, AX is effectively NOP but does swap (no LOCK)
    ; ========================================================================
    mov     ax, 0x4242
    xchg    ax, ax
    cmp     ax, 0x4242
    jne     .fail

    ; ========================================================================
    ; TEST 9: PUSH segment register / POP
    ; ========================================================================
    push    es
    pop     cx                          ; CX should = ES
    mov     dx, es
    cmp     cx, dx
    jne     .fail

    ; ========================================================================
    ; TEST 10: LEA — load effective address
    ; ========================================================================
    lea     bx, [stack_buf]
    mov     ax, stack_buf               ; NASM resolves label address
    cmp     bx, ax                      ; LEA should give same address
    jne     .fail

    ; ========================================================================
    ; TEST 11: PUSH imm8 (80186+) — sign-extended to word
    ; NOTE: On a real 8086, PUSH imm is not available. NASM will still encode
    ; it, but it requires 80186+. We gate this test on CPU >= 80186.
    ; ========================================================================
    mov     al, [g_cpu_type]
    cmp     al, CPU_80186
    jb      .skip_push_imm              ; 8086 doesn't have PUSH imm8
    push    word 0x0042
    pop     ax
    cmp     ax, 0x0042
    jne     .fail
    push    word -1                     ; sign extension
    pop     ax
    cmp     ax, 0xFFFF
    jne     .fail
.skip_push_imm:

    ; ========================================================================
    ; TEST 12: Stack pointer fully balanced — SP unchanged after all push/pop
    ; ========================================================================
    mov     bx, sp
    push    ax
    push    cx
    push    dx
    pop     dx
    pop     cx
    pop     ax
    cmp     sp, bx
    jne     .fail

    ; All tests passed
    mov     al, STATUS_PASS
    jmp     .done

.fail:
    mov     al, STATUS_FAIL

.done:
    pop     di
    pop     si
    pop     dx
    pop     cx
    pop     bx
    ret

;---------------------------------------------------------------------------
; stack_cleanup — Module cleanup
;---------------------------------------------------------------------------
stack_cleanup:
    ret

; --- stack data ---
stack_name: db '8086 Stack/XCHG', 0
stack_buf:  dw 0
