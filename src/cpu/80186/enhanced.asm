;============================================================================
; MODULE: cpu/80186/enhanced.asm
; TIER:   UNIVERSAL
; VENUE:  G
; GEN:    80186+
; ORACLE: manual
; DESC:   ENTER/LEAVE procedure entry/exit instructions, additional
;         80186 behavioral differences from 8086.
;         ENTER: establishes stack frame for high-level language.
;           allocate local frame, optionally copy nesting levels.
;         LEAVE: deallocate frame (MOV SP,BP; POP BP).
; REFS:   Intel iAPX 186 Reference Manual — ENTER/LEAVE
;============================================================================

;---------------------------------------------------------------------------
; enh186_init — Module initialization
;---------------------------------------------------------------------------
enh186_init:
    ret

;---------------------------------------------------------------------------
; enh186_run — Execute 80186 enhanced instruction tests
; OUT: AL = STATUS_PASS or STATUS_FAIL
;---------------------------------------------------------------------------
enh186_run:
    push    bx
    push    cx
    push    dx
    push    si
    push    di

    ; ========================================================================
    ; Capability gate: 80186+ required
    ; ========================================================================
    mov     al, [g_cpu_type]
    cmp     al, CPU_80186
    jae     .cap_ok
    mov     al, STATUS_SKIP
    jmp     .done
.cap_ok:

    ; ========================================================================
    ; TEST 1: LEAVE — reverse of frame setup
    ; MOV BP, SP → SUB SP, 4 → ... → LEAVE should restore SP and BP
    ; ========================================================================
    mov     dx, sp                      ; save original SP
    mov     bx, bp                      ; save original BP
    push    bp                          ; save BP
    mov     bp, sp                      ; new frame pointer
    sub     sp, 4                       ; allocate 4 bytes of locals
    mov     word [bp - 2], 0xCAFE      ; store local
    mov     word [bp - 4], 0xBABE      ; store local
    leave                               ; LEAVE: SP = BP; POP BP
    ; After LEAVE: SP should be dx, BP should be bx
    cmp     sp, dx
    jne     .fail
    cmp     bp, bx
    jne     .fail

    ; ========================================================================
    ; TEST 2: ENTER level=0 — simple stack frame (no display)
    ; ENTER size, 0: push BP, set BP=SP, SUB SP, size
    ; ========================================================================
    mov     dx, sp                      ; save original SP
    mov     bx, bp                      ; save original BP
    enter   8, 0                        ; allocate 8 bytes, nesting level 0
    ; After ENTER: BP = old_SP - 2 (BP pushed), SP = BP - 8
    ; Check frame: SP should be DX - 2 - 8 = DX - 10
    mov     cx, dx
    sub     cx, 10                      ; 2 bytes for pushed BP + 8 bytes locals
    cmp     sp, cx
    jne     .fail
    ; BP should point to saved BP location
    mov     si, [bp]                    ; saved BP value should be our original BP
    cmp     si, bx
    jne     .fail
    leave                               ; clean up
    cmp     sp, dx                      ; SP restored
    jne     .fail
    cmp     bp, bx                      ; BP restored
    jne     .fail

    ; ========================================================================
    ; TEST 3: ENTER level=0, size=0 — minimal frame
    ; ========================================================================
    mov     dx, sp
    mov     bx, bp
    enter   0, 0
    ; SP should be DX - 2 (just pushed BP)
    mov     cx, dx
    sub     cx, 2
    cmp     sp, cx
    jne     .fail
    leave
    cmp     sp, dx
    jne     .fail
    cmp     bp, bx
    jne     .fail

    ; ========================================================================
    ; TEST 4: Multiple ENTER/LEAVE nesting (level=0 each time)
    ; ========================================================================
    mov     dx, sp
    enter   4, 0
    enter   4, 0                        ; nested frame
    enter   4, 0                        ; triple nested
    ; SP should be DX - 6 (3 pushes of BP) - 12 (3×4 locals)
    mov     cx, dx
    sub     cx, 18                      ; 6 + 12 = 18
    cmp     sp, cx
    jne     .fail
    leave
    leave
    leave
    cmp     sp, dx
    jne     .fail

    ; ========================================================================
    ; TEST 5: Shift with count=1 using immediate (80186+ allows imm8 count)
    ; On 8086 only CL or 1 allowed; 80186+ allows any imm8
    ; ========================================================================
    mov     ax, 0x0001
    shl     ax, 4                       ; immediate count (not CL)
    cmp     ax, 0x0010
    jne     .fail

    ; ========================================================================
    ; TEST 6: ROR with immediate count
    ; 0x0001 ROR 4 = 0x1000
    ; ========================================================================
    mov     ax, 0x0001
    ror     ax, 4
    cmp     ax, 0x1000
    jne     .fail

    ; ========================================================================
    ; TEST 7: SHR with immediate count
    ; 0xF000 SHR 4 = 0x0F00
    ; ========================================================================
    mov     ax, 0xF000
    shr     ax, 4
    cmp     ax, 0x0F00
    jne     .fail

    ; ========================================================================
    ; TEST 8: Local variable access via [BP-N] after ENTER
    ; ========================================================================
    mov     dx, sp
    enter   16, 0                       ; 16 bytes of locals
    mov     word [bp - 2], 0xDEAD
    mov     word [bp - 4], 0xBEEF
    mov     word [bp - 16], 0x1234
    ; Read back
    mov     ax, [bp - 2]
    cmp     ax, 0xDEAD
    jne     .fail
    mov     ax, [bp - 4]
    cmp     ax, 0xBEEF
    jne     .fail
    mov     ax, [bp - 16]
    cmp     ax, 0x1234
    jne     .fail
    leave
    cmp     sp, dx
    jne     .fail

    ; ========================================================================
    ; TEST 9: Rotate by immediate — ROL by 8 = byte swap
    ; 0x1234 ROL 8 = 0x3412
    ; ========================================================================
    mov     ax, 0x1234
    rol     ax, 8
    cmp     ax, 0x3412
    jne     .fail

    ; ========================================================================
    ; TEST 10: IMUL two-operand with immediate — negative result
    ; AX = -10 * 3 = -30
    ; ========================================================================
    mov     ax, -10
    imul    ax, 3
    cmp     ax, -30
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
; enh186_cleanup — Module cleanup
;---------------------------------------------------------------------------
enh186_cleanup:
    ret

; --- enh186 data ---
enh186_name: db '80186 ENTER/LEAVE/Enhanced', 0
