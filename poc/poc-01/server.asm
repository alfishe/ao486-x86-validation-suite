; POC-01 Scenario 2: Interactive Server Mode
; Implements command server on COM1 - host sends commands, gets responses
; Assemble: nasm -f bin -o server.com server.asm

org 100h

COM1_BASE   equ 0x3F8
COM1_THR    equ COM1_BASE + 0
COM1_RBR    equ COM1_BASE + 0
COM1_DLL    equ COM1_BASE + 0
COM1_DLH    equ COM1_BASE + 1
COM1_IER    equ COM1_BASE + 1
COM1_LCR    equ COM1_BASE + 3
COM1_MCR    equ COM1_BASE + 4
COM1_LSR    equ COM1_BASE + 5

BAUD_115200 equ 1
CMD_BUF_SIZE equ 64

section .text

start:
    ; Initialize COM1
    call uart_init

    ; Send ready message
    mov si, msg_ready
    call uart_puts

main_loop:
    ; Read command into buffer
    mov di, cmd_buffer
    xor cx, cx          ; Command length

.read_char:
    call uart_getc      ; AL = received char

    ; Echo back
    call uart_putc

    ; Check for CR (end of command)
    cmp al, 13
    je .process_cmd

    ; Check for backspace
    cmp al, 8
    je .backspace

    ; Store character (if room)
    cmp cx, CMD_BUF_SIZE - 1
    jge .read_char
    stosb
    inc cx
    jmp .read_char

.backspace:
    test cx, cx
    jz .read_char
    dec di
    dec cx
    jmp .read_char

.process_cmd:
    ; Null-terminate
    xor al, al
    stosb

    ; Send newline
    mov si, msg_crlf
    call uart_puts

    ; Parse and execute command
    call process_command
    jmp main_loop

;----------------------------------------
; Process command in cmd_buffer
;----------------------------------------
process_command:
    mov si, cmd_buffer

    ; Check for PING
    mov di, cmd_ping
    call str_cmp
    jc .do_ping

    ; Check for CPU
    mov di, cmd_cpu
    call str_cmp
    jc .do_cpu

    ; Check for TEST ADD
    mov di, cmd_test_add
    call str_cmp
    jc .do_test_add

    ; Check for TEST SUB
    mov di, cmd_test_sub
    call str_cmp
    jc .do_test_sub

    ; Check for TEST INC
    mov di, cmd_test_inc
    call str_cmp
    jc .do_test_inc

    ; Check for QUIT
    mov di, cmd_quit
    call str_cmp
    jc .do_quit

    ; Unknown command
    mov si, msg_unknown
    call uart_puts
    ret

.do_ping:
    mov si, msg_pong
    call uart_puts
    ret

.do_cpu:
    call test_cpu_detect
    ret

.do_test_add:
    call test_add
    ret

.do_test_sub:
    call test_sub
    ret

.do_test_inc:
    call test_inc
    ret

.do_quit:
    mov si, msg_bye
    call uart_puts
    mov ax, 0x4C00
    int 0x21

;----------------------------------------
; String compare: SI=input, DI=command
; Returns CF=1 if match (case insensitive prefix)
;----------------------------------------
str_cmp:
    push si
    push di

.loop:
    mov al, [di]
    test al, al         ; End of command string?
    jz .match

    mov ah, [si]

    ; Convert both to uppercase
    cmp al, 'a'
    jb .no_conv1
    cmp al, 'z'
    ja .no_conv1
    sub al, 32
.no_conv1:
    cmp ah, 'a'
    jb .no_conv2
    cmp ah, 'z'
    ja .no_conv2
    sub ah, 32
.no_conv2:
    cmp al, ah
    jne .no_match

    inc si
    inc di
    jmp .loop

.match:
    pop di
    pop si
    stc
    ret

.no_match:
    pop di
    pop si
    clc
    ret

;----------------------------------------
; UART routines
;----------------------------------------

uart_init:
    mov dx, COM1_LCR
    mov al, 0x80
    out dx, al

    mov dx, COM1_DLL
    mov al, BAUD_115200
    out dx, al
    mov dx, COM1_DLH
    xor al, al
    out dx, al

    mov dx, COM1_LCR
    mov al, 0x03
    out dx, al

    mov dx, COM1_MCR
    mov al, 0x03
    out dx, al

    mov dx, COM1_IER
    xor al, al
    out dx, al
    ret

; Wait and receive character, return in AL
uart_getc:
    push dx
.wait:
    mov dx, COM1_LSR
    in al, dx
    test al, 0x01       ; Data ready?
    jz .wait

    mov dx, COM1_RBR
    in al, dx
    pop dx
    ret

uart_putc:
    push ax
    push dx
    mov ah, al

.wait_ready:
    mov dx, COM1_LSR
    in al, dx
    test al, 0x20
    jz .wait_ready

    mov dx, COM1_THR
    mov al, ah
    out dx, al

    pop dx
    pop ax
    ret

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

uart_hex8:
    push ax
    push cx
    mov cl, al
    shr al, 4
    call .nibble
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
    pushf
    pop ax
    mov cx, ax

    or ax, 0xF000
    push ax
    popf
    pushf
    pop ax

    push cx
    popf

    and ax, 0xF000
    cmp ax, 0xF000
    jne .not_8086

    mov si, resp_cpu_8086
    call uart_puts
    ret

.not_8086:
    mov si, resp_cpu_286
    call uart_puts
    ret

;----------------------------------------
; Test: ADD
;----------------------------------------
test_add:
    mov al, 0x7F
    add al, 0x01
    pushf
    pop bx

    cmp al, 0x80
    jne .fail
    test bh, 0x08       ; OF
    jz .fail

    mov si, resp_add_pass
    call uart_puts

    ; Show flags
    mov si, msg_flags_prefix
    call uart_puts
    mov ax, bx
    call uart_hex16
    mov si, msg_crlf
    call uart_puts
    ret

.fail:
    mov si, resp_add_fail
    call uart_puts
    ret

;----------------------------------------
; Test: SUB
;----------------------------------------
test_sub:
    mov al, 0x80
    sub al, 0x01
    pushf
    pop bx

    cmp al, 0x7F
    jne .fail
    test bh, 0x08       ; OF
    jz .fail

    mov si, resp_sub_pass
    call uart_puts

    mov si, msg_flags_prefix
    call uart_puts
    mov ax, bx
    call uart_hex16
    mov si, msg_crlf
    call uart_puts
    ret

.fail:
    mov si, resp_sub_fail
    call uart_puts
    ret

;----------------------------------------
; Test: INC preserves CF
;----------------------------------------
test_inc:
    stc
    mov al, 0xFF
    inc al

    jnc .fail
    test al, al
    jnz .fail

    mov si, resp_inc_pass
    call uart_puts
    ret

.fail:
    mov si, resp_inc_fail
    call uart_puts
    ret

;----------------------------------------
; Data
;----------------------------------------
section .data

msg_ready:      db 'READY', 13, 10, '> ', 0
msg_crlf:       db 13, 10, '> ', 0
msg_unknown:    db 'ERR: Unknown command', 13, 10, '> ', 0
msg_pong:       db 'PONG', 13, 10, '> ', 0
msg_bye:        db 'BYE', 13, 10, 0
msg_flags_prefix: db 'FLAGS=0x', 0

cmd_ping:       db 'PING', 0
cmd_cpu:        db 'CPU', 0
cmd_test_add:   db 'TEST ADD', 0
cmd_test_sub:   db 'TEST SUB', 0
cmd_test_inc:   db 'TEST INC', 0
cmd_quit:       db 'QUIT', 0

resp_cpu_8086:  db 'CPU: 8086/8088', 13, 10, '> ', 0
resp_cpu_286:   db 'CPU: 80286+', 13, 10, '> ', 0

resp_add_pass:  db 'ADD overflow: PASS (0x7F+0x01=0x80, OF=1)', 13, 10, 0
resp_add_fail:  db 'ADD overflow: FAIL', 13, 10, '> ', 0

resp_sub_pass:  db 'SUB overflow: PASS (0x80-0x01=0x7F, OF=1)', 13, 10, 0
resp_sub_fail:  db 'SUB overflow: FAIL', 13, 10, '> ', 0

resp_inc_pass:  db 'INC CF preserve: PASS (CF unchanged after INC)', 13, 10, '> ', 0
resp_inc_fail:  db 'INC CF preserve: FAIL (CF was cleared)', 13, 10, '> ', 0

section .bss

cmd_buffer:     resb CMD_BUF_SIZE
