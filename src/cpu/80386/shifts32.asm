;============================================================================
; MODULE: cpu/80386/shifts32.asm
; TIER:   UNIVERSAL
; VENUE:  G
; GEN:    80386+
; ORACLE: manual
; DESC:   80386 double-precision shift instructions:
;         - SHLD r/m16, r16, count:  shift left, fill from source register
;         - SHLD r/m32, r32, count:  32-bit variant
;         - SHRD r/m16, r16, count:  shift right, fill from source register
;         - SHRD r/m32, r32, count:  32-bit variant
;
;         Flags: CF gets last bit shifted out; SF/ZF/PF set per result;
;         OF defined only for count=1. Count masked to 5 bits (mod 32).
;
; REFS:   Intel 80386 PRM Ch. 17 (SHLD, SHRD)
;============================================================================

;---------------------------------------------------------------------------
i386shf_init:
    ret

;---------------------------------------------------------------------------
; i386shf_run
;---------------------------------------------------------------------------
i386shf_run:
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
    ; TEST 1: SHLD r16, r16, imm8 — basic shift left
    ; dest=0x1234, src=0x5678, count=4
    ; Concat = (dest<<16)|src = 0x12345678, shift left 4 → high 16 = 0x2345
    ; CF = bit (32-4)=bit28 of concat = (0x12345678>>28)&1 = 1
    ; ========================================================================
    mov     ax, 0x1234
    mov     bx, 0x5678
    shld    ax, bx, 4
    pushfd
    pop     ecx
    cmp     ax, 0x2345
    jne     .fail
    test    ecx, FLAG_CF
    jz      .fail

    ; ========================================================================
    ; TEST 2: SHLD r16, r16, imm8 — shift by 1
    ; dest=0x8000, src=0x0001, count=1
    ; Concat = 0x80000001, shift left 1 → high 16 = 0x0000
    ; CF = bit 31 = 1
    ; ========================================================================
    mov     ax, 0x8000
    mov     bx, 0x0001
    shld    ax, bx, 1
    cmp     ax, 0x0000
    jne     .fail

    ; ========================================================================
    ; TEST 3: SHLD r16, r16, imm8 — shift by 8
    ; dest=0xABCD, src=0x1234, count=8
    ; Concat = 0xABCD1234, shift left 8 → high 16 = 0xCD12
    ; CF = bit (32-8)=bit24 = (0xABCD1234>>24)&1 = 1
    ; ========================================================================
    mov     ax, 0xABCD
    mov     bx, 0x1234
    shld    ax, bx, 8
    pushfd
    pop     ecx
    cmp     ax, 0xCD12
    jne     .fail
    test    ecx, FLAG_CF
    jz      .fail

    ; ========================================================================
    ; TEST 4: SHLD r16, r16, CL — shift by CL register
    ; dest=0x000F, src=0xFFFF, count=4
    ; Concat = 0x000FFFFF, shift left 4 → high 16 = 0x00FF
    ; ========================================================================
    mov     ax, 0x000F
    mov     dx, 0xFFFF
    mov     cl, 4
    shld    ax, dx, cl
    cmp     ax, 0x00FF
    jne     .fail

    ; ========================================================================
    ; TEST 5: SHLD r32, r32, imm8 — 32-bit shift left
    ; dest=0x12345678, src=0x9ABCDEF0, count=4
    ; Concat = 0x123456789ABCDEF0, shift left 4 → high 32 = 0x23456789
    ; CF = bit 60 = (0x123456789ABCDEF0>>60)&1 = 1
    ; ========================================================================
    mov     eax, 0x12345678
    mov     edx, 0x9ABCDEF0
    shld    eax, edx, 4
    pushfd
    pop     ecx
    cmp     eax, 0x23456789
    jne     .fail
    test    ecx, FLAG_CF
    jz      .fail

    ; ========================================================================
    ; TEST 6: SHLD r32, r32, imm8 — shift by 16
    ; dest=0x0000AAAA, src=0xBBBB0000, count=16
    ; Concat high 32 after shift 16 = 0xAAAABBBB
    ; ========================================================================
    mov     eax, 0x0000AAAA
    mov     edx, 0xBBBB0000
    shld    eax, edx, 16
    cmp     eax, 0xAAAABBBB
    jne     .fail

    ; ========================================================================
    ; TEST 7: SHLD count=0 — no flags modified, dest unchanged
    ; ========================================================================
    stc
    mov     ax, 0x1234
    mov     bx, 0x5678
    shld    ax, bx, 0
    pushfd
    pop     ecx
    cmp     ax, 0x1234
    jne     .fail
    test    ecx, FLAG_CF
    jz      .fail                            ; CF must still be 1

    ; ========================================================================
    ; TEST 8: SHRD r16, r16, imm8 — basic shift right
    ; dest=0x1234, src=0x5678, count=4
    ; Concat = (src<<16)|dest = 0x56781234, shift right 4 → low 16 = 0x8123
    ; CF = bit 3 of concat = (0x56781234>>3)&1 = 0
    ; ========================================================================
    mov     ax, 0x1234
    mov     bx, 0x5678
    shrd    ax, bx, 4
    pushfd
    pop     ecx
    cmp     ax, 0x8123
    jne     .fail
    test    ecx, FLAG_CF
    jnz     .fail                            ; CF should be 0

    ; ========================================================================
    ; TEST 9: SHRD r16, r16, imm8 — shift by 1
    ; dest=0x0001, src=0x8000, count=1
    ; Concat = 0x80000001, shift right 1 → low 16 = 0x0000
    ; CF = bit 0 of concat = 1
    ; ========================================================================
    mov     ax, 0x0001
    mov     bx, 0x8000
    shrd    ax, bx, 1
    pushfd
    pop     ecx
    cmp     ax, 0x0000
    jne     .fail
    test    ecx, FLAG_CF
    jz      .fail                            ; CF should be 1

    ; ========================================================================
    ; TEST 10: SHRD r16, r16, imm8 — shift by 8
    ; dest=0xABCD, src=0x1234, count=8
    ; Concat = 0x1234ABCD, shift right 8 → low 16 = 0x34AB
    ; ========================================================================
    mov     ax, 0xABCD
    mov     bx, 0x1234
    shrd    ax, bx, 8
    cmp     ax, 0x34AB
    jne     .fail

    ; ========================================================================
    ; TEST 11: SHRD r32, r32, imm8 — 32-bit shift right
    ; dest=0x12345678, src=0x9ABCDEF0, count=4
    ; Concat = 0x9ABCDEF012345678, shift right 4 → low 32 = 0x01234567
    ; (0x9ABCDEF0>>4 fills high bits, but low nibble E goes to bit 32 = gone)
    ; ========================================================================
    mov     eax, 0x12345678
    mov     edx, 0x9ABCDEF0
    shrd    eax, edx, 4
    cmp     eax, 0x01234567
    jne     .fail

    ; ========================================================================
    ; TEST 12: SHRD r32, r32, imm8 — shift by 16
    ; dest=0xAAAABBBB, src=0xCCCCDDDD, count=16
    ; Concat = 0xCCCCDDDDAAAABBBB, shift right 16 → low 32 = 0xDDDDAAAA
    ; ========================================================================
    mov     eax, 0xAAAABBBB
    mov     edx, 0xCCCCDDDD
    shrd    eax, edx, 16
    cmp     eax, 0xDDDDAAAA
    jne     .fail

    ; ========================================================================
    ; TEST 13: SHLD with memory operand (16-bit)
    ; dest=[mem]=0x00FF, src=cx=0xFF00, count=8
    ; Concat = 0x00FFFF00, shift left 8 → high 16 = 0xFFFF
    ; ========================================================================
    mov     word [i386shf_buf], 0x00FF
    mov     cx, 0xFF00
    shld    word [i386shf_buf], cx, 8
    cmp     word [i386shf_buf], 0xFFFF
    jne     .fail

    ; ========================================================================
    ; TEST 14: SHRD with memory operand (32-bit)
    ; dest=0xDEADBEEF, src=0xCAFEBABE, count=4
    ; Concat low 32 after shift = 0xEDEADBEE
    ; ========================================================================
    mov     dword [i386shf_buf], 0xDEADBEEF
    mov     ecx, 0xCAFEBABE
    shrd    dword [i386shf_buf], ecx, 4
    cmp     dword [i386shf_buf], 0xEDEADBEE
    jne     .fail

    ; ========================================================================
    ; TEST 15: SHLD r32, r32, imm8 — result zero, ZF=1, CF=1
    ; dest=0x80000000, src=0x00000000, count=1
    ; Concat high 32 after shift 1 = 0x00000000
    ; ========================================================================
    mov     eax, 0x80000000
    mov     edx, 0x00000000
    shld    eax, edx, 1
    pushfd
    pop     ecx
    cmp     eax, 0x00000000
    jne     .fail
    test    ecx, FLAG_ZF
    jz      .fail                            ; ZF must be 1
    test    ecx, FLAG_CF
    jz      .fail                            ; CF must be 1

    ; ========================================================================
    ; TEST 16: SHRD r32, r32, CL — shift by CL register
    ; dest=0xFFFFFFFF, src=0x00000000, count=4
    ; Result = 0x0FFFFFFF
    ; ========================================================================
    mov     eax, 0xFFFFFFFF
    mov     edx, 0x00000000
    mov     cl, 4
    shrd    eax, edx, cl
    cmp     eax, 0x0FFFFFFF
    jne     .fail

    ; ========================================================================
    ; TEST 17: SHLD count masking — CL=32 masks to 0 (no-op)
    ; ========================================================================
    stc                                     ; pre-set CF
    mov     eax, 0x12345678
    mov     edx, 0x9ABCDEF0
    mov     cl, 32                         ; 32 & 0x1F = 0
    shld    eax, edx, cl
    pushfd
    pop     ecx
    cmp     eax, 0x12345678                 ; unchanged
    jne     .fail
    test    ecx, FLAG_CF
    jz      .fail                            ; CF must still be 1

    ; ========================================================================
    ; TEST 18: SHLD count masking — CL=33 masks to 1
    ; ========================================================================
    mov     eax, 0x12345678
    mov     edx, 0x9ABCDEF0
    mov     cl, 33                         ; 33 & 0x1F = 1
    shld    eax, edx, cl
    pushfd
    pop     ecx
    cmp     eax, 0x2468ACF1                 ; (0x12345678<<1)|(0x9ABCDEF0>>31)
    jne     .fail
    test    ecx, FLAG_CF
    jnz     .fail                            ; CF=0 (bit31 of 0x12345678 is 0)

    ; ========================================================================
    ; TEST 19: SHRD count masking — CL=36 masks to 4
    ; ========================================================================
    mov     eax, 0xDEADBEEF
    mov     edx, 0xCAFEBABE
    mov     cl, 36                         ; 36 & 0x1F = 4
    shrd    eax, edx, cl
    cmp     eax, 0xEDEADBEE                 ; same as SHRD ..., 4
    jne     .fail

    ; ========================================================================
    ; TEST 20: SHRD count masking — CL=255 masks to 31
    ; ========================================================================
    mov     eax, 0x80000001
    mov     edx, 0xFFFFFFFF
    mov     cl, 255                        ; 255 & 0x1F = 31
    shrd    eax, edx, cl
    cmp     eax, 0xFFFFFFFF                 ; (0x80000001>>31)|(0xFFFFFFFF<<1)
    jne     .fail

    ; ========================================================================
    ; TEST 21: SHLD count=1 OF=1 — sign bit changes
    ; ========================================================================
    mov     eax, 0x80000000
    mov     edx, 0x00000000
    shld    eax, edx, 1
    pushfd
    pop     ecx
    cmp     eax, 0x00000000
    jne     .fail
    test    ecx, FLAG_CF
    jz      .fail                            ; CF=1
    test    ecx, FLAG_OF
    jz      .fail                            ; OF=1

    ; ========================================================================
    ; TEST 22: SHLD count=1 OF=0 — sign bit unchanged
    ; ========================================================================
    mov     eax, 0x12345678
    mov     edx, 0x9ABCDEF0
    shld    eax, edx, 1
    pushfd
    pop     ecx
    cmp     eax, 0x2468ACF1
    jne     .fail
    test    ecx, FLAG_OF
    jnz     .fail                            ; OF=0

    ; ========================================================================
    ; TEST 23: SHRD count=1 OF=1 — sign bit changes
    ; ========================================================================
    mov     eax, 0x12345678
    mov     edx, 0x9ABCDEF1
    shrd    eax, edx, 1
    pushfd
    pop     ecx
    cmp     eax, 0x891A2B3C
    jne     .fail
    test    ecx, FLAG_OF
    jz      .fail                            ; OF=1

    ; ========================================================================
    ; TEST 24: SHRD count=1 OF=0 — sign bit unchanged
    ; eax=0x80000001 (MSB=1,bit0=1), edx=0x80000001 (bit0=1)
    ; result = (0x80000001>>1)|(0x80000001<<31) = 0x40000000|0x80000000 = 0xC0000000
    ; CF=1, MSB(result)=1 → OF=0 (both SDM and alt defs agree)
    ; ========================================================================
    mov     eax, 0x80000001
    mov     edx, 0x80000001
    shrd    eax, edx, 1
    pushfd
    pop     ecx
    cmp     eax, 0xC0000000
    jne     .fail
    test    ecx, FLAG_OF
    jnz     .fail                            ; OF=0

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
i386shf_cleanup:
    ret

; --- i386 shifts32 data ---
i386shf_name: db '80386 SHLD/SHRD', 0

i386shf_buf: dd 0
