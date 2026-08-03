;============================================================================
; MODULE: cpu/8086/smoke.asm
; TIER:   UNIVERSAL
; VENUE:  G
; GEN:    8086+
; ORACLE: manual
; DESC:   Basic smoke test — validates framework pipeline with simple
;         arithmetic, logic, and flag checks. Not a deep corner-case test;
;         its purpose is to prove the init/run/cleanup/report pipeline works.
; REFS:   Intel 8086 Family Users Manual §2.2-2.4 (ADD/SUB/AND/OR flags)
;============================================================================

;---------------------------------------------------------------------------
; smoke_init — Module initialization (no-op for now)
;---------------------------------------------------------------------------
smoke_init:
    ret

;---------------------------------------------------------------------------
; smoke_run — Execute smoke test cases
; OUT: AL = STATUS_PASS or STATUS_FAIL
;---------------------------------------------------------------------------
smoke_run:
    push    bx
    push    cx
    push    dx

    ; ====================================================================
    ; PATTERN: do operation, capture flags IMMEDIATELY via pushf, then
    ; check result value (which clobbers flags), then test saved flags.
    ; Never put cmp between an operation and pushf — cmp modifies flags!
    ; ====================================================================

    ; --- Sub-test 1: ADD result and flags ---
    mov     ax, 0x1234
    mov     bx, 0x1111
    add     ax, bx                     ; AX = 0x2345, CF=0, ZF=0, SF=0, OF=0
    pushf                              ; capture flags from ADD
    pop     cx                         ; CX = flags
    cmp     ax, 0x2345
    jne     .fail
    test    cx, FLAG_CF                ; CF must be 0
    jnz     .fail
    test    cx, FLAG_ZF                ; ZF must be 0
    jnz     .fail

    ; --- Sub-test 2: SUB with borrow (CF=1) ---
    mov     ax, 0x0001
    mov     bx, 0x0002
    sub     ax, bx                     ; AX = 0xFFFF, CF=1, SF=1
    pushf                              ; capture flags from SUB
    pop     cx
    cmp     ax, 0xFFFF
    jne     .fail
    test    cx, FLAG_CF                ; CF must be 1
    jz      .fail

    ; --- Sub-test 3: AND clears CF and OF ---
    mov     ax, 0xFF00
    mov     bx, 0x0FF0
    and     ax, bx                     ; AX = 0x0F00, CF=0, OF=0
    pushf                              ; capture flags from AND
    pop     cx
    cmp     ax, 0x0F00
    jne     .fail
    mov     dx, FLAG_CF | FLAG_OF
    test    cx, dx                     ; both CF and OF must be 0
    jnz     .fail

    ; --- Sub-test 4: OR sets flags correctly ---
    mov     ax, 0xF0F0
    mov     bx, 0x0F0F
    or      ax, bx                     ; AX = 0xFFFF, SF=1, ZF=0, PF=1
    pushf                              ; capture flags from OR
    pop     cx
    cmp     ax, 0xFFFF
    jne     .fail
    test    cx, FLAG_SF                ; SF must be 1
    jz      .fail

    ; --- Sub-test 5: INC preserves CF ---
    stc                                ; set CF=1
    mov     ax, 0xFFFE
    inc     ax                         ; AX = 0xFFFF, CF UNCHANGED (=1)
    pushf                              ; capture flags from INC
    pop     cx
    cmp     ax, 0xFFFF
    jne     .fail
    test    cx, FLAG_CF                ; CF must still be 1
    jz      .fail

    ; --- Sub-test 6: Memory write/read round-trip ---
    mov     word [smoke_buf], 0xBEEF
    mov     ax, [smoke_buf]
    cmp     ax, 0xBEEF
    jne     .fail

    ; --- Sub-test 7: PUSH/POP round-trip ---
    mov     ax, 0xCAFE
    push    ax
    pop     dx
    cmp     dx, 0xCAFE
    jne     .fail

    ; --- Sub-test 8: XOR self-zeroes ---
    mov     ax, 0xDEAD
    xor     ax, ax                     ; AX = 0, ZF=1
    pushf                              ; capture flags from XOR
    pop     cx
    test    ax, ax                     ; verify AX=0
    jnz     .fail
    test    cx, FLAG_ZF                ; ZF must be 1
    jz      .fail

    ; All sub-tests passed
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
; smoke_cleanup — Module cleanup (no-op)
;---------------------------------------------------------------------------
smoke_cleanup:
    ret

; --- smoke data ---
smoke_name: db '8086 Smoke Test', 0
smoke_buf:  dw 0                       ; scratch buffer for memory test
