;============================================================================
; MODULE: cpu/8086/string.asm
; TIER:   UNIVERSAL
; VENUE:  G
; GEN:    8086+
; ORACLE: manual
; DESC:   MOVS/STOS/CMPS/SCAS with REP prefix and DF (direction flag) control.
;         Tests forward/backward, repeat counts, and DF save/restore.
;         CRITICAL: every test must save/restore DF (cld before exit).
; REFS:   Intel 8086 Family Users Manual §2.5 (string instructions)
;============================================================================

;---------------------------------------------------------------------------
; string_init — Module initialization
;---------------------------------------------------------------------------
string_init:
    ret

;---------------------------------------------------------------------------
; string_run — Execute string operation test cases
; OUT: AL = STATUS_PASS or STATUS_FAIL
;---------------------------------------------------------------------------
string_run:
    push    bx
    push    cx
    push    dx
    push    si
    push    di
    push    es

    ; ES = DS for all string ops (flat .COM model)
    push    ds
    pop     es

    ; ========================================================================
    ; TEST 1: REP MOVSB forward (DF=0)
    ; Copy 8 bytes from src to dst, verify match
    ; ========================================================================
    cld
    lea     si, [str_src]
    lea     di, [str_dst]
    mov     cx, 8
    rep     movsb
    ; Verify
    lea     si, [str_src]
    lea     di, [str_dst]
    mov     cx, 8
    repe    cmpsb
    jne     .fail

    ; ========================================================================
    ; TEST 2: REP MOVSW forward (word copies)
    ; ========================================================================
    cld
    lea     si, [str_src]
    lea     di, [str_dst]
    mov     cx, 4                       ; 4 words = 8 bytes
    rep     movsw
    lea     si, [str_src]
    lea     di, [str_dst]
    mov     cx, 8
    repe    cmpsb
    jne     .fail

    ; ========================================================================
    ; TEST 3: REP STOSB — fill buffer with byte
    ; ========================================================================
    cld
    lea     di, [str_dst]
    mov     al, 0xAA
    mov     cx, 8
    rep     stosb
    ; Verify all bytes = 0xAA
    lea     di, [str_dst]
    mov     cx, 8
    mov     al, 0xAA
    repe    scasb
    jne     .fail                       ; found a non-0xAA byte

    ; ========================================================================
    ; TEST 4: REP STOSW — fill buffer with word
    ; ========================================================================
    cld
    lea     di, [str_dst]
    mov     ax, 0xBEEF
    mov     cx, 4                       ; 4 words
    rep     stosw
    lea     di, [str_dst]
    mov     ax, 0xBEEF
    mov     cx, 4
    repe    scasw
    jne     .fail

    ; ========================================================================
    ; TEST 5: CMPSB — byte compare, find difference
    ; str_src and str_diff differ at byte 3
    ; ========================================================================
    cld
    lea     si, [str_src]
    lea     di, [str_diff]
    mov     cx, 8
    repe    cmpsb                       ; stop at first difference
    ; CX should be less than 8 (difference found)
    cmp     cx, 8
    jae     .fail                       ; no difference found = fail
    ; SI/DI should point PAST the differing byte
    mov     bx, si
    sub     bx, str_src
    cmp     bx, 4                       ; should be at offset 4 (byte 3 + 1)
    jne     .fail

    ; ========================================================================
    ; TEST 6: SCASB — scan for matching byte
    ; Find 0x44 in str_src: 11 22 33 44 55 66 77 88
    ; ========================================================================
    cld
    lea     di, [str_src]
    mov     al, 0x44
    mov     cx, 8
    repne   scasb                       ; scan until match
    jcxz    .fail                       ; CX=0 means not found
    ; DI should point past the 0x44 byte (offset 4)
    mov     bx, di
    sub     bx, str_src
    cmp     bx, 4
    jne     .fail

    ; ========================================================================
    ; TEST 7: REP MOVSB backward (DF=1) — copy in reverse
    ; Start SI/DI at END of buffers, copy backward
    ; ========================================================================
    std
    lea     si, [str_src + 7]           ; last byte of source
    lea     di, [str_dst + 7]           ; last byte of dst
    mov     cx, 8
    rep     movsb
    cld                                 ; CRITICAL: restore DF=0
    ; Verify
    lea     si, [str_src]
    lea     di, [str_dst]
    mov     cx, 8
    repe    cmpsb
    jne     .fail

    ; ========================================================================
    ; TEST 8: LODSB/STOSB combo — byte copy with AL intermediate
    ; ========================================================================
    cld
    lea     si, [str_src]
    lea     di, [str_dst]
    mov     cx, 8
.t8_loop:
    lodsb                               ; AL = [SI++]
    stosb                               ; [DI++] = AL
    loop    .t8_loop
    lea     si, [str_src]
    lea     di, [str_dst]
    mov     cx, 8
    repe    cmpsb
    jne     .fail

    ; ========================================================================
    ; TEST 9: REPNE SCASW — scan for word value
    ; Find 0x4433 in str_src (bytes: 11 22 33 44 → words: 2211 4433)
    ; ========================================================================
    cld
    lea     di, [str_src]
    mov     ax, 0x4433
    mov     cx, 4
    repne   scasw
    jcxz    .fail

    ; ========================================================================
    ; TEST 10: CX=0 means no operation for REP
    ; REP with CX=0 should not execute even once
    ; ========================================================================
    cld
    lea     di, [str_dst]
    mov     byte [str_dst], 0x00
    mov     al, 0xFF
    mov     cx, 0
    rep     stosb                       ; should do nothing
    cmp     byte [str_dst], 0x00        ; still 0x00
    jne     .fail

    ; Ensure DF is clear on exit
    cld

    ; All tests passed
    mov     al, STATUS_PASS
    jmp     .done

.fail:
    cld                                 ; always restore DF
    mov     al, STATUS_FAIL

.done:
    pop     es
    pop     di
    pop     si
    pop     dx
    pop     cx
    pop     bx
    ret

;---------------------------------------------------------------------------
; string_cleanup — Module cleanup
;---------------------------------------------------------------------------
string_cleanup:
    ret

; --- string data ---
string_name: db '8086 String Ops', 0

str_src:  db 0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77, 0x88
str_diff: db 0x11, 0x22, 0x33, 0x99, 0x55, 0x66, 0x77, 0x88
str_dst:  db 0, 0, 0, 0, 0, 0, 0, 0
