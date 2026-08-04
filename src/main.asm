;============================================================================
; x86 Validation Suite — Main Entry Point
; Target: DOS .COM (tiny model, flat binary)
; Build:  nasm -f bin -o build/bin/X86VAL.COM -I include/ -I src/ src/main.asm
;
; For .COM: CS=DS=ES=SS, program loaded at CS:0100h, PSP at CS:0000h.
; All framework modules are textually %included into this single translation
; unit. When wlink/OMF becomes available, modules will compile separately.
;============================================================================

%include "test.inc"
%include "x86.inc"
%include "ports.inc"
%include "dos.inc"

bits 16
org   0x100

;============================================================================
; ENTRY POINT
;============================================================================
_start:
    cld                                 ; clear direction flag (required!)
    mov     sp, 0xFFF0                  ; set stack pointer explicitly

    ; --- Initialize output system (console enabled by default) ---
    call    output_init

    ; --- Parse command line (may enable serial/file output) ---
    call    config_parse

    ; --- Print banner ---
    mov     si, str_banner
    call    output_puts
    call    output_newline
    mov     si, str_separator
    call    output_puts

    ; --- Detect CPU ---
    call    detect_cpu
    mov     si, str_cpu_label
    call    output_puts
    call    print_cpu_name
    call    output_newline

    ; --- Detect FPU ---
    call    detect_fpu
    mov     si, str_fpu_label
    call    output_puts
    call    print_fpu_name
    call    output_newline
    mov     si, str_separator
    call    output_puts

    ; --- Run test suite ---
    call    runner_main

    ; --- Cleanup ---
    mov     si, str_separator
    call    output_puts
    mov     si, str_complete
    call    output_puts
    call    output_newline
    call    output_flush
    call    dos_file_close

    ; --- Exit (code 0 = all pass, 1 = any failure) ---
    mov     ax, [g_fail_count]
    test    ax, ax
    jz      .exit_ok
    mov     ax, 0x4C01                  ; exit code 1 = failures present
    int     0x21
.exit_ok:
    mov     ax, 0x4C00                  ; exit code 0 = all passed
    int     0x21

;---------------------------------------------------------------------------
; print_cpu_name — Print CPU family name based on g_cpu_type
;---------------------------------------------------------------------------
print_cpu_name:
    push    ax
    push    si
    mov     al, [g_cpu_type]
    mov     si, str_cpu_unknown        ; default
    cmp     al, CPU_8086
    jne     .c1
    mov     si, str_cpu_8086
    jmp     .p
.c1:
    cmp     al, CPU_80286
    jne     .c2
    mov     si, str_cpu_286
    jmp     .p
.c2:
    cmp     al, CPU_80386
    jne     .c3
    mov     si, str_cpu_386
    jmp     .p
.c3:
    cmp     al, CPU_80486
    jne     .c4
    mov     si, str_cpu_486
    jmp     .p
.c4:
    cmp     al, CPU_PENTIUM
    jne     .p
    mov     si, str_cpu_pent
.p:
    call    output_puts
    pop     si
    pop     ax
    ret

;---------------------------------------------------------------------------
; print_fpu_name — Print FPU type name based on g_fpu_type
;---------------------------------------------------------------------------
print_fpu_name:
    push    ax
    push    si
    mov     al, [g_fpu_type]
    mov     si, str_fpu_unknown
    cmp     al, FPU_NONE
    jne     .f1
    mov     si, str_fpu_none
    jmp     .p
.f1:
    cmp     al, FPU_8087
    jne     .f2
    mov     si, str_fpu_8087
    jmp     .p
.f2:
    cmp     al, FPU_80287
    jne     .f3
    mov     si, str_fpu_287
    jmp     .p
.f3:
    cmp     al, FPU_80387
    jne     .f4
    mov     si, str_fpu_387
    jmp     .p
.f4:
    cmp     al, FPU_80486
    jne     .p
    mov     si, str_fpu_486
.p:
    call    output_puts
    pop     si
    pop     ax
    ret

;============================================================================
; FRAMEWORK MODULES (functions + module-local data)
;============================================================================
%include "arch/dos/dosio.asm"
%include "core/output.asm"
%include "core/memory.asm"
%include "core/state.asm"
%include "core/detect.asm"
%include "core/config.asm"
%include "core/runner.asm"

;============================================================================
; TEST MODULES
; (Uncomment includes and add runner table entries as modules are created)
;============================================================================
%include "cpu/8086/smoke.asm"
%include "cpu/8086/arith.asm"
%include "cpu/8086/shift.asm"
%include "cpu/8086/logic.asm"
%include "cpu/8086/string.asm"
%include "cpu/8086/inc_dec.asm"
%include "cpu/8086/div.asm"
%include "cpu/8086/stack.asm"
%include "cpu/8086/bcd.asm"
%include "cpu/8086/control.asm"
%include "cpu/8086/transfer.asm"
%include "cpu/8086/multiply.asm"

; --- 80186+ tests ---
%include "cpu/80186/new_insns.asm"
%include "cpu/80186/enhanced.asm"

; --- 80286+ tests ---
%include "cpu/80286/real.asm"
%include "cpu/80286/protected.asm"

; --- 80386+ tests ---
%include "cpu/80386/new_insns.asm"
%include "cpu/80386/bitops.asm"
%include "cpu/80386/shifts32.asm"
%include "cpu/80386/arith32.asm"
%include "cpu/80386/strings32.asm"
%include "cpu/80386/addr32.asm"
%include "cpu/80386/seg386.asm"

; --- FPU 8087+ tests ---
%include "fpu/8087/basic.asm"
%include "fpu/8087/arith.asm"
%include "fpu/8087/compare.asm"
%include "fpu/8087/const_special.asm"
%include "fpu/8087/transc.asm"
%include "fpu/8087/misc.asm"
%include "fpu/8087/extra.asm"

;============================================================================
; GLOBAL DATA
;============================================================================
str_banner:        db 'x86 Validation Suite v0.1.0', 0
str_separator:     db '========================================', 0x0D, 0x0A, 0
str_complete:      db 'Suite complete.', 0
str_cpu_label:     db 'CPU: ', 0
str_fpu_label:     db 'FPU: ', 0

str_cpu_8086:      db '8086/8088', 0
str_cpu_286:       db '80286', 0
str_cpu_386:       db '80386', 0
str_cpu_486:       db '80486', 0
str_cpu_pent:      db 'Pentium (586+)', 0
str_cpu_unknown:   db 'Unknown', 0

str_fpu_none:      db 'None', 0
str_fpu_8087:      db '8087', 0
str_fpu_287:       db '80287', 0
str_fpu_387:       db '80387', 0
str_fpu_486:       db '80486 (integrated)', 0
str_fpu_unknown:   db 'Unknown', 0

; NOTE: g_cpu_type, g_fpu_type, g_cpu_features, g_fpu_features
; are defined in core/detect.asm
