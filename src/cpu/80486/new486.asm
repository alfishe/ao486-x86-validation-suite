;============================================================================
; MODULE: cpu/80486/new486.asm
; TIER:   UNIVERSAL
; VENUE:  G
; GEN:    80486+
; ORACLE: manual
; DESC:   80486-specific new instructions (19 sub-tests):
;         - BSWAP:   byte-swap 32-bit register (5 tests + 2 reg variants)
;         - XADD:    exchange and add (4 tests incl flags + LOCK)
;         - CMPXCHG: compare-and-exchange (4 tests + LOCK)
;         - CPUID:   CPU identification (leaf 0 vendor + leaf 1 features)
;
; REFS:   Intel 80486 PRM §4 (new instructions);
;         Intel SDM Vol. 2B (BSWAP/XADD/CMPXCHG/CPUID opcodes)
;============================================================================

;---------------------------------------------------------------------------
i486_init:
    ret

;---------------------------------------------------------------------------
; i486_run
;---------------------------------------------------------------------------
i486_run:
    push    ebx
    push    ecx
    push    edx
    push    esi
    push    edi
    push    ebp

    ; ========================================================================
    ; Capability gate: 80486+ required
    ; ========================================================================
    mov     al, [g_cpu_type]
    cmp     al, CPU_80486
    jae     .cap_ok
    mov     al, STATUS_SKIP
    jmp     .done

.cap_ok:
    pushfd
    pop     ecx
    mov     [i486_save_flags], ecx

    ; ========================================================================
    ; TEST 1: BSWAP EAX — basic byte reversal
    ; EAX = 0x12345678 → BSWAP → EAX = 0x78563412
    ; ========================================================================
    mov     eax, 0x12345678
    bswap   eax
    cmp     eax, 0x78563412
    jne     .fail

    ; ========================================================================
    ; TEST 2: BSWAP EAX — all zeros
    ; ========================================================================
    mov     eax, 0x00000000
    bswap   eax
    cmp     eax, 0x00000000
    jne     .fail

    ; ========================================================================
    ; TEST 3: BSWAP EAX — all ones
    ; ========================================================================
    mov     eax, 0xFFFFFFFF
    bswap   eax
    cmp     eax, 0xFFFFFFFF
    jne     .fail

    ; ========================================================================
    ; TEST 4: BSWAP different registers (ECX, EDX, EBX)
    ; ========================================================================
    mov     ecx, 0xAABBCCDD
    bswap   ecx
    cmp     ecx, 0xDDCCBBAA
    jne     .fail

    mov     edx, 0x11223344
    bswap   edx
    cmp     edx, 0x44332211
    jne     .fail

    mov     ebx, 0x00000001
    bswap   ebx
    cmp     ebx, 0x01000000
    jne     .fail

    ; ========================================================================
    ; TEST 5: BSWAP round-trip (double BSWAP = identity)
    ; ========================================================================
    mov     eax, 0xDEADBEEF
    bswap   eax
    bswap   eax
    cmp     eax, 0xDEADBEEF
    jne     .fail

    ; ========================================================================
    ; TEST 6: XADD r32, r32 — exchange and add
    ; EAX=0x10, ECX=0x20 → XADD: ECX=old EAX=0x10, EAX=0x10+0x20=0x30
    ; XADD dest, src: dest ← dest+src, src ← old dest
    ; ========================================================================
    mov     eax, 0x10
    mov     ecx, 0x20
    xadd    eax, ecx                      ; EAX=0x30, ECX=0x10
    cmp     eax, 0x30
    jne     .fail
    cmp     ecx, 0x10
    jne     .fail

    ; ========================================================================
    ; TEST 7: XADD flags — verify ZF, CF, OF, SF
    ; EAX=0x7FFFFFFF, ECX=0x1 → sum=0x80000000
    ; CF=0 (no carry out of 32 bits), OF=1 (signed overflow), SF=1, ZF=0
    ; ========================================================================
    mov     eax, 0x7FFFFFFF
    mov     ecx, 0x00000001
    xadd    eax, ecx
    pushfd
    pop     edx
    cmp     eax, 0x80000000               ; result
    jne     .fail
    cmp     ecx, 0x7FFFFFFF               ; old dest
    jne     .fail
    test    edx, FLAG_ZF                  ; ZF=0 (result != 0)
    jnz     .fail
    test    edx, FLAG_SF                  ; SF=1 (MSB set)
    jz      .fail
    test    edx, FLAG_OF                  ; OF=1 (signed overflow: pos+pos=neg)
    jz      .fail

    ; ========================================================================
    ; TEST 8: XADD with zero result — ZF=1
    ; ========================================================================
    mov     eax, 0x00000005
    mov     ecx, 0xFFFFFFFB               ; -5
    xadd    eax, ecx                      ; EAX=0, ECX=5
    pushfd
    pop     edx
    cmp     eax, 0x00000000
    jne     .fail
    test    edx, FLAG_ZF                  ; ZF must be set
    jz      .fail

    ; ========================================================================
    ; TEST 9: XADD memory operand
    ; XADD [mem], reg: mem ← mem+reg, reg ← old mem
    ; ========================================================================
    mov     dword [i486_buf], 100
    mov     eax, 23
    xadd    dword [i486_buf], eax          ; buf=123, eax=old buf=100
    cmp     eax, 100
    jne     .fail
    cmp     dword [i486_buf], 123
    jne     .fail

    ; ========================================================================
    ; TEST 10: CMPXCHG — match case (EAX = dest, exchange succeeds)
    ; CMPXCHG dest, src: if EAX==dest then dest←src, ZF=1
    ;                     else EAX←dest, ZF=0
    ; ========================================================================
    mov     eax, 0xAAAABBBB               ; accumulator (comparand)
    mov     ecx, 0xCCCCDDDD               ; source (new value)
    mov     dword [i486_buf], 0xAAAABBBB  ; dest matches EAX
    cmpxchg dword [i486_buf], ecx         ; match → buf=ecx, ZF=1
    pushfd
    pop     edx
    cmp     dword [i486_buf], 0xCCCCDDDD  ; dest updated
    jne     .fail
    test    edx, FLAG_ZF                  ; ZF must be set
    jz      .fail

    ; ========================================================================
    ; TEST 11: CMPXCHG — mismatch case (EAX != dest, exchange fails)
    ; ========================================================================
    mov     eax, 0x11111111               ; accumulator
    mov     ecx, 0x22222222               ; source
    mov     dword [i486_buf], 0x33333333  ; dest does NOT match EAX
    cmpxchg dword [i486_buf], ecx         ; mismatch → EAX=dest, ZF=0
    pushfd
    pop     edx
    cmp     eax, 0x33333333               ; EAX loaded with current dest
    jne     .fail
    cmp     dword [i486_buf], 0x33333333  ; dest unchanged
    jne     .fail
    test    edx, FLAG_ZF                  ; ZF must be clear
    jnz     .fail

    ; ========================================================================
    ; TEST 12: CMPXCHG register operand — match
    ; ========================================================================
    mov     eax, 0x100
    mov     ebx, 0x200
    mov     ecx, 0x100                    ; dest = comparand
    cmpxchg ecx, ebx                      ; EAX==ECX → ECX=EBX, ZF=1
    pushfd
    pop     edx
    cmp     ecx, 0x200                    ; dest updated
    jne     .fail
    test    edx, FLAG_ZF                  ; ZF set
    jz      .fail

    ; ========================================================================
    ; TEST 13: CMPXCHG register operand — mismatch
    ; ========================================================================
    mov     eax, 0x100
    mov     ebx, 0x200
    mov     ecx, 0x300                    ; dest != comparand
    cmpxchg ecx, ebx                      ; EAX!=ECX → EAX=ECX, ZF=0
    pushfd
    pop     edx
    cmp     eax, 0x300                    ; EAX loaded with dest
    jne     .fail
    cmp     ecx, 0x300                    ; dest unchanged
    jne     .fail
    test    edx, FLAG_ZF                  ; ZF clear
    jnz     .fail

    ; ========================================================================
    ; TEST 14: CPUID — EFLAGS.ID toggle test
    ; If we can toggle EFLAGS bit 21 (ID), CPUID is available
    ; ========================================================================
    pushfd
    pop     eax                           ; EAX = EFLAGS
    mov     ecx, eax                      ; save original
    xor     eax, 0x00200000               ; toggle ID bit
    push    eax
    popfd                                 ; write back to EFLAGS
    pushfd
    pop     eax                           ; re-read EFLAGS
    xor     eax, ecx                      ; if ID toggled, bit21 differs
    test    eax, 0x00200000               ; check if ID bit changed
    jz      .no_cpuid                     ; ID bit stuck → no CPUID

    ; CPUID is available — execute leaf 0
    mov     byte [i486_cpuid_ok], 1       ; mark CPUID available
    xor     eax, eax                      ; leaf 0
    cpuid
    ; EBX:ECX:EDX = vendor string (12 chars)
    ; Just verify we get a non-zero vendor string
    mov     eax, ebx
    or      eax, edx
    or      eax, ecx
    test    eax, eax
    jz      .fail                         ; vendor string must not be all zeros
    jmp     .cpuid_ok

.no_cpuid:
    ; CPUID not available on early 486 — this is valid, not a failure
    mov     byte [i486_cpuid_ok], 0       ; mark CPUID unavailable
    ; Restore flags and continue
    push    dword [i486_save_flags]
    popfd

.cpuid_ok:
    ; ========================================================================
    ; TEST 15: BSWAP ESI, EDI (verify remaining registers)
    ; ESP/EBP not tested to avoid stack corruption
    ; ========================================================================
    mov     esi, 0xCAFEBABE
    bswap   esi
    cmp     esi, 0xBEBAFECA
    jne     .fail

    mov     edi, 0x0F0E0D0C
    bswap   edi
    cmp     edi, 0x0C0D0E0F
    jne     .fail
    ; ========================================================================
    ; TEST 16: XADD with CF — carry flag on addition with carry out
    ; 0xFFFFFFFF + 0x1 = 0x100000000 → wraps to 0, CF=1
    ; ========================================================================
    mov     eax, 0xFFFFFFFF
    mov     ecx, 0x00000001
    xadd    eax, ecx                      ; EAX=0, ECX=0xFFFFFFFF
    pushfd
    pop     edx
    cmp     eax, 0x00000000
    jne     .fail
    cmp     ecx, 0xFFFFFFFF
    jne     .fail
    test    edx, FLAG_CF                  ; CF must be set (carry out)
    jz      .fail
    test    edx, FLAG_ZF                  ; ZF must be set (result=0)
    jz      .fail

    ; ========================================================================
    ; TEST 17: CPUID Leaf 1 — family/model/stepping/features
    ; Skipped gracefully if CPUID unavailable (early 486).
    ; ========================================================================
    cmp     byte [i486_cpuid_ok], 0
    je      .test18                       ; no CPUID — skip leaf 1
    mov     eax, 1                        ; leaf 1
    cpuid
    ; EAX = family/model/stepping — must be non-zero
    test    eax, eax
    jz      .fail
    ; EDX feature flags: bit 0 = on-chip FPU (should be set on 486DX)
    test    edx, 1
    jz      .fail

.test18:
    ; ========================================================================
    ; TEST 18: LOCK XADD — locked exchange-and-add (memory)
    ; Verifies LOCK prefix decoding + correct result.
    ; ========================================================================
    mov     dword [i486_buf], 100
    mov     eax, 23
    lock xadd dword [i486_buf], eax       ; buf=123, eax=old buf=100
    cmp     eax, 100
    jne     .fail
    cmp     dword [i486_buf], 123
    jne     .fail

    ; ========================================================================
    ; TEST 19: LOCK CMPXCHG — locked compare-and-exchange (memory)
    ; Match case: EAX==[mem] → exchange succeeds, ZF=1.
    ; ========================================================================
    mov     eax, 0x12345678               ; comparand
    mov     ecx, 0xABCDEF00               ; new value
    mov     dword [i486_buf], 0x12345678  ; dest matches EAX
    lock cmpxchg dword [i486_buf], ecx   ; match → buf=ecx, ZF=1
    pushfd
    pop     edx
    cmp     dword [i486_buf], 0xABCDEF00  ; dest updated
    jne     .fail
    test    edx, FLAG_ZF                  ; ZF must be set
    jz      .fail

    ; All tests passed
    mov     al, STATUS_PASS
    jmp     .done

.fail:
    mov     al, STATUS_FAIL

.done:
    ; Restore flags
    push    dword [i486_save_flags]
    popfd

    pop     ebp
    pop     edi
    pop     esi
    pop     edx
    pop     ecx
    pop     ebx
    ret

;---------------------------------------------------------------------------
i486_cleanup:
    ret

; --- data ---
i486_name: db '80486 New Instructions', 0

i486_save_flags: dd 0
i486_buf:        dd 0
i486_cpuid_ok:   db 0
