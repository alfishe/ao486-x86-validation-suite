; POC-01 Scenario 1: Push Mode
; Runs diagnostic tests and pushes results to COM1
; Assemble: nasm -f bin -o push.com push.asm

org 100h

COM1_BASE   equ 0x3F8
COM1_THR    equ COM1_BASE + 0   ; Transmit Holding Register
COM1_RBR    equ COM1_BASE + 0   ; Receive Buffer Register
COM1_DLL    equ COM1_BASE + 0   ; Divisor Latch Low (DLAB=1)
COM1_DLH    equ COM1_BASE + 1   ; Divisor Latch High (DLAB=1)
COM1_IER    equ COM1_BASE + 1   ; Interrupt Enable Register
COM1_LCR    equ COM1_BASE + 3   ; Line Control Register
COM1_MCR    equ COM1_BASE + 4   ; Modem Control Register
COM1_LSR    equ COM1_BASE + 5   ; Line Status Register

BAUD_115200 equ 1               ; Divisor for 115200 baud

section .text

start:
    ; Initialize COM1: 115200 8N1
    call uart_init

    ; Send banner
    mov si, msg_banner
    call uart_puts

    ; Run tests
    call test_cpu_detect
    call test_add_flags
    call test_sub_flags
    call test_inc_cf

    ; Send completion marker
    mov si, msg_complete
    call uart_puts

    ; Exit to DOS
    mov ax, 0x4C00
    int 0x21

;----------------------------------------
; UART routines
;----------------------------------------

uart_init:
    ; Set DLAB to access divisor
    mov dx, COM1_LCR
    mov al, 0x80
    out dx, al

    ; Set baud rate divisor (115200)
    mov dx, COM1_DLL
    mov al, BAUD_115200
    out dx, al
    mov dx, COM1_DLH
    xor al, al
    out dx, al

    ; 8 bits, no parity, 1 stop bit (8N1), clear DLAB
    mov dx, COM1_LCR
    mov al, 0x03
    out dx, al

    ; Enable DTR, RTS
    mov dx, COM1_MCR
    mov al, 0x03
    out dx, al

    ; Disable interrupts
    mov dx, COM1_IER
    xor al, al
    out dx, al

    ret

; Send character in AL
uart_putc:
    push ax
    push dx
    mov ah, al          ; Save char

.wait_ready:
    mov dx, COM1_LSR
    in al, dx
    test al, 0x20       ; THR empty?
    jz .wait_ready

    mov dx, COM1_THR
    mov al, ah
    out dx, al

    pop dx
    pop ax
    ret

; Send null-terminated string at SI
uart_puts:
    push ax
    push si
.loop:
    lodsb
    test al, al
    jz .done
    call uart_putc
    jmp .loop
.done:
    pop si
    pop ax
    ret

; Send hex byte in AL
uart_hex8:
    push ax
    push cx
    mov cl, al

    ; High nibble
    shr al, 4
    call .nibble

    ; Low nibble
    mov al, cl
    and al, 0x0F
    call .nibble

    pop cx
    pop ax
    ret

.nibble:
    cmp al, 10
    jb .digit
    add al, 'A' - 10
    jmp uart_putc
.digit:
    add al, '0'
    jmp uart_putc

; Send hex word in AX
uart_hex16:
    push ax
    mov al, ah
    call uart_hex8
    pop ax
    call uart_hex8
    ret

;----------------------------------------
; Test: CPU Detection
;----------------------------------------
test_cpu_detect:
    mov si, msg_cpu_test
    call uart_puts

    ; Try to detect CPU type via FLAGS bits 12-15
    pushf
    pop ax
    mov cx, ax          ; Save original

    or ax, 0xF000       ; Try to set bits 12-15
    push ax
    popf
    pushf
    pop ax

    push cx             ; Restore original FLAGS
    popf

    and ax, 0xF000
    cmp ax, 0xF000
    jne .not_8086

    mov si, msg_cpu_8086
    call uart_puts
    jmp .done

.not_8086:
    test ax, ax
    jnz .is_286

    ; Could be 286 or higher - check for 32-bit
    ; For simplicity, report as 286+
    mov si, msg_cpu_286plus
    call uart_puts
    jmp .done

.is_286:
    mov si, msg_cpu_286plus
    call uart_puts

.done:
    mov si, msg_pass
    call uart_puts
    mov si, msg_pass_end
    call uart_puts
    ret

;----------------------------------------
; Test: ADD flags
;----------------------------------------
test_add_flags:
    mov si, msg_add_test
    call uart_puts

    ; Test: 0x7F + 0x01 = 0x80, OF=1, SF=1, ZF=0
    mov al, 0x7F
    add al, 0x01

    pushf
    pop bx              ; Flags in BX

    ; Check result
    cmp al, 0x80
    jne .fail

    ; Check OF (bit 11)
    test bh, 0x08
    jz .fail

    ; Check SF (bit 7)
    test bl, 0x80
    jz .fail

    ; Output: "status":"PASS","result":"0x80","flags":"0x...."},
    mov si, msg_pass
    call uart_puts
    mov si, msg_result
    call uart_puts
    mov al, 0x80
    call uart_hex8
    mov si, msg_flags
    call uart_puts
    mov ax, bx
    call uart_hex16
    mov si, msg_quote
    call uart_puts
    mov si, msg_pass_end
    call uart_puts
    ret

.fail:
    mov si, msg_fail
    call uart_puts
    ret

;----------------------------------------
; Test: SUB flags
;----------------------------------------
test_sub_flags:
    mov si, msg_sub_test
    call uart_puts

    ; Test: 0x80 - 0x01 = 0x7F, OF=1 (sign change)
    mov al, 0x80
    sub al, 0x01

    pushf
    pop bx

    ; Check result
    cmp al, 0x7F
    jne .fail

    ; Check OF
    test bh, 0x08
    jz .fail

    mov si, msg_pass
    call uart_puts
    mov si, msg_result
    call uart_puts
    mov al, 0x7F
    call uart_hex8
    mov si, msg_flags
    call uart_puts
    mov ax, bx
    call uart_hex16
    mov si, msg_quote
    call uart_puts
    mov si, msg_pass_end
    call uart_puts
    ret

.fail:
    mov si, msg_fail
    call uart_puts
    ret

;----------------------------------------
; Test: INC preserves CF
;----------------------------------------
test_inc_cf:
    mov si, msg_inc_test
    call uart_puts

    ; Set CF first
    stc

    ; INC should NOT affect CF
    mov al, 0xFF
    inc al              ; AL=0, but CF should still be 1

    jnc .fail           ; CF cleared = BUG

    ; AL should be 0
    test al, al
    jnz .fail

    mov si, msg_pass
    call uart_puts
    mov si, msg_pass_end
    call uart_puts
    ret

.fail:
    mov si, msg_fail
    call uart_puts
    ret

;----------------------------------------
; Data
;----------------------------------------
section .data

msg_banner:     db '{"suite":"poc-01","version":"1.0","tests":[', 13, 10, 0
msg_complete:   db '],"status":"complete"}', 13, 10, '===END===', 13, 10, 0
msg_crlf:       db 13, 10, 0

msg_cpu_test:   db '{"test":"cpu_detect",', 0
msg_cpu_8086:   db '"cpu":"8086",', 0
msg_cpu_286plus: db '"cpu":"286+",', 0

msg_add_test:   db '{"test":"add_overflow",', 0
msg_sub_test:   db '{"test":"sub_overflow",', 0
msg_inc_test:   db '{"test":"inc_cf_preserve",', 0

msg_pass:       db '"status":"PASS"', 0
msg_pass_end:   db '},', 13, 10, 0
msg_fail:       db '"status":"FAIL"},', 13, 10, 0

msg_result:     db ',"result":"0x', 0
msg_flags:      db '","flags":"0x', 0
msg_quote:      db '"', 0
