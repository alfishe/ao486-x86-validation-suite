;============================================================================
; MODULE: cpu/80386/addr32.asm
; TIER:   UNIVERSAL
; VENUE:  G
; GEN:    80386+
; ORACLE: manual
; DESC:   80386 32-bit addressing modes and prefixes:
;         - SIB (Scale-Index-Base) byte: [base+index*scale+disp]
;           Scales: ×1, ×2, ×4, ×8
;           Base=EBP with mod=0 → disp32 only (no base register)
;           Index=ESP → illegal (index cannot be ESP)
;         - Operand-size prefix (0x66): switch 16-bit ↔ 32-bit data
;         - Address-size prefix (0x67): switch 16-bit ↔ 32-bit addressing
;
; REFS:   Intel 80386 PRM Ch. 2.5 (Addressing Modes), Ch. 17
;         Intel 80386 Hardware Reference Manual §4 (SIB encoding)
;============================================================================

;---------------------------------------------------------------------------
i386addr_init:
    ret

;---------------------------------------------------------------------------
; i386addr_run
;---------------------------------------------------------------------------
i386addr_run:
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
    ; TEST 1: SIB [base+index*1] — scale=1
    ; Load from [EBX + ESI*1] where the memory has a known value
    ; ========================================================================
    mov     ebx, i386addr_buf              ; base
    mov     esi, 4                          ; index offset (4 bytes)
    mov     eax, [ebx + esi*1]
    cmp     eax, 0x44332211
    jne     .fail

    ; ========================================================================
    ; TEST 2: SIB [base+index*2] — scale=2
    ; ========================================================================
    mov     ebx, i386addr_buf
    mov     esi, 2                          ; index * 2 = 4 byte offset
    mov     eax, [ebx + esi*2]
    cmp     eax, 0x44332211
    jne     .fail

    ; ========================================================================
    ; TEST 3: SIB [base+index*4] — scale=4 (array indexing)
    ; ========================================================================
    mov     ebx, i386addr_buf
    mov     esi, 1                          ; index * 4 = 4 byte offset
    mov     eax, [ebx + esi*4]
    cmp     eax, 0x44332211
    jne     .fail

    ; ========================================================================
    ; TEST 4: SIB [base+index*8] — scale=8
    ; ========================================================================
    mov     ebx, i386addr_buf
    mov     esi, 1                          ; index * 8 = 8 byte offset
    mov     eax, [ebx + esi*8]
    cmp     eax, 0x88776655
    jne     .fail

    ; ========================================================================
    ; TEST 5: SIB [index*scale + disp32] — no base register
    ; (base=EBP with mod=0 → pure disp32, encoded as [disp + index*scale])
    ; Use NASM syntax: [esi*4 + i386addr_buf]
    ; ========================================================================
    mov     esi, 1                          ; index * 4 = 4 byte offset
    mov     eax, [esi*4 + i386addr_buf]
    cmp     eax, 0x44332211
    jne     .fail

    ; ========================================================================
    ; TEST 6: SIB with displacement [base+index*scale+disp8]
    ; ========================================================================
    mov     ebx, i386addr_buf
    mov     esi, 0                          ; index = 0
    mov     eax, [ebx + esi*4 + 4]         ; = buf + 0 + 4
    cmp     eax, 0x44332211
    jne     .fail

    ; ========================================================================
    ; TEST 7: SIB with displacement [base+index*scale+disp32]
    ; ========================================================================
    mov     ebx, 0                          ; base = 0
    mov     esi, 0                          ; index = 0
    mov     eax, [ebx + esi*1 + i386addr_buf]
    cmp     eax, 0x11223344
    jne     .fail

    ; ========================================================================
    ; TEST 8: SIB store [base+index*scale] — write test
    ; ========================================================================
    mov     ebx, i386addr_buf2
    mov     esi, 2                          ; offset 2*4 = 8
    mov     dword [ebx + esi*4], 0xDEADBEEF
    cmp     dword [i386addr_buf2 + 8], 0xDEADBEEF
    jne     .fail

    ; ========================================================================
    ; TEST 9: SIB using different base registers
    ; Test EBP as base, EDI as index
    ; ========================================================================
    mov     ebp, i386addr_buf
    mov     edi, 2                          ; index * 1 = 2 → dword at buf+2 is unaligned
    ; Use scale=4 so EDI*4 = 8
    mov     eax, [ebp + edi*4]
    cmp     eax, 0x88776655
    jne     .fail

    ; ========================================================================
    ; TEST 10: SIB with ECX as base, EDX as index, scale 2
    ; ========================================================================
    mov     ecx, i386addr_buf
    mov     edx, 2                          ; index * 2 = 4 byte offset
    mov     eax, [ecx + edx*2]
    cmp     eax, 0x44332211
    jne     .fail

    ; ========================================================================
    ; TEST 11: Operand-size prefix (0x66) — 16-bit op in 32-bit context
    ; MOV AX, [mem] with 0x66 prefix reads 16 bits
    ; ========================================================================
    mov     ax, word [i386addr_buf]         ; low word of first dword
    cmp     ax, 0x3344
    jne     .fail

    ; ========================================================================
    ; TEST 12: Operand-size prefix — 32-bit op with immediate in 16-bit code
    ; We are in BITS 16; using 32-bit register is already prefixed.
    ; Test that MOV EAX, [mem] works (0x66 prefix auto-added by NASM)
    ; ========================================================================
    mov     eax, [i386addr_buf]
    cmp     eax, 0x11223344
    jne     .fail

    ; ========================================================================
    ; TEST 13: Address-size prefix (0x67) — 32-bit addressing in 16-bit mode
    ; Use explicit [dword disp32] addressing
    ; ========================================================================
    mov     eax, [dword i386addr_buf]
    cmp     eax, 0x11223344
    jne     .fail

    ; ========================================================================
    ; TEST 14: Mixed prefix — 0x67 + 0x66 (addr32 + data32)
    ; MOV EAX, [EBX+ESI*4] uses both address and operand size prefixes
    ; ========================================================================
    mov     ebx, i386addr_buf
    mov     esi, 3                          ; index * 4 = 12 byte offset
    mov     eax, [ebx + esi*4]
    cmp     eax, 0x55667788                 ; buf[3] at offset 12
    jne     .fail

    ; ========================================================================
    ; TEST 15: SIB LEA — compute effective address
    ; LEA EAX, [EBX + ESI*4 + 8] should give base + index*scale + disp
    ; ========================================================================
    mov     ebx, 0x1000
    mov     esi, 3
    lea     eax, [ebx + esi*4 + 8]
    cmp     eax, 0x1000 + 12 + 8
    jne     .fail

    ; ========================================================================
    ; TEST 16: LEA with scale=8
    ; ========================================================================
    mov     ebx, 0x2000
    mov     esi, 5
    lea     eax, [ebx + esi*8]
    cmp     eax, 0x2000 + 40
    jne     .fail

    ; ========================================================================
    ; TEST 17: LEA with no-base (disp32 + index*scale)
    ; ========================================================================
    mov     esi, 2
    lea     eax, [esi*4 + 0x1000]
    cmp     eax, 0x1008
    jne     .fail

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
i386addr_cleanup:
    ret

; --- i386 addr32 data ---
i386addr_name: db '80386 Addressing/SIB', 0

align 4
i386addr_buf:  dd 0x11223344, 0x44332211, 0x88776655, 0x55667788
               dd 0x99AABBCC, 0xCCBBAA99, 0xDDEEFF00, 0x00FFEEDD
i386addr_buf2: dd 0, 0, 0, 0
