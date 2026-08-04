;============================================================================
; MODULE: cpu/80386/bitops.asm
; TIER:   UNIVERSAL
; VENUE:  G
; GEN:    80386+
; ORACLE: manual
; DESC:   80386 bit manipulation instructions:
;         - BT:   bit test (copy bit to CF, no modification)
;         - BTC:  bit test and complement (toggle bit)
;         - BTR:  bit test and reset (clear bit)
;         - BTS:  bit test and set (set bit)
;         - BSF:  bit scan forward (find lowest set bit)
;         - BSR:  bit scan reverse (find highest set bit)
;
; REFS:   Intel 80386 PRM Ch. 17 (BT/BTS/BTR/BTC, BSF/BSR)
;============================================================================

;---------------------------------------------------------------------------
i386bit_init:
    ret

;---------------------------------------------------------------------------
; i386bit_run
;---------------------------------------------------------------------------
i386bit_run:
    push    ebx
    push    ecx
    push    edx
    push    esi
    push    edi
    push    ebp

    ; ========================================================================
    ; Capability gate: 80386+ required
    ; ========================================================================
    mov     al, [g_cpu_type]
    cmp     al, CPU_80386
    jae     .cap_ok
    mov     al, STATUS_SKIP
    jmp     .done
.cap_ok:

    ; ========================================================================
    ; TEST 1: BT r16, imm8 — bit test, bit goes to CF
    ; AX=0x0001, BT AX, 0 -> CF=1
    ; ========================================================================
    mov     ax, 0x0001
    bt      ax, 0
    jnc     .fail

    mov     ax, 0x0001
    bt      ax, 1                       ; bit 1 is 0
    jc      .fail

    ; ========================================================================
    ; TEST 2: BT r16, imm8 — higher bit
    ; AX=0x8000, BT AX, 15 -> CF=1
    ; ========================================================================
    mov     ax, 0x8000
    bt      ax, 15
    jnc     .fail

    mov     ax, 0x4000
    bt      ax, 15                      ; bit 15 is 0
    jc      .fail

    ; ========================================================================
    ; TEST 3: BT r32, imm8 — 32-bit register
    ; EAX=0x80000000, BT EAX, 31 -> CF=1
    ; ========================================================================
    mov     eax, 0x80000000
    bt      eax, 31
    jnc     .fail

    mov     eax, 0x40000000
    bt      eax, 31                     ; bit 31 is 0
    jc      .fail

    ; ========================================================================
    ; TEST 4: BT r16, r16 — bit index in register
    ; AX=0x0080, BT AX, CL where CL=7 -> CF=1
    ; ========================================================================
    mov     ax, 0x0080
    mov     cl, 7
    bt      ax, cx                      ; NOTE: 16-bit operand uses CL only
    jnc     .fail

    ; ========================================================================
    ; TEST 5: BT m16, imm8 — memory operand
    ; ========================================================================
    mov     word [i386bit_buf], 0x0100
    bt      word [i386bit_buf], 8
    jnc     .fail

    ; ========================================================================
    ; TEST 6: BTS r16, imm8 — set bit and test
    ; ========================================================================
    mov     ax, 0x0000
    mov     bx, 0x0000
    ; Set bit 5
    bts     ax, 5
    ; AX should now be 0x0020 and CF should be 0 (bit was clear)
    jc      .fail
    cmp     ax, 0x0020
    jne     .fail

    ; Setting an already-set bit: CF=1
    bts     ax, 5
    jnc     .fail
    cmp     ax, 0x0020                  ; unchanged
    jne     .fail

    ; ========================================================================
    ; TEST 7: BTS r32, imm8 — 32-bit
    ; ========================================================================
    mov     eax, 0x00000000
    bts     eax, 20
    jc      .fail                       ; bit was 0
    cmp     eax, 0x00100000
    jne     .fail

    bts     eax, 20
    jnc     .fail                       ; bit was 1
    cmp     eax, 0x00100000             ; unchanged
    jne     .fail

    ; ========================================================================
    ; TEST 8: BTR r16, imm8 — reset bit and test
    ; ========================================================================
    mov     ax, 0x00FF
    btr     ax, 3                       ; reset bit 3
    jc      .fail2                      ; bit was 1 → CF should be 1!
    jmp     .fail                      ; if we get here CF was wrong
.fail2:
    cmp     ax, 0x00F7                  ; bit 3 cleared
    jne     .fail

    ; Reset already-cleared bit: CF=0
    btr     ax, 3
    jc      .fail
    cmp     ax, 0x00F7                  ; unchanged
    jne     .fail

    ; ========================================================================
    ; TEST 9: BTR r32, imm8 — 32-bit
    ; ========================================================================
    mov     eax, 0xFFFFFFFF
    btr     eax, 31
    jc      .t9_ok                      ; bit was 1 → CF must be 1
    jmp     .fail
.t9_ok:
    cmp     eax, 0x7FFFFFFF             ; bit 31 cleared
    jne     .fail

    ; ========================================================================
    ; TEST 10: BTC r16, imm8 — toggle bit and test
    ; ========================================================================
    mov     ax, 0x0000
    btc     ax, 4                       ; toggle bit 4: 0→1
    jc      .fail                       ; original bit was 0 → CF=0
    cmp     ax, 0x0010
    jne     .fail

    btc     ax, 4                       ; toggle bit 4: 1→0
    jc      .t10b_ok                    ; original bit was 1 → CF=1
    jmp     .fail
.t10b_ok:
    cmp     ax, 0x0000
    jne     .fail

    ; ========================================================================
    ; TEST 11: BTC r32, r32 — toggle with register index
    ; ========================================================================
    mov     eax, 0x00000000
    mov     ecx, 16
    btc     eax, ecx                    ; toggle bit 16: 0→1
    jc      .fail
    cmp     eax, 0x00010000
    jne     .fail

    ; ========================================================================
    ; TEST 12: BTS/BTR/BTC with memory operand
    ; ========================================================================
    mov     dword [i386bit_buf], 0x00000000
    bts     dword [i386bit_buf], 10
    jc      .fail                       ; bit was 0
    cmp     dword [i386bit_buf], 0x00000400
    jne     .fail

    btr     dword [i386bit_buf], 10
    jc      .t12_ok                     ; bit was 1 → CF=1
    jmp     .fail
.t12_ok:
    cmp     dword [i386bit_buf], 0x00000000
    jne     .fail

    btc    dword [i386bit_buf], 8       ; toggle: 0→1
    jc      .fail
    cmp     dword [i386bit_buf], 0x00000100
    jne     .fail

    ; ========================================================================
    ; TEST 13: BSF r16, r/m16 — bit scan forward (find LSB)
    ; BSF scans from bit 0 upward. If source=0, ZF=1 and dest undefined.
    ; ========================================================================
    mov     ax, 0x0010                  ; bit 4 is lowest set bit
    bsf     bx, ax
    jz      .fail                       ; ZF must be 0 (found a bit)
    cmp     bx, 4
    jne     .fail

    mov     ax, 0x8000                  ; only bit 15 set
    bsf     bx, ax
    jz      .fail
    cmp     bx, 15
    jne     .fail

    ; ========================================================================
    ; TEST 14: BSF r32, r/m32 — 32-bit bit scan forward
    ; ========================================================================
    mov     eax, 0x00010000             ; bit 16
    bsf     ebx, eax
    jz      .fail
    cmp     ebx, 16
    jne     .fail

    mov     eax, 0x80000000             ; bit 31
    bsf     ebx, eax
    jz      .fail
    cmp     ebx, 31
    jne     .fail

    ; ========================================================================
    ; TEST 15: BSF on zero — ZF=1 (undefined destination)
    ; ========================================================================
    mov     eax, 0
    bsf     ebx, eax
    jnz     .fail                       ; ZF must be 1 (no bit found)

    ; ========================================================================
    ; TEST 16: BSR r16, r/m16 — bit scan reverse (find MSB)
    ; BSR scans from high bit downward.
    ; ========================================================================
    mov     ax, 0x0010                  ; bit 4 is highest set bit
    bsr     bx, ax
    jz      .fail
    cmp     bx, 4
    jne     .fail

    mov     ax, 0x8001                  ; bits 0 and 15 set
    bsr     bx, ax
    jz      .fail
    cmp     bx, 15                      ; highest set bit
    jne     .fail

    ; ========================================================================
    ; TEST 17: BSR r32, r/m32 — 32-bit bit scan reverse
    ; ========================================================================
    mov     eax, 0x00010000             ; bit 16
    bsr     ebx, eax
    jz      .fail
    cmp     ebx, 16
    jne     .fail

    mov     eax, 0x00800040             ; bits 6 and 23 set
    bsr     ebx, eax
    jz      .fail
    cmp     ebx, 23                     ; highest set bit
    jne     .fail

    ; ========================================================================
    ; TEST 18: BSR on zero — ZF=1
    ; ========================================================================
    mov     eax, 0
    bsr     ebx, eax
    jnz     .fail                       ; ZF must be 1

    ; ========================================================================
    ; TEST 19: BSF from memory
    ; ========================================================================
    mov     dword [i386bit_buf], 0x00000080   ; bit 7
    bsf     eax, dword [i386bit_buf]
    jz      .fail
    cmp     eax, 7
    jne     .fail

    ; ========================================================================
    ; TEST 20: BSR from memory
    ; ========================================================================
    mov     dword [i386bit_buf], 0x40000000   ; bit 30
    bsr     eax, dword [i386bit_buf]
    jz      .fail
    cmp     eax, 30
    jne     .fail

    ; ========================================================================
    ; TEST 21: BT m32, r32 — bit test with register index on memory
    ; NOTE: large bit offset address crossing (bit ≥ 32 on memory) is a
    ; documented 386 feature but not implemented correctly in DOSBox-X
    ; core=normal. We test register-index BT on memory within a single
    ; dword instead. TODO: add cross-dword BT test on 86Box/real HW.
    ; Ref: Intel 80386 PRM Ch. 17 (BT r/m32, r32)
    ; ========================================================================
    mov     dword [i386bit_buf], 0x00400000   ; bit 22 set
    mov     ecx, 22
    bt      dword [i386bit_buf], ecx
    jnc     .fail                              ; CF must be 1

    mov     dword [i386bit_buf], 0x00000000   ; all clear
    mov     ecx, 15
    bt      dword [i386bit_buf], ecx
    jc      .fail                              ; CF must be 0

    ; ========================================================================
    ; TEST 22: BTS m32, r32 — set bit with register index on memory
    ; ========================================================================
    mov     dword [i386bit_buf], 0x00000000
    mov     ecx, 18
    bts     dword [i386bit_buf], ecx
    jc      .fail                                ; was 0 → CF=0
    cmp     dword [i386bit_buf], 0x00040000       ; bit 18 set
    jne     .fail

    ; BTS on already-set bit
    bts     dword [i386bit_buf], ecx
    jnc     .fail                                ; was 1 → CF=1
    cmp     dword [i386bit_buf], 0x00040000       ; unchanged
    jne     .fail

    ; ========================================================================
    ; TEST 23: BTR m32, r32 — reset bit with register index on memory
    ; ========================================================================
    mov     dword [i386bit_buf], 0x00040000   ; bit 18 set
    mov     ecx, 18
    btr     dword [i386bit_buf], ecx
    jnc     .fail                                ; was 1 → CF=1
    cmp     dword [i386bit_buf], 0x00000000       ; bit 18 cleared
    jne     .fail

    ; BTR on already-clear bit
    btr     dword [i386bit_buf], ecx
    jc      .fail                                ; was 0 → CF=0
    cmp     dword [i386bit_buf], 0x00000000       ; unchanged
    jne     .fail

    ; ========================================================================
    ; TEST 24: BTC m32, r32 — toggle bit with register index on memory
    ; ========================================================================
    mov     dword [i386bit_buf], 0x00000000
    mov     ecx, 25
    btc     dword [i386bit_buf], ecx               ; toggle: 0→1
    jc      .fail                                  ; was 0 → CF=0
    cmp     dword [i386bit_buf], 0x02000000         ; bit 25 set
    jne     .fail

    btc     dword [i386bit_buf], ecx               ; toggle: 1→0
    jnc     .fail                                  ; was 1 → CF=1
    cmp     dword [i386bit_buf], 0x00000000         ; bit 25 cleared
    jne     .fail

    ; ========================================================================
    ; TEST 25: BT r32, r32 — bit test with all boundary indices
    ; Test bits 0 and 31 (boundary cases)
    ; ========================================================================
    mov     eax, 0x00000001                      ; bit 0
    mov     ecx, 0
    bt      eax, ecx
    jnc     .fail

    mov     eax, 0x80000000                      ; bit 31
    mov     ecx, 31
    bt      eax, ecx
    jnc     .fail

    mov     eax, 0x00000001                      ; bit 0
    mov     ecx, 31
    bt      eax, ecx
    jc      .fail                                ; bit 31 is 0

    ; All tests passed
    mov     al, STATUS_PASS
    jmp     .done

.fail:
    mov     al, STATUS_FAIL

.done:
    pop     ebp
    pop     edi
    pop     esi
    pop     edx
    pop     ecx
    pop     ebx
    ret

;---------------------------------------------------------------------------
i386bit_cleanup:
    ret

; --- i386 bitops data ---
i386bit_name: db '80386 Bit Operations', 0

i386bit_buf:  dd 0
