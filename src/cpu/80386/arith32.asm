;============================================================================
; MODULE: cpu/80386/arith32.asm
; TIER:   UNIVERSAL
; VENUE:  G
; GEN:    80386+
; ORACLE: manual
; DESC:   32-bit arithmetic operations introduced/enabled by the 80386:
;         - 32-bit ADD/SUB with result and flag corners (CF, OF, SF, ZF)
;         - 32-bit INC/DEC/NEG (affects OF/SF/ZF, INC/DEC don't affect CF)
;         - 32-bit MUL (EDX:EAX = EAX * r/m32) with CF/OF overflow test
;         - 32-bit IMUL (signed) with CF/OF
;         - IMUL r32, r/m32, imm8/imm32 (3-operand form, 32-bit)
;         - 32-bit DIV/IDIV
;         - 32-bit XCHG, CMP, MOV imm
;         - 32-bit logic (AND/OR/XOR) and shifts (SHL/SHR/SAR/ROL/ROR)
;
; REFS:   Intel 80386 PRM Ch. 3 (Arithmetic), Ch. 17 (instruction set)
;============================================================================

;---------------------------------------------------------------------------
i386a32_init:
    ret

;---------------------------------------------------------------------------
; i386a32_run
;---------------------------------------------------------------------------
i386a32_run:
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
    ; TEST 1: 32-bit ADD — carry out (0xFFFFFFFF + 1 = 0, CF=1, ZF=1)
    ; ========================================================================
    mov     eax, 0xFFFFFFFF
    add     eax, 1
    pushfd
    pop     ecx
    cmp     eax, 0x00000000
    jne     .fail
    test    ecx, FLAG_CF
    jz      .fail                           ; CF must be 1
    test    ecx, FLAG_ZF
    jz      .fail                           ; ZF must be 1

    ; ========================================================================
    ; TEST 2: 32-bit ADD — signed overflow (0x7FFFFFFF + 1, OF=1)
    ; ========================================================================
    mov     eax, 0x7FFFFFFF
    add     eax, 1
    pushfd
    pop     ecx
    cmp     eax, 0x80000000
    jne     .fail
    test    ecx, FLAG_OF
    jz      .fail                           ; OF must be 1

    ; ========================================================================
    ; TEST 3: 32-bit SUB — borrow (0 - 1 = 0xFFFFFFFF, CF=1)
    ; ========================================================================
    mov     eax, 0x00000000
    sub     eax, 1
    pushfd
    pop     ecx
    cmp     eax, 0xFFFFFFFF
    jne     .fail
    test    ecx, FLAG_CF
    jz      .fail                           ; CF must be 1

    ; ========================================================================
    ; TEST 4: 32-bit SUB — signed overflow (0x80000000 - 1, OF=1)
    ; ========================================================================
    mov     eax, 0x80000000
    sub     eax, 1
    pushfd
    pop     ecx
    cmp     eax, 0x7FFFFFFF
    jne     .fail
    test    ecx, FLAG_OF
    jz      .fail                           ; OF must be 1

    ; ========================================================================
    ; TEST 5: 32-bit INC — does NOT affect CF
    ; ========================================================================
    clc
    mov     eax, 0xFFFFFFFE
    inc     eax
    pushfd
    pop     ecx
    cmp     eax, 0xFFFFFFFF
    jne     .fail
    test    ecx, FLAG_CF
    jnz     .fail                           ; CF must still be 0

    ; ========================================================================
    ; TEST 6: 32-bit DEC — does NOT affect CF
    ; ========================================================================
    stc
    mov     eax, 0x00000001
    dec     eax
    pushfd
    pop     ecx
    cmp     eax, 0x00000000
    jne     .fail
    test    ecx, FLAG_CF
    jz      .fail                           ; CF must still be 1

    ; ========================================================================
    ; TEST 7: 32-bit NEG — two's complement
    ; ========================================================================
    mov     eax, 0x00000001
    neg     eax
    pushfd
    pop     ecx
    cmp     eax, 0xFFFFFFFF
    jne     .fail
    test    ecx, FLAG_CF
    jz      .fail                           ; NEG sets CF=1 unless operand=0

    ; NEG(0) = 0, CF=0
    mov     eax, 0
    neg     eax
    pushfd
    pop     ecx
    cmp     eax, 0
    jne     .fail
    test    ecx, FLAG_CF
    jnz     .fail                           ; CF=0 when operand was 0

    ; ========================================================================
    ; TEST 8: 32-bit MUL — unsigned multiply with overflow
    ; ========================================================================
    mov     eax, 0x00010000
    mov     ecx, 0x00010000
    mul     ecx
    pushfd
    pop     ecx
    cmp     eax, 0x00000000
    jne     .fail
    cmp     edx, 0x00000001
    jne     .fail
    ; CF/OF check: pushf was after MUL but before the CMPs
    ; The CMPs clobber flags, but we saved them in ECX
    ; NOTE: ECX was also the multiplier register... oops.
    ; Need to use a different register for flag save.
    ; Actually ECX was clobbered by MUL (MUL uses EDX:EAX, not ECX)
    ; But we popped flags into ECX AFTER the MUL, which is fine.
    ; However, ECX here holds the flags, not the multiplier.
    ; Wait - we set ECX=0x00010000 as the multiplier, then MUL clobbers EDX:EAX.
    ; ECX is NOT clobbered by MUL. Then pushf/pop ECX overwrites ECX with flags.
    ; So the CMP EDX, 0x00000001 check is fine (EDX is from MUL).
    ; But we lost ECX (flags are in ECX now). The test ecx check below is correct.
    test    ecx, FLAG_CF
    jz      .fail                           ; CF=1 (EDX nonzero)

    ; ========================================================================
    ; TEST 9: 32-bit MUL — no overflow
    ; ========================================================================
    mov     eax, 100
    mov     ecx, 200
    mul     ecx
    pushfd
    pop     ecx
    cmp     eax, 20000
    jne     .fail
    cmp     edx, 0
    jne     .fail
    test    ecx, FLAG_CF
    jnz     .fail                           ; CF=0

    ; ========================================================================
    ; TEST 10: 32-bit IMUL — signed (-1 * -1 = 1, CF=0)
    ; ========================================================================
    mov     eax, -1
    mov     ecx, -1
    imul    ecx
    pushfd
    pop     ecx
    cmp     eax, 1
    jne     .fail
    cmp     edx, 0
    jne     .fail
    test    ecx, FLAG_CF
    jnz     .fail                           ; CF=0 (no overflow)

    ; ========================================================================
    ; TEST 11: 32-bit IMUL — signed overflow
    ; ========================================================================
    mov     eax, 0x00010000
    mov     ecx, 0x00010000
    imul    ecx
    pushfd
    pop     ecx
    cmp     eax, 0x00000000
    jne     .fail
    cmp     edx, 0x00000001
    jne     .fail
    test    ecx, FLAG_CF
    jz      .fail                           ; CF=1 (overflow)

    ; ========================================================================
    ; TEST 12: IMUL r32, r/m32, imm8 — 3-operand form
    ; ========================================================================
    mov     eax, 100
    imul    ebx, eax, 10
    cmp     ebx, 1000
    jne     .fail

    mov     eax, 50
    imul    ebx, eax, -3
    cmp     ebx, -150
    jne     .fail

    ; ========================================================================
    ; TEST 13: IMUL r32, r/m32, imm32 — 3-operand with 32-bit immediate
    ; ========================================================================
    mov     eax, 3
    imul    ebx, eax, 100000
    cmp     ebx, 300000
    jne     .fail

    ; ========================================================================
    ; TEST 14: IMUL r32, r/m32 — 2-operand form
    ; ========================================================================
    mov     ebx, 7
    mov     eax, 6
    imul    ebx, eax
    cmp     ebx, 42
    jne     .fail

    ; ========================================================================
    ; TEST 15: 32-bit DIV — unsigned division
    ; ========================================================================
    mov     edx, 0
    mov     eax, 100
    mov     ecx, 7
    div     ecx
    cmp     eax, 14
    jne     .fail
    cmp     edx, 2
    jne     .fail

    ; ========================================================================
    ; TEST 16: 32-bit IDIV — signed division
    ; ========================================================================
    mov     eax, -100
    cdq
    mov     ecx, 7
    idiv    ecx
    cmp     eax, -14
    jne     .fail
    cmp     edx, -2
    jne     .fail

    ; ========================================================================
    ; TEST 17: 32-bit XCHG with memory
    ; ========================================================================
    mov     dword [i386a32_buf], 0xDEADBEEF
    mov     eax, 0xCAFEBABE
    xchg    eax, dword [i386a32_buf]
    cmp     eax, 0xDEADBEEF
    jne     .fail
    cmp     dword [i386a32_buf], 0xCAFEBABE
    jne     .fail

    ; ========================================================================
    ; TEST 18: 32-bit CMP — equality and borrow
    ; ========================================================================
    mov     eax, 0x12345678
    cmp     eax, 0x12345678
    jnz     .fail

    mov     eax, 0x12345678
    cmp     eax, 0x12345679
    jnc     .fail                           ; CF=1 (borrow)

    ; ========================================================================
    ; TEST 19: 32-bit ADD to memory
    ; ========================================================================
    mov     dword [i386a32_buf], 0x00000001
    add     dword [i386a32_buf], 0x00000002
    cmp     dword [i386a32_buf], 0x00000003
    jne     .fail

    ; ========================================================================
    ; TEST 20: 32-bit XCHG EAX, r32
    ; ========================================================================
    mov     eax, 0x11111111
    mov     ebx, 0x22222222
    xchg    eax, ebx
    cmp     eax, 0x22222222
    jne     .fail
    cmp     ebx, 0x11111111
    jne     .fail

    ; ========================================================================
    ; TEST 21: 32-bit MOV with immediate
    ; ========================================================================
    mov     eax, 0xDEADBEEF
    cmp     eax, 0xDEADBEEF
    jne     .fail

    ; ========================================================================
    ; TEST 22: 32-bit AND/OR/XOR — logic ops clear CF/OF
    ; ========================================================================
    mov     eax, 0xF0F0F0F0
    and     eax, 0x0F0F0F0F
    jnz     .fail                           ; result=0, ZF=1
    jc      .fail                           ; AND clears CF
    jo      .fail                           ; AND clears OF

    mov     eax, 0xF0F00000
    or      eax, 0x0000F0F0
    cmp     eax, 0xF0F0F0F0
    jne     .fail

    mov     eax, 0xFFFFFFFF
    xor     eax, eax
    jnz     .fail                           ; ZF=1

    ; ========================================================================
    ; TEST 23: 32-bit SHL — CF gets MSB
    ; ========================================================================
    mov     eax, 0x80000000
    shl     eax, 1
    jc      .t23_ok                         ; CF=1 (bit 31 shifted out)
    jmp     .fail
.t23_ok:
    cmp     eax, 0x00000000
    jne     .fail

    ; ========================================================================
    ; TEST 24: 32-bit SHR — CF gets LSB
    ; ========================================================================
    mov     eax, 0x00000001
    shr     eax, 1
    jc      .t24_ok                         ; CF=1 (bit 0 was 1)
    jmp     .fail
.t24_ok:
    cmp     eax, 0
    jne     .fail

    ; ========================================================================
    ; TEST 25: 32-bit SAR — arithmetic right shift (preserves sign)
    ; ========================================================================
    mov     eax, 0x80000000
    sar     eax, 4
    cmp     eax, 0xF8000000
    jne     .fail

    ; ========================================================================
    ; TEST 26: 32-bit ROL by 8 — byte rotation
    ; ========================================================================
    mov     eax, 0x12345678
    rol     eax, 8
    cmp     eax, 0x34567812
    jne     .fail

    ; ========================================================================
    ; TEST 27: 32-bit ROR by 16 — swap halves
    ; ========================================================================
    mov     eax, 0x12345678
    ror     eax, 16
    cmp     eax, 0x56781234
    jne     .fail

    ; ========================================================================
    ; TEST 28: 32-bit ADC — carry in (0xFFFFFFFF + 0 + CF=1 = 0, CF=1)
    ; ========================================================================
    stc                                     ; set CF=1
    mov     eax, 0xFFFFFFFF
    adc     eax, 0                          ; +0 + CF(1) = 0 with CF=1
    pushfd
    pop     ecx
    cmp     eax, 0x00000000
    jne     .fail
    test    ecx, FLAG_CF
    jz      .fail                           ; CF must be 1
    test    ecx, FLAG_ZF
    jz      .fail                           ; ZF must be 1

    ; ========================================================================
    ; TEST 29: 32-bit ADC — no carry in (0xFFFFFFFF + 0 + CF=0 = 0xFFFFFFFF, CF=0)
    ; ========================================================================
    clc                                     ; CF=0
    mov     eax, 0xFFFFFFFF
    adc     eax, 0
    pushfd
    pop     ecx
    cmp     eax, 0xFFFFFFFF
    jne     .fail
    test    ecx, FLAG_CF
    jnz     .fail                           ; CF must be 0

    ; ========================================================================
    ; TEST 30: 32-bit ADC — carry chain threading
    ; Multi-precision: 0xFFFFFFFF + 0x00000001 = 0x100000000
    ; Lower dword: 0xFFFFFFFF + 1 = 0x00000000 CF=1
    ; Upper dword: 0x00000000 + 0 + CF(1) = 0x00000001 CF=0
    ; ========================================================================
    mov     eax, 0xFFFFFFFF
    mov     ebx, 0x00000000
    add     eax, 1                          ; lower dword, sets CF=1
    mov     dword [i386a32_buf], eax        ; save lower result
    adc     ebx, 0                          ; upper dword + carry
    cmp     dword [i386a32_buf], 0x00000000
    jne     .fail
    cmp     ebx, 0x00000001
    jne     .fail

    ; ========================================================================
    ; TEST 31: 32-bit SBB — borrow in (0 - 0 - CF=1 = 0xFFFFFFFF, CF=1)
    ; ========================================================================
    stc                                     ; CF=1
    mov     eax, 0x00000000
    sbb     eax, 0                          ; 0 - 0 - CF(1) = 0xFFFFFFFF, CF=1
    pushfd
    pop     ecx
    cmp     eax, 0xFFFFFFFF
    jne     .fail
    test    ecx, FLAG_CF
    jz      .fail                           ; CF must be 1 (borrow)

    ; ========================================================================
    ; TEST 32: 32-bit SBB — no borrow in (0 - 0 - CF=0 = 0, CF=0)
    ; ========================================================================
    clc                                     ; CF=0
    mov     eax, 0x00000000
    sbb     eax, 0                          ; 0 - 0 - 0 = 0, CF=0
    pushfd
    pop     ecx
    cmp     eax, 0x00000000
    jne     .fail
    test    ecx, FLAG_CF
    jnz     .fail                           ; CF must be 0

    ; ========================================================================
    ; TEST 33: 32-bit SBB — borrow chain (multi-precision subtract)
    ; Compute 0x0000000100000000 - 0x0000000000000001 = 0x00000000FFFFFFFF
    ; Lower dword: 0x00000000 - 0x00000001 = CF=1, result=0xFFFFFFFF
    ; Upper dword: 0x00000001 - 0 - CF(1) = 0x00000000
    ; ========================================================================
    mov     eax, 0x00000000                 ; lower minuend
    mov     ebx, 0x00000001                 ; upper minuend
    sub     eax, 1                          ; lower: 0 - 1, sets CF=1
    mov     dword [i386a32_buf], eax        ; save lower result
    sbb     ebx, 0                          ; upper: 1 - 0 - CF(1) = 0
    cmp     dword [i386a32_buf], 0xFFFFFFFF
    jne     .fail
    cmp     ebx, 0x00000000
    jne     .fail

    ; ========================================================================
    ; TEST 34: 32-bit ADC — signed overflow (0x7FFFFFFF + 0 + CF=0, OF=0)
    ; ========================================================================
    clc
    mov     eax, 0x7FFFFFFF
    adc     eax, 0
    pushfd
    pop     ecx
    cmp     eax, 0x7FFFFFFF
    jne     .fail
    test    ecx, FLAG_OF
    jnz     .fail                           ; OF=0 (no signed overflow)

    ; ========================================================================
    ; TEST 35: 32-bit ADC with immediate — ADC EAX, imm32
    ; ========================================================================
    clc
    mov     eax, 0x10000000
    adc     eax, 0x70000000                  ; = 0x80000000, CF=0, OF=1
    pushfd
    pop     ecx
    cmp     eax, 0x80000000
    jne     .fail
    test    ecx, FLAG_OF
    jz      .fail                           ; OF=1 (pos+pos=neg = overflow)

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
i386a32_cleanup:
    ret

; --- i386 arith32 data ---
i386a32_name: db '80386 32-bit Arithmetic', 0

i386a32_buf: dd 0
