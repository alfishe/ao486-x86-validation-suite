;============================================================================
; MODULE: cpu/80386/seg386.asm
; TIER:   UNIVERSAL
; VENUE:  G
; GEN:    80386+
; ORACLE: manual
; DESC:   80386 segment/flag/push extensions:
;         - LFS r32, m48: load far pointer (FS:offset) from 6-byte memory
;         - LGS r32, m48: load far pointer (GS:offset) from 6-byte memory
;         - LSS r32, m48: load far pointer (SS:offset) from 6-byte memory
;         - PUSHFD: push 32-bit EFLAGS
;         - POPFD:  pop 32-bit EFLAGS
;         - PUSH imm32: push 32-bit immediate
;         - PUSHAD/POPAD already tested in new_insns.asm
;
; REFS:   Intel 80386 PRM Ch. 17 (LFS, LGS, LSS, PUSHFD, POPFD)
;============================================================================

;---------------------------------------------------------------------------
i386seg_init:
    ret

;---------------------------------------------------------------------------
; i386seg_run
;---------------------------------------------------------------------------
i386seg_run:
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
    ; TEST 1: PUSHFD/POPFD — 32-bit flag round-trip
    ; Push EFLAGS (32-bit), modify them, then restore from saved copy
    ; ========================================================================
    pushfd
    pop     ecx                             ; ECX = saved EFLAGS
    ; Set CF and OF, then verify POPFD restores
    stc
    pushfd
    pop     edx                             ; EDX = EFLAGS with CF=1
    test    edx, FLAG_CF
    jz      .fail                           ; CF must be 1 after STC

    ; Restore original flags
    push    ecx
    popfd
    ; Verify CF was cleared by the restore (unless it was set originally)
    pushfd
    pop     edx
    mov     eax, ecx
    xor     eax, edx
    test    eax, (FLAG_CF | FLAG_OF | FLAG_ZF | FLAG_SF | FLAG_PF)
    jnz     .fail                           ; arithmetic flags must match

    ; ========================================================================
    ; TEST 2: PUSHFD pushes 4 bytes (32-bit)
    ; ========================================================================
    mov     edx, esp                        ; save SP
    pushfd
    sub     edx, esp                        ; EDX = bytes pushed
    popfd                                   ; restore
    cmp     edx, 4
    jne     .fail

    ; ========================================================================
    ; TEST 3: POPFD can set IF (interrupt flag)
    ; In real mode we can freely set/clear IF via POPFD
    ; ========================================================================
    pushfd
    pop     ecx                             ; save current EFLAGS
    ; Clear IF
    and     ecx, ~FLAG_IF
    push    ecx
    popfd
    pushfd
    pop     edx
    test    edx, FLAG_IF
    jnz     .fail                           ; IF must be 0 now

    ; Set IF back
    or      ecx, FLAG_IF
    push    ecx
    popfd
    pushfd
    pop     edx
    test    edx, FLAG_IF
    jz      .fail                           ; IF must be 1 now

    ; ========================================================================
    ; TEST 4: PUSH imm32 — push 32-bit immediate value
    ; ========================================================================
    mov     edx, esp
    push    dword 0xDEADBEEF
    pop     eax
    cmp     eax, 0xDEADBEEF
    jne     .fail
    cmp     esp, edx                        ; SP must be balanced
    jne     .fail

    ; ========================================================================
    ; TEST 5: PUSH imm8 sign-extended to 16 bits (default operand size in BITS 16)
    ; ========================================================================
    push    byte -1                         ; pushes 0xFFFF (16-bit)
    pop     ax
    cmp     ax, 0xFFFF
    jne     .fail

    push    byte 0x42                       ; positive byte
    pop     ax
    cmp     ax, 0x0042
    jne     .fail

    ; ========================================================================
    ; TEST 6: PUSH imm16 (operand-size prefix in 32-bit push context)
    ; In BITS 16 mode, PUSH imm pushes 16 bits by default.
    ; With operand-size prefix, PUSH imm32.
    ; Default 16-bit push:
    push    word 0x1234
    pop     ax
    cmp     ax, 0x1234
    jne     .fail

    ; ========================================================================
    ; TEST 7: LFS — load far pointer into FS
    ; In real mode, LFS loads offset:EAX and segment:FS from a 6-byte mem.
    ; We set up a fake far pointer: offset=0x1000, seg=0x2000
    ; LFS EAX, [m48] → EAX=offset, FS=segment
    ; ========================================================================
    mov     dword [i386seg_farptr],   0x00001000     ; offset
    mov     word  [i386seg_farptr+4], 0x0000         ; segment (use 0 = current DS)
    push    fs
    lfs     eax, [i386seg_farptr]
    cmp     eax, 0x00001000
    jne     .fail
    mov     ax, fs
    cmp     ax, 0x0000
    jne     .fail
    pop     fs                              ; restore FS

    ; ========================================================================
    ; TEST 8: LGS — load far pointer into GS
    ; ========================================================================
    mov     dword [i386seg_farptr],   0x00002000
    mov     word  [i386seg_farptr+4], 0x0000
    push    gs
    lgs     ebx, [i386seg_farptr]
    cmp     ebx, 0x00002000
    jne     .fail
    mov     ax, gs
    cmp     ax, 0x0000
    jne     .fail
    pop     gs

    ; ========================================================================
    ; TEST 9: LSS — load far pointer into SS
    ; LSS ESP, [m48] changes SS:ESP atomically. We set ESP to point
    ; at the END of a scratch buffer (so push has room), do one push/pop,
    ; then restore original SP.
    ; ========================================================================
    mov     dword [i386seg_farptr],   i386seg_esp_save + 28   ; end of buffer
    mov     ax, ss
    mov     word  [i386seg_farptr+4], ax                  ; segment = current SS
    
    mov     word [i386seg_old_sp], sp
    cli                                     ; disable IRQs during SS change
    lss     esp, [i386seg_farptr]
    ; Now SS:ESP points to end of i386seg_esp_save (same segment)
    push    dword 0xCAFEBABE
    pop     eax
    sti                                     ; re-enable IRQs
    cmp     eax, 0xCAFEBABE
    jne     .fail
    
    ; Restore original SP (SS is same segment)
    mov     sp, word [i386seg_old_sp]
    
    ; ========================================================================
    ; TEST 10: Verify far pointer data layout
    ; ========================================================================
    mov     dword [i386seg_farptr], 0x12345678
    mov     word  [i386seg_farptr+4], 0x9ABC
    mov     eax, dword [i386seg_farptr]
    cmp     eax, 0x12345678
    jne     .fail
    mov     ax, word [i386seg_farptr+4]
    cmp     ax, 0x9ABC
    jne     .fail
    
    ; ========================================================================
    ; TEST 11: Multiple PUSH/POP — stack balance with 32-bit values
    ; ========================================================================
    mov     ecx, esp                        ; save SP
    push    dword 0x11111111
    push    dword 0x22222222
    push    dword 0x33333333
    pop     eax
    cmp     eax, 0x33333333
    jne     .fail
    pop     eax
    cmp     eax, 0x22222222
    jne     .fail
    pop     eax
    cmp     eax, 0x11111111
    jne     .fail
    cmp     esp, ecx                        ; stack must be balanced
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
i386seg_cleanup:
    ret

; --- i386 seg386 data ---
i386seg_name: db '80386 Seg/Push Extensions', 0

align 4
i386seg_farptr:   dd 0, 0                     ; 6-byte far pointer (offset+seg)
i386seg_old_sp:   dw 0                        ; saved SP for LSS test
i386seg_esp_save: dd 0, 0, 0, 0, 0, 0, 0, 0   ; mini stack for LSS test
