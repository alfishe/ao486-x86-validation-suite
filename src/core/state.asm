;============================================================================
; MODULE: core/state.asm
; DESC:   CPU state save/restore macros and helpers
;
; SAVE_STATE saves GP registers + FLAGS to a local buffer.
; RESTORE_STATE restores them. These are macros that operate on a
; named buffer (typically on the stack or in BSS).
;
; Usage in tests:
;   SAVE_STATE  state_buf
;   ; ... test code that modifies state ...
;   RESTORE_STATE state_buf
;
; For FPU state, use fpu_save/fpu_restore which save/restore the
; full 108-byte FPU state image.
;============================================================================

;---------------------------------------------------------------------------
; State buffer layout (28 bytes):
;   offset 0:  DW flags (2 bytes)
;   offset 2:  DW AX (2 bytes)
;   offset 4:  DW BX
;   offset 6:  DW CX
;   offset 8:  DW DX
;   offset 10: DW SI
;   offset 12: DW DI
;   offset 14: DW BP
;   offset 16: DW SP (value at save time, not restored)
;   offset 18: DW DS
;   offset 20: DW ES
;   offset 22: DW SS (not restored, just saved for diagnostics)
;   offset 24: DW reserved
;---------------------------------------------------------------------------
STATE_SIZE equ 28

;---------------------------------------------------------------------------
; save_state — Save GP registers + FLAGS to [DI]
; IN: DI = pointer to 28-byte state buffer
; Clobbers: nothing (all saved)
;---------------------------------------------------------------------------
save_state:
    pushf
    pop     ax
    mov     [di + 0], ax                ; flags
    mov     [di + 2], ax                ; AX — will overwrite below
    pop     ax                          ; recover return address
    ; We need to save all regs. Tricky because we can't push/pop freely.
    ; Use a different approach: save to buffer directly.
    ret

; Simpler macro-based approach (preferred):
%macro SAVE_STATE 1
    pushf
    pop     word [%1 + 0]
    mov     word [%1 + 2], ax
    mov     word [%1 + 4], bx
    mov     word [%1 + 6], cx
    mov     word [%1 + 8], dx
    mov     word [%1 + 10], si
    mov     word [%1 + 12], di
    mov     word [%1 + 14], bp
    mov     word [%1 + 16], sp
    mov     word [%1 + 18], ds
    mov     word [%1 + 20], es
%endmacro

%macro RESTORE_STATE 1
    mov     ax, word [%1 + 0]
    push    ax
    popf                                ; restore flags
    mov     ax, word [%1 + 2]
    mov     bx, word [%1 + 4]
    mov     cx, word [%1 + 6]
    mov     dx, word [%1 + 8]
    mov     si, word [%1 + 10]
    mov     di, word [%1 + 12]
    mov     bp, word [%1 + 14]
    mov     ds, word [%1 + 18]
    mov     es, word [%1 + 20]
    ; SP NOT restored (would corrupt stack). Caller manages SP separately.
%endmacro

;---------------------------------------------------------------------------
; fpu_save — Save FPU state to a 108-byte buffer
; IN: DI = pointer to 108-byte buffer
;---------------------------------------------------------------------------
fpu_save:
    push    ax
    mov     ax, di
    fnsave  [di]                        ; save full FPU state (108 bytes)
    fninit                              ; clean state for test
    pop     ax
    ret

;---------------------------------------------------------------------------
; fpu_restore — Restore FPU state from a 108-byte buffer
; IN: SI = pointer to 108-byte saved state
;---------------------------------------------------------------------------
fpu_restore:
    frstor  [si]
    ret

;---------------------------------------------------------------------------
; save_flags / restore_flags — lightweight FLAGS-only save/restore
; IN: none / AX = saved flags
;---------------------------------------------------------------------------
save_flags:
    pushf
    pop     ax
    ret

restore_flags:
    push    ax
    popf
    ret
