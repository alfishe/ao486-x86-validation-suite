;============================================================================
; MODULE: cpu/80386/strings32.asm
; TIER:   UNIVERSAL
; VENUE:  G
; GEN:    80386+
; ORACLE: manual
; DESC:   80386 32-bit string operations:
;         - MOVSD: move dword [DS:ESI] -> [ES:EDI]
;         - STOSD: store EAX to [ES:EDI]
;         - CMPSD: compare [DS:ESI] with [ES:EDI]
;         - SCASD: compare EAX with [ES:EDI]
;         - LODSD: load [DS:ESI] into EAX
;         - REP/REPE/REPNE prefixes with ECX counter
;         - DF direction (forward/backward, ESI/EDI increment/decrement by 4)
;
; REFS:   Intel 80386 PRM Ch. 3.7 (String Instructions), Ch. 17
;============================================================================

;---------------------------------------------------------------------------
i386str_init:
    ret

;---------------------------------------------------------------------------
; i386str_run
;---------------------------------------------------------------------------
i386str_run:
    push    ebx
    push    ecx
    push    edx
    push    esi
    push    edi
    push    ebp

    ; ES = DS for all string ops (flat .COM model)
    push    ds
    pop     es

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
    ; TEST 1: MOVSD forward (DF=0) — copy 4 dwords, verify
    ; ESI/EDI should increment by 4 per iteration
    ; ========================================================================
    cld
    mov     esi, i386str_src
    mov     edi, i386str_dst
    mov     ecx, 4
    rep     movsd
    ; Verify: dst should match src
    mov     esi, i386str_src
    mov     edi, i386str_dst
    mov     ecx, 4
.repe_cmp1:
    mov     eax, [esi]
    cmp     eax, [edi]
    jne     .fail
    add     esi, 4
    add     edi, 4
    loop    .repe_cmp1
    ; ESI/EDI should have advanced by 16 (4 dwords * 4 bytes)
    sub     esi, i386str_src
    cmp     esi, 16
    jne     .fail

    ; ========================================================================
    ; TEST 2: MOVSD backward (DF=1) — copy 4 dwords in reverse
    ; ESI/EDI should DECREMENT by 4 per iteration
    ; Start at the END of the buffers
    ; ========================================================================
    std
    mov     esi, i386str_src + 12          ; point to last dword
    mov     edi, i386str_dst2 + 12
    mov     ecx, 4
    rep     movsd
    cld                                     ; restore DF immediately
    ; Verify: dst2 should match src
    mov     esi, i386str_src
    mov     edi, i386str_dst2
    mov     ecx, 4
.repe_cmp2:
    mov     eax, [esi]
    cmp     eax, [edi]
    jne     .fail
    add     esi, 4
    add     edi, 4
    loop    .repe_cmp2

    ; ========================================================================
    ; TEST 3: REP STOSD — fill memory with EAX pattern (DF=0)
    ; ========================================================================
    cld
    mov     edi, i386str_dst
    mov     eax, 0xDEADBEEF
    mov     ecx, 4
    rep     stosd
    ; Verify all 4 dwords
    mov     edi, i386str_dst
    cmp     dword [edi],      0xDEADBEEF
    jne     .fail
    cmp     dword [edi +  4], 0xDEADBEEF
    jne     .fail
    cmp     dword [edi +  8], 0xDEADBEEF
    jne     .fail
    cmp     dword [edi + 12], 0xDEADBEEF
    jne     .fail

    ; ========================================================================
    ; TEST 4: STOSD backward (DF=1) — EDI decrements by 4
    ; ========================================================================
    std
    mov     edi, i386str_dst2 + 12          ; last dword
    mov     eax, 0xCAFEBABE
    mov     ecx, 4
    rep     stosd
    cld
    ; Verify
    cmp     dword [i386str_dst2],      0xCAFEBABE
    jne     .fail
    cmp     dword [i386str_dst2 +  4], 0xCAFEBABE
    jne     .fail
    cmp     dword [i386str_dst2 +  8], 0xCAFEBABE
    jne     .fail
    cmp     dword [i386str_dst2 + 12], 0xCAFEBABE
    jne     .fail

    ; ========================================================================
    ; TEST 5: LODSD forward — load dwords from memory into EAX
    ; ========================================================================
    cld
    mov     esi, i386str_src
    lodsd
    cmp     eax, 0x11223344
    jne     .fail
    lodsd
    cmp     eax, 0x55667788
    jne     .fail
    ; ESI should have advanced by 8
    sub     esi, i386str_src
    cmp     esi, 8
    jne     .fail

    ; ========================================================================
    ; TEST 6: LODSD backward (DF=1) — ESI decrements by 4
    ; ========================================================================
    std
    mov     esi, i386str_src + 12           ; last dword
    lodsd
    cld
    cmp     eax, 0xDDEEFF00                 ; [src+12] = 4th dword
    jne     .fail
    ; ESI should have decremented to i386str_src + 8
    cmp     esi, i386str_src + 8
    jne     .fail

    ; ========================================================================
    ; TEST 7: CMPSD forward — compare, ZF set per result
    ; ========================================================================
    cld
    mov     esi, i386str_src
    mov     edi, i386str_src                ; same data = equal
    cmpsd
    jne     .fail                           ; ZF=1 expected (equal)

    ; Now compare different data
    mov     esi, i386str_src
    mov     edi, i386str_dst                ; different data (was overwritten)
    cmpsd
    je      .fail                           ; ZF=0 expected (not equal)

    ; ========================================================================
    ; TEST 8: REPE CMPSD — compare until mismatch
    ; ========================================================================
    cld
    mov     esi, i386str_src                ; 0x11223344, 0x55667788, 0x99AABBCC, ...
    mov     edi, i386str_src                ; same → all equal
    mov     ecx, 4
    repe    cmpsd
    ; All 4 matched, ECX should be 0, ZF=1
    jecxz   .t8_ok
    jmp     .fail
.t8_ok:
    ; ZF should be set after the last comparison
    jnz     .fail

    ; ========================================================================
    ; TEST 9: REPNE SCASD — scan for non-matching value
    ; ========================================================================
    cld
    mov     edi, i386str_src
    mov     eax, 0x11223344                 ; first dword matches
    mov     ecx, 4
    repne   scasd
    ; Should stop after 1 iteration (found match)
    cmp     ecx, 3                          ; 4 - 1 = 3 remaining
    jne     .fail

    ; ========================================================================
    ; TEST 10: SCASD — compare EAX with [ES:EDI], set flags
    ; ========================================================================
    cld
    mov     edi, i386str_src + 4            ; second dword = 0x55667788
    mov     eax, 0x55667788
    scasd
    jne     .fail                           ; ZF=1 (match)

    mov     edi, i386str_src + 4
    mov     eax, 0x00000000
    scasd
    je      .fail                           ; ZF=0 (no match)

    ; ========================================================================
    ; TEST 11: REP MOVSD with ECX=0 — no operation, ESI/EDI unchanged
    ; ========================================================================
    cld
    mov     esi, i386str_src
    mov     edi, i386str_dst
    mov     ecx, 0
    rep     movsd
    ; ESI and EDI must be unchanged
    cmp     esi, i386str_src
    jne     .fail
    cmp     edi, i386str_dst
    jne     .fail

    ; ========================================================================
    ; TEST 12: Single MOVSD (no REP) — moves exactly one dword
    ; ========================================================================
    cld
    mov     dword [i386str_dst], 0x00000000
    mov     esi, i386str_src
    mov     edi, i386str_dst
    movsd
    ; Verify dword was copied
    mov     eax, [i386str_dst]
    cmp     eax, 0x11223344
    jne     .fail
    ; ESI/EDI advanced by 4
    sub     esi, i386str_src
    cmp     esi, 4
    jne     .fail

    ; All tests passed
    mov     al, STATUS_PASS
    jmp     .done

.fail:
    mov     al, STATUS_FAIL

.done:
    cld                                     ; always clear DF on exit
    pop     ebp
    pop     edi
    pop     esi
    pop     edx
    pop     ecx
    pop     ebx
    ret

;---------------------------------------------------------------------------
i386str_cleanup:
    ret

; --- i386 strings32 data ---
i386str_name: db '80386 32-bit String Ops', 0

align 4
i386str_src:  dd 0x11223344, 0x55667788, 0x99AABBCC, 0xDDEEFF00
i386str_dst:  dd 0, 0, 0, 0
i386str_dst2: dd 0, 0, 0, 0
