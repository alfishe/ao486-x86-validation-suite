;============================================================================
; MODULE: arch/dos/dosio.asm
; DESC:   Low-level DOS I/O primitives — console, serial, file
;         This file is textually %included into main.asm (flat .COM binary).
;         All functions preserve ALL registers unless documented otherwise.
;============================================================================

;---------------------------------------------------------------------------
; dos_con_putc — Print one character to console (stdout handle)
; IN:  AL = character
;---------------------------------------------------------------------------
dos_con_putc:
    push    ax
    push    bx
    push    cx
    push    dx
    mov     [dosio_tx_buf], al
    mov     ah, DOS_WRITE
    mov     bx, DOS_STDOUT
    mov     cx, 1
    mov     dx, dosio_tx_buf
    int     0x21
    pop     dx
    pop     cx
    pop     bx
    pop     ax
    ret

;---------------------------------------------------------------------------
; dos_con_write — Write buffer to console
; IN:  DS:DX = buffer, CX = byte count
;---------------------------------------------------------------------------
dos_con_write:
    push    ax
    push    bx
    mov     ah, DOS_WRITE
    mov     bx, DOS_STDOUT
    int     0x21
    pop     bx
    pop     ax
    ret

;---------------------------------------------------------------------------
; dos_ser_init — Initialize COM1 serial port
;       115200 baud, 8 data bits, no parity, 1 stop bit (8N1)
; IN:  none
;---------------------------------------------------------------------------
dos_ser_init:
    push    ax
    push    dx
    ; Disable all COM1 interrupts
    mov     dx, COM1_BASE + COM_IER
    xor     al, al
    out     dx, al
    ; Enable DLAB to set baud rate
    mov     dx, COM1_BASE + COM_LCR
    mov     al, 0x80
    out     dx, al
    ; Divisor = 1 -> 115200 baud
    mov     dx, COM1_BASE + 0          ; DLL
    mov     al, 0x01
    out     dx, al
    mov     dx, COM1_BASE + 1          ; DLH
    xor     al, al
    out     dx, al
    ; 8N1, clear DLAB
    mov     dx, COM1_BASE + COM_LCR
    mov     al, 0x03
    out     dx, al
    ; Enable + clear FIFOs, 14-byte trigger
    mov     dx, COM1_BASE + COM_IIR
    mov     al, 0xC7
    out     dx, al
    ; DTR=1, RTS=1, OUT2=1 (needed for IRQ and some emulators)
    mov     dx, COM1_BASE + COM_MCR
    mov     al, 0x0B
    out     dx, al
    pop     dx
    pop     ax
    ret

;---------------------------------------------------------------------------
; dos_ser_putc — Print one character to COM1
; IN:  AL = character
; Bounded: 65535-iteration timeout; returns silently if UART never empties.
;---------------------------------------------------------------------------
dos_ser_putc:
    push    ax
    push    cx
    push    dx
    mov     ah, al                      ; save char in AH
    mov     dx, COM1_BASE + COM_LSR
    mov     cx, 0xFFFF                  ; timeout loop count
.wait:
    in      al, dx
    test    al, LSR_THRE                ; TX holding register empty?
    jnz     .ready
    loop    .wait
    jmp     .timeout                    ; give up — avoid hang
.ready:
    mov     dx, COM1_BASE               ; THR (transmit holding register)
    mov     al, ah                      ; restore char
    out     dx, al
.timeout:
    pop     dx
    pop     cx
    pop     ax
    ret

;---------------------------------------------------------------------------
; dos_file_open — Create or truncate file for writing
; IN:  DS:DX = ASCIIZ filename
; OUT: AX = file handle (success) or 0 (error)
;      [g_log_handle] updated on success
; Clobbers: AX, FLAGS
;---------------------------------------------------------------------------
dos_file_open:
    push    bx
    push    cx
    mov     ah, DOS_CREATE
    xor     cx, cx                      ; normal attribute
    int     0x21
    jc      .error
    mov     [g_log_handle], ax          ; save handle
    pop     cx
    pop     bx
    ret
.error:
    xor     ax, ax                      ; return 0 on error
    pop     cx
    pop     bx
    ret

;---------------------------------------------------------------------------
; dos_file_putc — Print one character to log file
; IN:  AL = character
; Uses [g_log_handle]; silently no-ops if handle is 0.
;---------------------------------------------------------------------------
dos_file_putc:
    push    ax
    push    bx
    push    cx
    push    dx
    mov     bx, [g_log_handle]
    test    bx, bx
    jz      .done                       ; no file open
    mov     [dosio_tx_buf], al
    mov     ah, DOS_WRITE
    mov     cx, 1
    mov     dx, dosio_tx_buf
    int     0x21
.done:
    pop     dx
    pop     cx
    pop     bx
    pop     ax
    ret

;---------------------------------------------------------------------------
; dos_file_close — Close the log file
;---------------------------------------------------------------------------
dos_file_close:
    push    ax
    push    bx
    mov     bx, [g_log_handle]
    test    bx, bx
    jz      .done
    mov     ah, DOS_CLOSE
    int     0x21
    xor     ax, ax
    mov     [g_log_handle], ax
.done:
    pop     bx
    pop     ax
    ret

; --- dosio data ---
dosio_tx_buf:    db 0                    ; single-byte scratch for putc functions
