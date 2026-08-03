;============================================================================
; MODULE: cpu/80186/new_insns.asm
; TIER:   UNIVERSAL
; VENUE:  G
; GEN:    80186+
; ORACLE: manual
; DESC:   Instructions new to the 80186 not present on 8086:
;         PUSHA/POPA — push/pop all GP registers (8 regs, 16 bytes)
;         PUSH imm   — push immediate (sign-extended byte or word)
;         IMUL imm   — multiply with immediate operand
;         BOUND      — check array bounds (raises #BR if out of range)
;         INS/OUTS   — string I/O (INSB/INSW/OUTSB/OUTSW)
;         The 80186 also changed shift count masking (5-bit, mod 32).
; REFS:   Intel iAPX 186 Reference Manual §2 (instruction set);
;         8086 to 80186 differences: shift count masked to 5 bits.
;============================================================================

;---------------------------------------------------------------------------
; insns186_init — Module initialization
;---------------------------------------------------------------------------
insns186_init:
    ret

;---------------------------------------------------------------------------
; insns186_run — Execute 80186 new instruction tests
; OUT: AL = STATUS_PASS or STATUS_FAIL
;---------------------------------------------------------------------------
insns186_run:
    push    bx
    push    cx
    push    dx
    push    si
    push    di
    push    bp

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
    ; TEST 1: PUSHA/POPA — save and restore all 8 GP registers
    ; PUSHA pushes: AX, CX, DX, BX, original SP, BP, SI, DI (in that order)
    ; POPA restores all except SP (SP is discarded)
    ; ========================================================================
    mov     ax, 0x1111
    mov     cx, 0x2222
    mov     dx, 0x3333
    mov     bx, 0x4444
    mov     bp, 0x5555
    mov     si, 0x6666
    mov     di, 0x7777
    pusha                               ; save all
    ; Now clobber everything
    mov     ax, 0xDEAD
    mov     cx, 0xDEAD
    mov     dx, 0xDEAD
    mov     bx, 0xDEAD
    mov     bp, 0xDEAD
    mov     si, 0xDEAD
    mov     di, 0xDEAD
    popa                                ; restore all
    ; Verify
    cmp     ax, 0x1111
    jne     .fail
    cmp     cx, 0x2222
    jne     .fail
    cmp     dx, 0x3333
    jne     .fail
    cmp     bx, 0x4444
    jne     .fail
    cmp     bp, 0x5555
    jne     .fail
    cmp     si, 0x6666
    jne     .fail
    cmp     di, 0x7777
    jne     .fail

    ; ========================================================================
    ; TEST 2: PUSHA/POPA — SP is NOT restored by POPA
    ; PUSHA pushes original SP value, but POPA discards it (restores SP to
    ; value after the 8 pops, i.e. SP before PUSHA).
    ; ========================================================================
    mov     bx, sp                      ; save SP before PUSHA
    pusha
    ; SP is now SP-16
    popa
    cmp     sp, bx                      ; SP should be fully restored
    jne     .fail

    ; ========================================================================
    ; TEST 3: PUSH imm8 — sign-extended to 16 bits
    ; PUSH 0x42 → pop AX = 0x0042
    ; ========================================================================
    push    byte 0x42
    pop     ax
    cmp     ax, 0x0042
    jne     .fail

    ; ========================================================================
    ; TEST 4: PUSH imm8 negative — sign extension
    ; PUSH -1 (0xFF byte) → sign-extended to 0xFFFF
    ; ========================================================================
    push    byte -1
    pop     ax
    cmp     ax, 0xFFFF
    jne     .fail

    ; ========================================================================
    ; TEST 5: PUSH word imm — full 16-bit immediate
    ; ========================================================================
    push    word 0xBEEF
    pop     ax
    cmp     ax, 0xBEEF
    jne     .fail

    ; ========================================================================
    ; TEST 6: IMUL r16, r/m16, imm8 — three-operand multiply
    ; AX = BL * 10 (where BL=5) = 50
    ; ========================================================================
    xor     bx, bx
    mov     bl, 5
    imul    cx, bx, 10                  ; CX = 5 * 10 = 50
    cmp     cx, 50
    jne     .fail

    ; ========================================================================
    ; TEST 7: IMUL r16, r/m16, imm16 — three-operand, word immediate
    ; CX = BX * 0x0100 (where BX=0x0010) = 0x1000
    ; ========================================================================
    mov     bx, 0x0010
    imul    cx, bx, 0x0100              ; CX = 16 * 256 = 4096
    cmp     cx, 0x1000
    jne     .fail

    ; ========================================================================
    ; TEST 8: IMUL r16, r/m16 — two-operand multiply
    ; DX = AX * BX
    ; ========================================================================
    mov     ax, 3
    mov     bx, 7
    imul    bx                          ; AX = AX * BX = 21
    ; NOTE: two-operand IMUL puts result in AX (implicit dest)
    cmp     ax, 21
    jne     .fail

    ; ========================================================================
    ; TEST 9: IMUL r16, imm8 — register * immediate
    ; ========================================================================
    mov     ax, 100
    imul    ax, 3                       ; AX = 100 * 3 = 300
    cmp     ax, 300
    jne     .fail

    ; ========================================================================
    ; TEST 10: IMUL negative result — CF/OF set if truncation occurs
    ; -5 * 3 = -15, fits in 16 bits → CF=OF=0
    ; ========================================================================
    mov     ax, -5
    imul    ax, 3                       ; AX = -15 = 0xFFF1
    pushf
    pop     cx
    cmp     ax, 0xFFF1
    jne     .fail
    test    cx, FLAG_CF                 ; CF=0 (result fits)
    jnz     .fail

    ; ========================================================================
    ; TEST 11: IMUL overflow — large product truncated, CF=OF=1
    ; 0x1000 * 0x1000 = 0x01000000, truncated to 0x0000 → CF=OF=1
    ; ========================================================================
    mov     ax, 0x1000
    mov     bx, 0x1000
    imul    bx                          ; AX:DX = result, but dest is AX
    ; AX = 0x0000 (low 16 bits), CF=1 (overflow)
    pushf
    pop     cx
    cmp     ax, 0x0000                  ; 0x1000*0x1000 low word = 0x0000
    jne     .fail
    test    cx, FLAG_CF                 ; CF=1 (overflow — result doesn't fit)
    jz      .fail

    ; ========================================================================
    ; TEST 12: Shift count masking — 80186+ masks to 5 bits (mod 32)
    ; On 80186: SHL ax, 33 → same as SHL ax, 1 (33 mod 32 = 1)
    ; ========================================================================
    mov     ax, 0x0001
    mov     cl, 33                      ; 33 mod 32 = 1
    shl     ax, cl                      ; should be same as SHL ax, 1
    cmp     ax, 0x0002
    jne     .fail

    ; ========================================================================
    ; TEST 13: Shift count masking — large count becomes 0
    ; 64 mod 32 = 0 → no-op, flags unchanged
    ; ========================================================================
    stc                                 ; CF=1
    mov     ax, 0x1234
    mov     cl, 64                      ; 64 mod 32 = 0 → no-op
    shl     ax, cl
    pushf
    pop     cx
    cmp     ax, 0x1234                  ; unchanged
    jne     .fail
    test    cx, FLAG_CF                 ; CF still 1
    jz      .fail

    ; ========================================================================
    ; TEST 14: Shift count = 31 (max effective on 80186+)
    ; 0x8000 SAR 31 → 0xFFFF (all sign bits)
    ; ========================================================================
    mov     ax, 0x8000
    mov     cl, 31
    sar     ax, cl                      ; arithmetic right shift 31 → all 1s
    cmp     ax, 0xFFFF
    jne     .fail

    ; ========================================================================
    ; TEST 15: BOUND — in-range value (no exception)
    ; BOUND r16, m16&16: if reg < [mem] or reg > [mem+2], raise #BR (INT 5)
    ; Bounds: [10, 20]. Value 15 is in range → no exception.
    ; ========================================================================
    ; --- Install temporary INT 5 handler ---
    push    es
    xor     ax, ax
    mov     es, ax                      ; ES → IVT (segment 0)
    mov     ax, [es:0x14]               ; save original INT 5 offset
    mov     [bound_save_off], ax
    mov     ax, [es:0x16]               ; save original INT 5 segment
    mov     [bound_save_seg], ax
    mov     ax, bound_int5_handler
    mov     [es:0x14], ax
    mov     ax, cs
    mov     [es:0x16], ax
    pop     es

    ; Set up bounds [10, 20] in memory
    mov     word [bound_lo], 10
    mov     word [bound_hi], 20
    mov     byte [bound_caught], 0       ; clear flag

    ; BOUND with in-range value: AX=15, bounds [10, 20]
    mov     ax, 15
    bound   ax, [bound_lo]              ; 15 is in [10,20] → no exception
    cmp     byte [bound_caught], 0      ; flag must still be 0
    jne     .fail

    ; ========================================================================
    ; TEST 16: BOUND — out-of-range value (INT 5 raised)
    ; AX=5, bounds [10, 20]: 5 < 10 → #BR
    ; Handler will set flag and skip past BOUND instruction
    ; ========================================================================
    mov     byte [bound_caught], 0
    mov     ax, 5
    bound   ax, [bound_lo]              ; 5 < 10 → #BR → handler fires
    ; Handler advanced IP past BOUND. Verify flag was set.
    cmp     byte [bound_caught], 1
    jne     .fail

    ; ========================================================================
    ; TEST 17: BOUND — out-of-range high value
    ; AX=25, bounds [10, 20]: 25 > 20 → #BR
    ; ========================================================================
    mov     byte [bound_caught], 0
    mov     ax, 25
    bound   ax, [bound_lo]              ; 25 > 20 → #BR
    cmp     byte [bound_caught], 1
    jne     .fail

    ; --- Restore original INT 5 handler ---
    push    es
    xor     ax, ax
    mov     es, ax
    mov     ax, [bound_save_off]
    mov     [es:0x14], ax
    mov     ax, [bound_save_seg]
    mov     [es:0x16], ax
    pop     es

    ; All tests passed
    mov     al, STATUS_PASS
    jmp     .done

.fail:
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
; insns186_cleanup — Module cleanup
;---------------------------------------------------------------------------
insns186_cleanup:
    ret

; --- INT 5 (#BR) handler for BOUND tests ---
; Stack on entry: [SP]=IP, [SP+2]=CS, [SP+4]=FLAGS
; BOUND instruction encoding with [disp16] is 4 bytes (62 06 lo hi)
; We add 4 to return IP to skip past the faulting BOUND instruction.
bound_int5_handler:
    push    bp
    push    ax
    mov     bp, sp
    ; Stack now: AX, BP, IP, CS, FLAGS
    ; IP is at [BP+4]
    add     word [bp + 4], 4            ; skip 4-byte BOUND instruction
    mov     byte [cs:bound_caught], 1   ; mark exception was caught
    pop     ax
    pop     bp
    iret

; --- insns186 data ---
insns186_name: db '80186 New Instructions', 0

bound_lo:       dw 0
bound_hi:       dw 0
bound_caught:   db 0
bound_save_off: dw 0
bound_save_seg: dw 0
