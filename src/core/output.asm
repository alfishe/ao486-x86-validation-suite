;============================================================================
; MODULE: core/output.asm
; DESC:   Output abstraction — routes text to console, serial, and/or file
;         Sits on top of dosio.asm primitives.
;         Output flags control which channels are active:
;           bit 0 = console   (on by default)
;           bit 1 = serial     (off by default)
;           bit 2 = file       (off by default)
;============================================================================

OUT_CONSOLE  equ 0x01
OUT_SERIAL   equ 0x02
OUT_FILE     equ 0x04

;---------------------------------------------------------------------------
; output_init — Initialize output system
; Console is always enabled; serial and file are enabled by config_parse.
;---------------------------------------------------------------------------
output_init:
    mov     byte [g_output_flags], OUT_CONSOLE
    mov     byte [g_verbose], 1
    ret

;---------------------------------------------------------------------------
; output_putc — Send one character to all enabled outputs
; IN: AL = character
; Preserves all registers.
;---------------------------------------------------------------------------
output_putc:
    push    ax
    test    byte [g_output_flags], OUT_CONSOLE
    jz      .check_serial
    call    dos_con_putc
.check_serial:
    test    byte [g_output_flags], OUT_SERIAL
    jz      .check_file
    call    dos_ser_putc
.check_file:
    test    byte [g_output_flags], OUT_FILE
    jz      .done
    call    dos_file_putc
.done:
    pop     ax
    ret

;---------------------------------------------------------------------------
; output_puts — Send null-terminated string to all enabled outputs
; IN: SI = pointer to null-terminated string
; Preserves all registers.
;---------------------------------------------------------------------------
output_puts:
    push    ax
    push    si
.loop:
    lodsb                               ; AL = [SI++]
    test    al, al
    jz      .done
    call    output_putc
    jmp     .loop
.done:
    pop     si
    pop     ax
    ret

;---------------------------------------------------------------------------
; output_hex8 — Print AL as two uppercase hex digits
; IN: AL = byte to print
;---------------------------------------------------------------------------
output_hex8:
    push    ax
    mov     ah, al
    shr     al, 4                       ; high nibble
    call    .nibble
    mov     al, ah
    and     al, 0x0F                    ; low nibble
    call    .nibble
    pop     ax
    ret
.nibble:
    cmp     al, 10
    jb      .digit
    add     al, 'A' - 10
    jmp     .emit
.digit:
    add     al, '0'
.emit:
    call    output_putc
    ret

;---------------------------------------------------------------------------
; output_hex16 — Print AX as four uppercase hex digits
; IN: AX = word to print
;---------------------------------------------------------------------------
output_hex16:
    push    ax
    xchg    al, ah                      ; print high byte first
    call    output_hex8
    xchg    al, ah
    call    output_hex8
    pop     ax
    ret

;---------------------------------------------------------------------------
; output_newline — Print CR LF to all outputs
;---------------------------------------------------------------------------
output_newline:
    push    ax
    mov     al, 0x0D
    call    output_putc
    mov     al, 0x0A
    call    output_putc
    pop     ax
    ret

;---------------------------------------------------------------------------
; output_dec16 — Print AX as unsigned decimal
; IN: AX = value (0..65535)
;---------------------------------------------------------------------------
output_dec16:
    push    ax
    push    bx
    push    cx
    push    dx
    mov     bx, 10
    xor     cx, cx
    test    ax, ax
    jnz     .convert
    mov     al, '0'
    call    output_putc
    jmp     .done
.convert:
    xor     dx, dx
    div     bx                         ; AX=quotient, DX=remainder
    push    dx                         ; save digit
    inc     cx
    test    ax, ax
    jnz     .convert
.print:
    pop     dx
    mov     al, dl
    add     al, '0'
    call    output_putc
    loop    .print
.done:
    pop     dx
    pop     cx
    pop     bx
    pop     ax
    ret

;---------------------------------------------------------------------------
; output_flush — Flush any pending output (DOS writes are synchronous)
;---------------------------------------------------------------------------
output_flush:
    ret

; --- output data ---
g_output_flags: db OUT_CONSOLE          ; active output channel flags
g_verbose:      db 1                    ; verbosity level (0-3)
g_log_handle:   dw 0                    ; file handle for log output
