;============================================================================
; MODULE: cpu/80386/new_insns.asm
; TIER:   UNIVERSAL
; VENUE:  G
; GEN:    80386+
; ORACLE: manual
; DESC:   80386 new instructions not present on 80286:
;         - MOVSX/MOVZX: sign/zero-extend r16/r32 from r/m8/r/m16
;         - SETcc: set byte on condition (unsigned + signed variants)
;         - CWDE: sign-extend AX into EAX
;         - CDQ: sign-extend EAX into EDX:EAX
;         - PUSHAD/POPAD: push/pop all 32-bit general registers
;
; REFS:   Intel 80386 Programmer's Reference Manual (PRM) Ch. 17
;============================================================================

;---------------------------------------------------------------------------
i386_init:
    ret

;---------------------------------------------------------------------------
; i386_run
;---------------------------------------------------------------------------
i386_run:
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
    ; TEST 1: MOVZX r16, r/m8 — zero-extend byte to word
    ; AL=0x8F, MOVZX BX, AL -> BX=0x008F
    ; ========================================================================
    mov     al, 0x8F
    movzx   bx, al
    cmp     bx, 0x008F
    jne     .fail

    ; ========================================================================
    ; TEST 2: MOVZX r32, r/m8 — zero-extend byte to dword
    ; AL=0xAB, MOVZX EBX, AL -> EBX=0x000000AB
    ; ========================================================================
    mov     al, 0xAB
    movzx   ebx, al
    cmp     ebx, 0x000000AB
    jne     .fail

    ; ========================================================================
    ; TEST 3: MOVZX r32, r/m16 — zero-extend word to dword
    ; AX=0x1234, MOVZX EBX, AX -> EBX=0x00001234
    ; ========================================================================
    mov     ax, 0x1234
    movzx   ebx, ax
    cmp     ebx, 0x00001234
    jne     .fail

    ; ========================================================================
    ; TEST 4: MOVZX from memory (byte)
    ; ========================================================================
    mov     byte [i386_buf], 0xFF
    movzx   ecx, byte [i386_buf]
    cmp     ecx, 0x000000FF
    jne     .fail

    ; ========================================================================
    ; TEST 5: MOVSX r16, r/m8 — sign-extend byte to word
    ; AL=0x80 (-128), MOVSX BX, AL -> BX=0xFF80
    ; ========================================================================
    mov     al, 0x80
    movsx   bx, al
    cmp     bx, 0xFF80
    jne     .fail

    ; ========================================================================
    ; TEST 6: MOVSX r16, r/m8 — positive byte
    ; AL=0x7F (+127), MOVSX BX, AL -> BX=0x007F
    ; ========================================================================
    mov     al, 0x7F
    movsx   bx, al
    cmp     bx, 0x007F
    jne     .fail

    ; ========================================================================
    ; TEST 7: MOVSX r32, r/m8 — sign-extend byte to dword
    ; AL=0xFE (-2), MOVSX EBX, AL -> EBX=0xFFFFFFFE
    ; ========================================================================
    mov     al, 0xFE
    movsx   ebx, al
    cmp     ebx, 0xFFFFFFFE
    jne     .fail

    ; ========================================================================
    ; TEST 8: MOVSX r32, r/m16 — sign-extend word to dword
    ; AX=0x8000 (-32768), MOVSX EBX, AX -> EBX=0xFFFF8000
    ; ========================================================================
    mov     ax, 0x8000
    movsx   ebx, ax
    cmp     ebx, 0xFFFF8000
    jne     .fail

    ; ========================================================================
    ; TEST 9: MOVSX r32, r/m16 — positive word
    ; AX=0x7FFF (+32767), MOVSX EBX, AX -> EBX=0x00007FFF
    ; ========================================================================
    mov     ax, 0x7FFF
    movsx   ebx, ax
    cmp     ebx, 0x00007FFF
    jne     .fail

    ; ========================================================================
    ; TEST 10: MOVSX from memory (word, negative)
    ; ========================================================================
    mov     word [i386_buf], 0xF000
    movsx   ecx, word [i386_buf]
    cmp     ecx, 0xFFFFF000
    jne     .fail

    ; ========================================================================
    ; TEST 11: SETZ/SETE — set byte to 1 if ZF=1
    ; ========================================================================
    xor     ax, ax                      ; ZF=1
    setz    al
    cmp     al, 1
    jne     .fail

    or      ax, -1                      ; AX nonzero, ZF=0 (MOV does NOT set flags)
    setz    al
    cmp     al, 0
    jne     .fail

    ; ========================================================================
    ; TEST 12: SETNZ/SETNE — set byte to 1 if ZF=0
    ; ========================================================================
    or      ax, -1                      ; ZF=0
    setnz   al
    cmp     al, 1
    jne     .fail

    xor     ax, ax                      ; ZF=1
    setnz   al
    cmp     al, 0
    jne     .fail

    ; ========================================================================
    ; TEST 13: SETC — set byte to 1 if CF=1
    ; ========================================================================
    stc
    setc    al
    cmp     al, 1
    jne     .fail

    clc
    setc    al
    cmp     al, 0
    jne     .fail

    ; ========================================================================
    ; TEST 14: SETNC — set byte to 1 if CF=0
    ; ========================================================================
    clc
    setnc   al
    cmp     al, 1
    jne     .fail

    stc
    setnc   al
    cmp     al, 0
    jne     .fail

    ; ========================================================================
    ; TEST 15: SETS / SETNS — sign flag
    ; ========================================================================
    mov     ax, -1
    or      ax, ax                      ; SF=1 (AX is negative)
    sets    bl
    cmp     bl, 1
    jne     .fail

    mov     ax, 1
    or      ax, ax                      ; SF=0 (AX is positive)
    setns   bl
    cmp     bl, 1
    jne     .fail

    ; ========================================================================
    ; TEST 16: SETL / SETGE — signed less / greater-or-equal
    ; Ref: SETL is true when SF != OF
    ; ========================================================================
    ; Compare -1 < 1 (signed)
    mov     ax, -1
    cmp     ax, 1                       ; -1 < 1 → SF != OF
    setl    cl                          ; should be 1
    cmp     cl, 1
    jne     .fail

    ; Compare 1 >= -1 (signed)
    mov     ax, 1
    cmp     ax, -1                      ; 1 >= -1 → SF = OF
    setl    cl                          ; should be 0
    cmp     cl, 0
    jne     .fail

    ; SETGE — greater or equal
    mov     ax, 5
    cmp     ax, 5                       ; equal → SF = OF → SETGE = 1
    setge   cl
    cmp     cl, 1
    jne     .fail

    ; ========================================================================
    ; TEST 17: SETG / SETLE — signed greater / less-or-equal
    ; SETG: ZF=0 AND SF=OF
    ; SETLE: ZF=1 OR SF!=OF
    ; ========================================================================
    mov     ax, 10
    cmp     ax, 5                       ; 10 > 5 → SETG = 1
    setg    dl
    cmp     dl, 1
    jne     .fail

    mov     ax, 5
    cmp     ax, 10                      ; 5 < 10 → SETG = 0
    setg    dl
    cmp     dl, 0
    jne     .fail

    mov     ax, 5
    cmp     ax, 10                      ; 5 <= 10 → SETLE = 1
    setle   dl
    cmp     dl, 1
    jne     .fail

    mov     ax, 10
    cmp     ax, 5                       ; 10 > 5 → SETLE = 0
    setle   dl
    cmp     dl, 0
    jne     .fail

    ; ========================================================================
    ; TEST 18: SETA / SETBE — unsigned above / below-or-equal
    ; SETA: CF=0 AND ZF=0
    ; SETBE: CF=1 OR ZF=1
    ; ========================================================================
    mov     ax, 10
    cmp     ax, 5                       ; 10 > 5 unsigned → SETA = 1
    seta    bl
    cmp     bl, 1
    jne     .fail

    mov     ax, 5
    cmp     ax, 10                      ; 5 < 10 unsigned → SETA = 0
    seta    bl
    cmp     bl, 0
    jne     .fail

    mov     ax, 5
    cmp     ax, 10                      ; 5 <= 10 → SETBE = 1
    setbe   bl
    cmp     bl, 1
    jne     .fail

    mov     ax, 10
    cmp     ax, 5                       ; 10 > 5 → SETBE = 0
    setbe   bl
    cmp     bl, 0
    jne     .fail

    ; ========================================================================
    ; TEST 19: SETcc to memory
    ; ========================================================================
    xor     ax, ax                      ; ZF=1
    sete    byte [i386_buf]
    cmp     byte [i386_buf], 1
    jne     .fail

    ; ========================================================================
    ; TEST 20: CWDE — sign-extend AX into EAX
    ; AX=0x1234 -> EAX=0x00001234
    ; AX=0x8000 -> EAX=0xFFFF8000
    ; ========================================================================
    mov     ax, 0x1234
    cwde
    cmp     eax, 0x00001234
    jne     .fail

    mov     ax, 0x8000
    cwde
    cmp     eax, 0xFFFF8000
    jne     .fail

    ; ========================================================================
    ; TEST 21: CDQ — sign-extend EAX into EDX:EAX
    ; EAX=positive -> EDX=0
    ; EAX=negative -> EDX=0xFFFFFFFF
    ; ========================================================================
    mov     eax, 0x00010000
    cdq
    cmp     edx, 0x00000000
    jne     .fail

    mov     eax, 0xFFFFFFFF            ; -1
    cdq
    cmp     edx, 0xFFFFFFFF
    jne     .fail

    mov     eax, 0x80000000            ; most negative 32-bit
    cdq
    cmp     edx, 0xFFFFFFFF
    jne     .fail

    ; ========================================================================
    ; TEST 22: PUSHAD/POPAD — push/pop all 32-bit GPRs
    ; PUSHAD pushes: EAX, ECX, EDX, EBX, orig_ESP, EBP, ESI, EDI
    ; POPOD pops in reverse (EDI, ESI, EBP, skip ESP, EBX, EDX, ECX, EAX)
    ; ========================================================================
    mov     eax, 0x11111111
    mov     ecx, 0x22222222
    mov     edx, 0x33333333
    mov     ebx, 0x44444444
    mov     ebp, 0x55555555
    mov     esi, 0x66666666
    mov     edi, 0x77777777
    pushad
    ; Clobber everything
    mov     eax, 0
    mov     ecx, 0
    mov     edx, 0
    mov     ebx, 0
    mov     ebp, 0
    mov     esi, 0
    mov     edi, 0
    popad
    ; Verify all restored (ESP is NOT restored by POPAD — it's skipped)
    cmp     eax, 0x11111111
    jne     .fail
    cmp     ecx, 0x22222222
    jne     .fail
    cmp     edx, 0x33333333
    jne     .fail
    cmp     ebx, 0x44444444
    jne     .fail
    cmp     ebp, 0x55555555
    jne     .fail
    cmp     esi, 0x66666666
    jne     .fail
    cmp     edi, 0x77777777
    jne     .fail

    ; ========================================================================
    ; TEST 23: PUSHAD/POPAD — stack balance (SP unchanged)
    ; ========================================================================
    mov     [i386_sp_save], sp
    pushad
    popad
    mov     ax, sp
    cmp     ax, [i386_sp_save]
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
i386_cleanup:
    ret

; --- i386 new_insns data ---
i386_name: db '80386 New Instructions', 0

i386_buf:     dd 0
i386_sp_save: dw 0
