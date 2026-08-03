;============================================================================
; MODULE: cpu/80286/real.asm
; TIER:   REALMODE
; VENUE:  G
; GEN:    80286+
; ORACLE: manual
; DESC:   80286-specific behaviors visible in real mode.
;         - SMSW: read Machine Status Word (CR0 low 16 bits), PE=0 in RM
;         - SGDT/SIDT: store GDT/IDT register contents to memory
;         - Shift count masking: 286 masks to 5 bits (same as 186)
;         - PUSH SP: 286 pushes pre-decrement SP (unlike 8086)
;         - Flags: NT bit exists but is read-only in real mode on 286
; REFS:   Intel iAPX 286 Programmer's Reference Manual;
;         §2.3 System Registers (MSW), §2.4 Table Registers
; DIVERGE: 8086 has no SMSW/SGDT/SIDT — #UD on that hardware
;============================================================================

;---------------------------------------------------------------------------
; real286_init — Module initialization
;---------------------------------------------------------------------------
real286_init:
    ret

;---------------------------------------------------------------------------
; real286_run — Execute 80286 real-mode tests
; OUT: AL = STATUS_PASS or STATUS_FAIL / STATUS_SKIP
;---------------------------------------------------------------------------
real286_run:
    push    bx
    push    cx
    push    dx
    push    si

    ; ========================================================================
    ; Capability gate: 80286+ required
    ; ========================================================================
    mov     al, [g_cpu_type]
    cmp     al, CPU_80286
    jae     .cap_ok
    mov     al, STATUS_SKIP
    jmp     .done
.cap_ok:

    ; ========================================================================
    ; TEST 1: SMSW — Machine Status Word readable, PE bit = 0 in real mode
    ; On 286+, SMSW returns CR0[15:0]. In real mode, PE (bit 0) = 0.
    ; ========================================================================
    smsw    ax                          ; AX = MSW
    test    ax, 1                       ; PE bit must be 0 in real mode
    jnz     .fail

    ; ========================================================================
    ; TEST 2: SMSW — ET bit (bit 4) indicates FPU type on 386+, always 0 on 286
    ; On 286 the MSW only has PE, MP, EM, TS bits. ET doesn't exist.
    ; We test that TS (bit 3) is initially clear.
    ; ========================================================================
    smsw    ax
    test    ax, 0x0008                  ; TS bit
    jnz     .fail                       ; TS should be 0 at startup

    ; ========================================================================
    ; TEST 3: SGDT — store GDT register to memory
    ; Format: [offset+0] = 16-bit limit, [offset+2] = 24/32-bit base
    ; In real mode, the GDT limit is typically 0x0000 and base is ~0.
    ; We verify the structure is readable without faulting.
    ; ========================================================================
    sgdt    [rm286_buf]                 ; store GDT register
    ; Limit is at offset 0, base at offset 2
    ; Just verify it doesn't crash and we can read the limit
    mov     ax, [rm286_buf]             ; limit (low 16 bits)
    ; In DOS real mode, BIOS sets up a GDT; just verify it's readable
    ; No specific value assertion — just that SGDT works

    ; ========================================================================
    ; TEST 4: SIDT — store IDT register to memory
    ; In real mode, IDT base is typically 0x00000000 and limit 0x03FF
    ; (256 interrupt vectors × 4 bytes each on 8086/286 RM)
    ; On 286 RM: IDT entries are 4 bytes, limit = 0x03FF
    ; ========================================================================
    sidt    [rm286_buf]
    mov     ax, [rm286_buf]             ; IDT limit
    cmp     ax, 0x03FF                  ; standard real-mode IDT limit
    je      .t4_ok
    ; Some BIOSes may use a different limit; just verify it's non-zero
    test    ax, ax
    jz      .fail
.t4_ok:

    ; ========================================================================
    ; TEST 5: SIDT — base address in low 1MB (real mode)
    ; The IDT base should be in the first 1MB (0x00000-0xFFFFF)
    ; ========================================================================
    sidt    [rm286_buf]
    mov     ax, [rm286_buf + 2]         ; base low word
    mov     dx, [rm286_buf + 4]         ; base high word (bits 16-31)
    ; On 286, only 24 address bits, so bits 24-31 are reserved/0
    ; Just check the high byte of the 32-bit base is zero (286 has 24-bit addr)
    ; For 386+ in real mode, high byte could be anything but typically 0
    test    dx, 0xFF00                  ; bits 24-31 should be 0 on 286
    jnz     .fail_t5                    ; might be nonzero on 386+, that's ok
    jmp     .t5_ok
.fail_t5:
    ; On 386+ the full 32-bit base may have high bits. Accept if below 1MB.
    cmp     dx, 0x0010                  ; base < 0x100000 (1MB)
    ja      .fail
.t5_ok:

    ; ========================================================================
    ; TEST 6: PUSH SP behavior — 286 pushes value of SP BEFORE decrement
    ; (8086 pushes SP after decrement, 186 same as 8086)
    ; Already tested in detect_cpu, but we assert it explicitly here.
    ; ========================================================================
    mov     bx, sp
    push    sp
    pop     ax
    cmp     ax, bx                      ; on 286+, AX should equal original SP
    jne     .fail

    ; ========================================================================
    ; TEST 7: Shift count masking — 286 masks to 5 bits (mod 32)
    ; CL=32 → effective count = 0 → no-op
    ; ========================================================================
    stc                                 ; set CF=1
    mov     ax, 0x1234
    mov     cl, 32                      ; 32 mod 32 = 0 → no-op on 286+
    shl     ax, cl
    pushf
    pop     cx
    cmp     ax, 0x1234                  ; result unchanged
    jne     .fail
    test    cx, FLAG_CF                 ; CF must still be 1 (no-op)
    jz      .fail

    ; ========================================================================
    ; TEST 8: IOPL bits are writable in real mode on 286+ via POPF
    ; In real mode, IOPL can be modified (no protection in RM)
    ; ========================================================================
    pushf
    pop     ax                          ; get current flags
    or      ax, 0x3000                  ; set IOPL = 3
    push    ax
    popf                                ; attempt to set IOPL
    pushf
    pop     ax                          ; read back
    test    ax, 0x3000                  ; IOPL should be 3
    jz      .fail                       ; if IOPL stayed 0, this is 8086 behavior
    ; Restore IOPL to 0 for safety
    pushf
    pop     ax
    and     ax, 0x0FFF                  ; clear IOPL
    push    ax
    popf

    ; ========================================================================
    ; TEST 9: NT flag (bit 14) — can be set/cleared in real mode on 386+
    ; On 286: NT exists but may not be modifiable via POPF in real mode
    ; We just verify NT is initially clear (no nested task active)
    ; ========================================================================
    pushf
    pop     ax
    test    ax, 0x4000                  ; NT bit
    jnz     .fail                       ; NT should be 0 at startup

    ; All tests passed
    mov     al, STATUS_PASS
    jmp     .done

.fail:
    mov     al, STATUS_FAIL
    jmp     .done

.done:
    pop     si
    pop     dx
    pop     cx
    pop     bx
    ret

;---------------------------------------------------------------------------
; real286_cleanup — Module cleanup
;---------------------------------------------------------------------------
real286_cleanup:
    ret

; --- real286 data ---
real286_name: db '80286 Real-Mode Behaviors', 0
rm286_buf:    dw 0, 0, 0               ; 6-byte buffer for SGDT/SIDT
