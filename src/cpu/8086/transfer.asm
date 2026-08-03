;============================================================================
; MODULE: cpu/8086/transfer.asm
; TIER:   UNIVERSAL
; VENUE:  G
; GEN:    8086+
; ORACLE: manual
; DESC:   Data transfer and comparison instructions — fills 8086 coverage gaps:
;         - MOV: all forms (reg-imm, reg-mem, mem-reg, sreg, moffs, AL/AX direct)
;         - CMP: standalone flag verification (equal, less, greater, signed/unsigned)
;         - XLAT/XLATB: table lookup translation
;         - SAHF/LAHF: store/load AH to/from flags
;         - JCXZ: jump if CX is zero
;         - CMC/CLC/STC/CLD/STD: explicit flag control verification
;         - LEA: complex addressing modes ([bx+si+disp], [bp+di+disp])
;         - LDS/LES: load far pointer from m16:16
;         - NOP: no-operation flag preservation
;         - Segment override prefixes (CS:, SS:)
;
; REFS:   Intel 8086 Family Users Manual §2.1 (MOV), §2.3 (CMP),
;         §2.4.4 (XLAT), §2.2.3 (flags), §2.4.5 (LEA),
;         §2.4.6 (LDS/LES), §3 (JCXZ)
;============================================================================

;---------------------------------------------------------------------------
xfer_init:
    ret

;---------------------------------------------------------------------------
; xfer_run
;---------------------------------------------------------------------------
xfer_run:
    push    bx
    push    cx
    push    dx
    push    si
    push    di
    push    bp

    ; ========================================================================
    ; TEST 1: MOV reg, imm16 — load immediate to register
    ; ========================================================================
    mov     ax, 0x1234
    cmp     ax, 0x1234
    jne     .fail

    mov     bx, 0xFFFF
    cmp     bx, 0xFFFF
    jne     .fail

    ; ========================================================================
    ; TEST 2: MOV reg, imm8 — byte immediate
    ; ========================================================================
    mov     al, 0xAB
    cmp     al, 0xAB
    jne     .fail

    mov     cl, 0x00
    cmp     cl, 0x00
    jne     .fail

    ; ========================================================================
    ; TEST 3: MOV mem, reg — store register to memory
    ; ========================================================================
    mov     ax, 0xBEEF
    mov     word [xfer_buf], ax
    mov     bx, [xfer_buf]
    cmp     bx, 0xBEEF
    jne     .fail

    ; ========================================================================
    ; TEST 4: MOV reg, mem — load memory to register
    ; ========================================================================
    mov     word [xfer_buf], 0xCAFE
    mov     cx, [xfer_buf]
    cmp     cx, 0xCAFE
    jne     .fail

    ; ========================================================================
    ; TEST 5: MOV mem, imm — store immediate to memory
    ; ========================================================================
    mov     word [xfer_buf], 0xDEAD
    mov     dx, [xfer_buf]
    cmp     dx, 0xDEAD
    jne     .fail

    mov     byte [xfer_buf], 0x42
    mov     al, [xfer_buf]
    cmp     al, 0x42
    jne     .fail

    ; ========================================================================
    ; TEST 6: MOV segment register — save/restore DS
    ; ========================================================================
    push    ds
    mov     ax, ds
    mov     word [xfer_buf], ax            ; save DS value
    mov     ax, 0x0000                     ; null selector (segment 0)
    mov     ds, ax                         ; DS = 0
    mov     es, ax                         ; ES = 0
    ; Read back: segment 0 with offset = our buffer address won't work
    ; because DS is now 0. Instead, restore from stack.
    pop     ds                             ; restore DS
    ; Verify DS restored
    mov     ax, [xfer_buf]                 ; should work with restored DS
    mov     bx, ds
    cmp     ax, bx                         ; [xfer_buf] should match DS value
    jne     .fail

    ; ========================================================================
    ; TEST 7: MOV AL, moffs8 — direct memory offset to AL
    ; ========================================================================
    mov     byte [xfer_byte_val], 0x99
    mov     al, [xfer_byte_val]            ; uses [DS:offset] effectively
    cmp     al, 0x99
    jne     .fail

    ; ========================================================================
    ; TEST 8: MOV AX, moffs16 — direct memory offset to AX
    ; ========================================================================
    mov     word [xfer_word_val], 0x7788
    mov     ax, [xfer_word_val]
    cmp     ax, 0x7788
    jne     .fail

    ; ========================================================================
    ; TEST 9: CMP equal — ZF=1, CF=0, OF=0
    ; ========================================================================
    mov     ax, 0x1234
    mov     bx, 0x1234
    cmp     ax, bx
    pushf
    pop     cx
    test    cx, FLAG_ZF                    ; ZF must be 1
    jz      .fail
    test    cx, FLAG_CF                    ; CF must be 0
    jnz     .fail
    test    cx, FLAG_OF                    ; OF must be 0
    jnz     .fail

    ; ========================================================================
    ; TEST 10: CMP less (unsigned) — CF=1
    ; 1 - 2 unsigned: borrow → CF=1
    ; ========================================================================
    mov     ax, 0x0001
    mov     bx, 0x0002
    cmp     ax, bx
    pushf
    pop     cx
    test    cx, FLAG_CF                    ; CF=1 (borrow)
    jz      .fail

    ; ========================================================================
    ; TEST 11: CMP greater (unsigned) — CF=0, ZF=0
    ; 5 - 3 unsigned: no borrow → CF=0
    ; ========================================================================
    mov     ax, 0x0005
    mov     bx, 0x0003
    cmp     ax, bx
    pushf
    pop     cx
    test    cx, FLAG_CF                    ; CF=0
    jnz     .fail
    test    cx, FLAG_ZF                    ; ZF=0
    jnz     .fail

    ; ========================================================================
    ; TEST 12: CMP signed less — SF != OF
    ; -1 (0xFFFF) vs +1: -1 < 1 signed → SF != OF
    ; ========================================================================
    mov     ax, 0xFFFF                     ; -1 signed
    mov     bx, 0x0001                     ; +1 signed
    cmp     ax, bx
    pushf
    pop     cx
    ; For signed less: SF XOR OF = 1
    mov     dx, cx
    and     dx, FLAG_SF
    jz      .sf0a
    ; SF=1 → OF must be 0 for "less" to be true
    test    cx, FLAG_OF
    jnz     .fail                          ; SF=1,OF=1 → not less
    jmp     .t12_ok
.sf0a:
    ; SF=0 → OF must be 1 for "less"
    test    cx, FLAG_OF
    jz      .fail                          ; SF=0,OF=0 → not less
.t12_ok:

    ; ========================================================================
    ; TEST 13: CMP does NOT modify operands
    ; ========================================================================
    mov     ax, 0xAAAA
    mov     bx, 0xBBBB
    cmp     ax, bx
    cmp     ax, 0xAAAA                     ; AX unchanged
    jne     .fail
    cmp     bx, 0xBBBB                     ; BX unchanged
    jne     .fail

    ; ========================================================================
    ; TEST 14: XLAT — table lookup translation
    ; XLAT: AL = [BX + AL]  (DS:BX+AL → AL)
    ; Set up a translation table: map 0→0xA0, 1→0xA1, 2→0xA2
    ; ========================================================================
    mov     bx, xfer_xlat_table
    mov     al, 0                          ; index 0
    xlat
    cmp     al, 0xA0
    jne     .fail

    mov     bx, xfer_xlat_table
    mov     al, 2                          ; index 2
    xlat
    cmp     al, 0xA2
    jne     .fail

    ; ========================================================================
    ; TEST 15: XLATB — same as XLAT (explicit operand form)
    ; ========================================================================
    mov     bx, xfer_xlat_table
    mov     al, 1
    xlatb
    cmp     al, 0xA1
    jne     .fail


    ; ========================================================================
    ; TEST 16: SAHF — store AH into flags (low byte)
    ; SAHF loads: SF, ZF, AF, PF, CF from AH
    ; Set AH to a known pattern, SAHF, then LAHF to read back
    ; ========================================================================
    ; We'll set CF=1 via AH bit 0 = 1
    mov     ah, 0x01                       ; bit 0 = CF = 1
    sahf
    pushf
    pop     cx
    test    cx, FLAG_CF                    ; CF must be 1
    jz      .fail

    ; Clear CF via SAHF
    mov     ah, 0x00
    sahf
    pushf
    pop     cx
    test    cx, FLAG_CF                    ; CF must be 0
    jnz     .fail

    ; ========================================================================
    ; TEST 17: LAHF — load flags into AH
    ; Set CF=1, then LAHF, AH bit 0 should be 1
    ; ========================================================================
    stc
    lahf
    mov     al, ah
    and     al, 0x01                       ; CF bit in AH
    jz      .fail                          ; must be 1

    clc
    lahf
    mov     al, ah
    and     al, 0x01
    jnz     .fail                          ; must be 0

    ; ========================================================================
    ; TEST 18: SAHF/LAHF round-trip
    ; SAHF sets SF,ZF,AF,PF,CF from AH. LAHF reads them back.
    ; Reserved bits 5,3,1 are not SAHF-controlled, so mask them out.
    ; 0xD5 mask = 11010101 preserves only SAHF-controlled bits.
    ; ========================================================================
    mov     ah, 0xC5                       ; SF=1, ZF=1, AF=0, PF=1, CF=1
    sahf
    lahf
    and     ah, 0xD5                       ; mask out reserved bits
    cmp     ah, 0xC5
    jne     .fail

    ; ========================================================================
    ; TEST 19: JCXZ — jump if CX is zero
    ; ========================================================================
    mov     cx, 0
    jcxz    .t19_ok
    jmp     .fail
.t19_ok:

    ; JCXZ does NOT jump when CX != 0
    mov     cx, 1
    jcxz    .t19_bail                      ; should NOT jump (CX=1)
    jmp     .t19_cont                      ; fall through — skip trampoline
.t19_bail:
    jmp     .fail                          ; trampoline: near jump
.t19_cont:

    ; ========================================================================
    ; TEST 20: CMC — complement carry flag
    ; CMC toggles CF. Verify using jc/jnc directly.
    ; ========================================================================
    clc                                  ; CF=0
    jnc     .t20a                         ; should not carry
    jmp     .fail
.t20a:
    cmc                                  ; CF -> 1
    jc      .t20b                         ; should carry now
    jmp     .fail
.t20b:
    cmc                                  ; CF -> 0
    jnc     .t20c                         ; should not carry
    jmp     .fail
.t20c:
    stc                                  ; CF=1
    cmc                                  ; CF -> 0
    jnc     .t20d                         ; should not carry
    jmp     .fail
.t20d:

    ; ========================================================================
    ; TEST 21: CLC/STC — clear/set carry
    ; ========================================================================
    stc
    pushf
    pop     cx
    test    cx, FLAG_CF
    jz      .fail

    clc
    pushf
    pop     cx
    test    cx, FLAG_CF
    jnz     .fail

    ; ========================================================================
    ; TEST 22: CLD/STD — clear/set direction flag
    ; STD sets DF=1, CLD clears DF=0
    ; ========================================================================
    std
    pushf
    pop     cx
    test    cx, FLAG_DF                    ; DF must be 1
    jz      .fail

    cld
    pushf
    pop     cx
    test    cx, FLAG_DF                    ; DF must be 0
    jnz     .fail


    ; ========================================================================
    ; TEST 23: JMP near indirect — jump through register
    ; ========================================================================
    mov     ax, .t23_target
    jmp     ax
    jmp     .fail                          ; should be skipped
.t23_target:


    ; ========================================================================
    ; TEST 24: MOV does not affect flags
    ; ========================================================================
    stc                                 ; CF=1
    mov     ax, 0xFFFF                     ; MOV must not change flags
    pushf
    pop     cx
    test    cx, FLAG_CF                    ; CF must still be 1
    jz      .fail

    ; ========================================================================
    ; TEST 25: LEA with complex addressing mode [bx+si+disp]
    ; All 8086 addressing modes must resolve correctly.
    ; ========================================================================
    lea     bx, [xfer_buf]
    mov     si, 2
    lea     ax, [bx + si + 4]              ; address = xfer_buf + 6
    mov     cx, xfer_buf + 6               ; expected
    cmp     ax, cx
    jne     .fail
    ; Also test [bp+di+disp] form (bp-relative addressing)
    lea     bp, [xfer_buf]
    mov     di, 0
    lea     ax, [bp + di + 1]              ; address = xfer_buf + 1
    mov     cx, xfer_buf + 1
    cmp     ax, cx
    jne     .fail

    ; ========================================================================
    ; TEST 26: LES — load ES:r16 from m16:16 far pointer
    ; ========================================================================
    push    es
    mov     word [xfer_far_ptr], 0x1234        ; offset
    mov     word [xfer_far_ptr + 2], 0x5678    ; segment
    les     di, [xfer_far_ptr]
    cmp     di, 0x1234                         ; offset into DI
    jne     .fail
    mov     ax, es
    cmp     ax, 0x5678                         ; segment into ES
    jne     .fail
    pop     es                                 ; restore ES

    ; ========================================================================
    ; TEST 27: LDS — load DS:r16 from m16:16 far pointer
    ; ========================================================================
    push    ds
    lds     si, [xfer_far_ptr]
    cmp     si, 0x1234                         ; offset into SI
    jne     .fail
    mov     ax, ds
    cmp     ax, 0x5678                         ; segment into DS
    jne     .fail
    pop     ds                                 ; restore DS

    ; ========================================================================
    ; TEST 28: NOP — no operation, must not affect flags
    ; ========================================================================
    stc
    nop
    jc      .t28a                             ; CF must still be 1
    jmp     .fail
.t28a:
    clc
    nop
    jnc     .t28b                             ; CF must still be 0
    jmp     .fail
.t28b:

    ; ========================================================================
    ; TEST 29: Segment override prefix — CS: to read data
    ; In .COM mode CS=DS, so CS: prefix must access same data.
    ; Tests that the assembler and CPU handle the prefix correctly.
    ; ========================================================================
    mov     byte [xfer_buf], 0x77
    mov     al, [cs:xfer_buf]
    cmp     al, 0x77
    jne     .fail
    ; Also test SS: override (same segment in .COM)
    mov     byte [xfer_buf], 0x88
    mov     al, [ss:xfer_buf]
    cmp     al, 0x88
    jne     .fail

    ; Ensure DF is clear on exit
    cld

    ; All tests passed
    mov     al, STATUS_PASS
    jmp     .done

.fail:
    cld
    mov     al, STATUS_FAIL

.done:
    pop     bp
    pop     di
    pop     si
    pop     dx
    pop     cx
    pop     bx
    ret

;---------------------------------------------------------------------------
xfer_cleanup:
    ret

; --- xfer data ---
xfer_name: db '8086 Data Transfer/CMP', 0

xfer_buf:       dw 0
xfer_byte_val:  db 0
xfer_word_val:  dw 0
xfer_far_ptr:   dw 0, 0

; XLAT translation table: index → value
xfer_xlat_table: db 0xA0, 0xA1, 0xA2, 0xA3, 0xA4, 0xA5, 0xA6, 0xA7
                 db 0xA8, 0xA9, 0xAA, 0xAB, 0xAC, 0xAD, 0xAE, 0xAF
