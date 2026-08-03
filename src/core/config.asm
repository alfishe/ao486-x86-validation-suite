;============================================================================
; MODULE: core/config.asm
; DESC:   Command-line parser for the validation suite
;         Reads PSP command line and sets global options.
;
; Supported flags:
;   /serial        Enable COM1 serial output (115200 8N1)
;   /log           Enable file output to X86VAL.LOG
;   /v:0..3        Set verbosity level (0=silent, 1=normal, 2=verbose, 3=debug)
;============================================================================

;---------------------------------------------------------------------------
; config_parse — Parse DOS command line from PSP
; Modifies: g_output_flags, g_verbose, g_log_handle
;---------------------------------------------------------------------------
config_parse:
    push    ax
    push    si
    push    cx
    push    dx

    mov     cl, [0x80]                  ; command line length byte
    test    cl, cl
    jz      .done
    xor     ch, ch                      ; CX = total length
    mov     si, 0x81                    ; command line text

.loop:
    jcxz   .done
    cmp     byte [si], '/'
    jne     .next
    inc     si                          ; skip '/'
    dec     cx
    jcxz   .done
    mov     al, [si]
    or      al, 0x20                    ; to lowercase
    cmp     al, 's'
    je      .serial
    cmp     al, 'l'
    je      .log
    cmp     al, 'v'
    je      .verbose
    cmp     al, '?'
    je      .help
    jmp     .next                       ; unknown flag char

.serial:
    or      byte [g_output_flags], OUT_SERIAL
    call    dos_ser_init
    jmp     .next

.log:
    or      byte [g_output_flags], OUT_FILE
    mov     dx, cfg_default_log
    call    dos_file_open
    jmp     .next

.verbose:
    ; Expect /v:N
    cmp     cx, 2
    jb      .next
    cmp     byte [si+1], ':'
    jne     .next
    mov     al, [si+2]
    sub     al, '0'
    jb      .next
    cmp     al, 3
    ja      .next
    mov     [g_verbose], al
    add     si, 2
    sub     cx, 2
    jmp     .next

.help:
    mov     byte [g_show_help], 1
    jmp     .next

.next:
    inc     si
    dec     cx
    jmp     .loop

.done:
    pop     dx
    pop     cx
    pop     si
    pop     ax
    ret

; --- config data ---
cfg_default_log: db 'X86VAL.LOG', 0
g_show_help:     db 0
