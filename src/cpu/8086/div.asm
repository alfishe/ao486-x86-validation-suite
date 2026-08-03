;============================================================================
; MODULE: cpu/8086/div.asm
; TIER:   UNIVERSAL
; VENUE:  G
; GEN:    8086+
; ORACLE: manual
; DESC:   DIV/IDIV/CBW/CWD — unsigned/signed division, sign extension.
;         DIV: divide error (#DE) on divide-by-zero or quotient overflow.
;         IDIV: signed division with sign-extended results.
;         CBW: sign-extend AL → AX. CWD: sign-extend AX → DX:AX.
;         Note: DIV/IDIV leave SF, ZF, AF, PF, OF, CF UNDEFINED.
; REFS:   Intel 8086 Family Users Manual §2.7 (MUL/DIV), §2.8 (CBW/CWD)
;============================================================================

;---------------------------------------------------------------------------
; div_init — Module initialization
;---------------------------------------------------------------------------
div_init:
    ret

;---------------------------------------------------------------------------
; div_run — Execute division test cases
; OUT: AL = STATUS_PASS or STATUS_FAIL
;---------------------------------------------------------------------------
div_run:
    push    bx
    push    cx
    push    dx

    ; ========================================================================
    ; TEST 1: DIV r/m8 — AX / r/m8 → AL=quotient, AH=remainder
    ; 100 / 3: AL=33, AH=1
    ; ========================================================================
    mov     ax, 100
    mov     bl, 3
    div     bl                          ; AX / BL → AL=quotient, AH=remainder
    cmp     al, 33                      ; 100 / 3 = 33
    jne     .fail
    cmp     ah, 1                       ; remainder = 1
    jne     .fail

    ; ========================================================================
    ; TEST 2: DIV r/m16 — DX:AX / r/m16 → AX=quotient, DX=remainder
    ; 0x00010000 / 0x0010 = 0x1000 rem 0
    ; ========================================================================
    mov     dx, 0x0001                  ; DX:AX = 0x00010000 = 65536
    mov     ax, 0x0000
    mov     bx, 0x0010                  ; divisor = 16
    div     bx                          ; 65536 / 16 = 4096 rem 0
    cmp     ax, 0x1000                  ; quotient = 4096
    jne     .fail
    cmp     dx, 0                       ; remainder = 0
    jne     .fail

    ; ========================================================================
    ; TEST 3: DIV exact division — 256 / 4 = 64 rem 0
    ; ========================================================================
    mov     ax, 256
    mov     bl, 4
    div     bl
    cmp     al, 64
    jne     .fail
    cmp     ah, 0
    jne     .fail

    ; ========================================================================
    ; TEST 4: DIV word — simple exact
    ; 0x0000:0x0010 / 0x0004 = 0x0004 rem 0
    ; ========================================================================
    xor     dx, dx
    mov     ax, 0x0010                  ; DX:AX = 16
    mov     bx, 0x0004                  ; divisor = 4
    div     bx
    cmp     ax, 0x0004                  ; 16/4 = 4
    jne     .fail
    cmp     dx, 0
    jne     .fail

    ; ========================================================================
    ; TEST 5: IDIV r/m8 — signed: -100 / 3 = -33 rem -1
    ; ========================================================================
    mov     ax, -100                    ; 0xFF9C
    mov     bl, 3
    idiv    bl                          ; signed divide
    cmp     al, -33                     ; -100 / 3 = -33 (truncated toward zero)
    jne     .fail
    cmp     ah, -1                      ; remainder = -1
    jne     .fail

    ; ========================================================================
    ; TEST 6: IDIV r/m16 — signed: -1024 / 4 = -256 rem 0
    ; ========================================================================
    cwd                                 ; sign-extend AX → DX:AX
    mov     ax, -1024
    cwd                                 ; DX:AX = 0xFFFF:0xFC00 = -1024
    mov     bx, 4
    idiv    bx
    cmp     ax, -256                    ; -1024 / 4 = -256
    jne     .fail
    cmp     dx, 0
    jne     .fail

    ; ========================================================================
    ; TEST 7: IDIV positive result from negatives
    ; -81 / -9 = 9 rem 0
    ; ========================================================================
    mov     ax, -81
    cwd
    mov     bx, -9
    idiv    bx
    cmp     ax, 9
    jne     .fail
    cmp     dx, 0
    jne     .fail

    ; ========================================================================
    ; TEST 8: CBW — sign-extend AL → AX
    ; Positive: AL=0x40 → AX=0x0040
    ; ========================================================================
    mov     al, 0x40                    ; +64
    cbw                                 ; AX = 0x0040
    cmp     ax, 0x0040
    jne     .fail

    ; ========================================================================
    ; TEST 9: CBW — negative AL sign-extends to negative AX
    ; AL=0x80 (-128) → AX=0xFF80 (-128)
    ; ========================================================================
    mov     al, 0x80                    ; -128
    cbw
    cmp     ax, 0xFF80
    jne     .fail

    ; ========================================================================
    ; TEST 10: CBW — AL=0xFF (-1) → AX=0xFFFF (-1)
    ; ========================================================================
    mov     al, 0xFF                    ; -1
    cbw
    cmp     ax, 0xFFFF
    jne     .fail

    ; ========================================================================
    ; TEST 11: CWD — sign-extend AX → DX:AX
    ; AX=0x8000 (-32768) → DX=0xFFFF, AX=0x8000
    ; ========================================================================
    mov     ax, 0x8000                  ; -32768
    cwd                                 ; DX:AX = 0xFFFF:0x8000
    cmp     ax, 0x8000
    jne     .fail
    cmp     dx, 0xFFFF
    jne     .fail

    ; ========================================================================
    ; TEST 12: CWD — positive value, DX=0
    ; AX=0x4000 (+16384) → DX=0x0000
    ; ========================================================================
    mov     ax, 0x4000                  ; +16384
    cwd
    cmp     ax, 0x4000
    jne     .fail
    cmp     dx, 0x0000
    jne     .fail

    ; ========================================================================
    ; TEST 13: DIV remainder edge — 255 / 256 → quotient=0, remainder=255
    ; (Using r/m16 form: DX:AX=0:255 / 256)
    ; ========================================================================
    xor     dx, dx
    mov     ax, 255
    mov     bx, 256
    div     bx                          ; 255 / 256 = 0 rem 255
    cmp     ax, 0
    jne     .fail
    cmp     dx, 255
    jne     .fail

    ; All tests passed
    mov     al, STATUS_PASS
    jmp     .done

.fail:
    mov     al, STATUS_FAIL

.done:
    pop     dx
    pop     cx
    pop     bx
    ret

;---------------------------------------------------------------------------
; div_cleanup — Module cleanup
;---------------------------------------------------------------------------
div_cleanup:
    ret

; --- div data ---
div_name: db '8086 DIV/IDIV/CBW/CWD', 0
