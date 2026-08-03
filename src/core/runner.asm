;============================================================================
; MODULE: core/runner.asm
; DESC:   Test runner — iterates the module table, dispatches init/run/cleanup
;
; Test module table format (8 bytes per entry):
;   offset 0: dw run_fn      ; near ptr to run function (0 = end sentinel)
;   offset 2: dw init_fn     ; near ptr to init (0 = skip)
;   offset 4: dw cleanup_fn  ; near ptr to cleanup (0 = skip)
;   offset 6: dw name_ptr    ; near ptr to module name string
;
; Module run functions return AL = STATUS_PASS / STATUS_FAIL / STATUS_SKIP
; All registers preserved except AX (return value).
;============================================================================

TM_RUN     equ 0
TM_INIT    equ 2
TM_CLEANUP equ 4
TM_NAME    equ 6
TM_SIZE    equ 8

;---------------------------------------------------------------------------
; runner_main — Run all registered test modules
;---------------------------------------------------------------------------
runner_main:
    push    ax
    push    bx
    push    bp
    push    si

    ; Reset counters
    xor     ax, ax
    mov     [g_pass_count], ax
    mov     [g_fail_count], ax
    mov     [g_skip_count], ax
    mov     [g_total_count], ax

    mov     si, runner_str_header
    call    output_puts
    call    output_newline

    mov     bp, test_module_table

.next:
    mov     ax, [bp + TM_RUN]
    test    ax, ax
    jz      .done

    inc     word [g_total_count]

    ; Print module name
    mov     si, runner_str_bullet
    call    output_puts
    mov     si, [bp + TM_NAME]
    call    output_puts
    mov     si, runner_str_sep
    call    output_puts

    ; Call init (optional)
    mov     ax, [bp + TM_INIT]
    test    ax, ax
    jz      .do_run
    call    ax

.do_run:
    mov     ax, [bp + TM_RUN]
    call    ax
    mov     bl, al                       ; save status

    ; Classify result
    cmp     bl, STATUS_PASS
    je      .pass
    cmp     bl, STATUS_FAIL
    je      .fail
    cmp     bl, STATUS_SKIP
    je      .skip
    mov     bl, STATUS_FAIL              ; unknown → fail
    jmp     .fail

.pass:
    inc     word [g_pass_count]
    mov     si, runner_str_pass
    jmp     .print
.fail:
    inc     word [g_fail_count]
    mov     si, runner_str_fail
    jmp     .print
.skip:
    inc     word [g_skip_count]
    mov     si, runner_str_skip

.print:
    call    output_puts
    call    output_newline

    ; Call cleanup (optional)
    mov     ax, [bp + TM_CLEANUP]
    test    ax, ax
    jz      .advance
    call    ax

.advance:
    add     bp, TM_SIZE
    jmp     .next

.done:
    call    output_newline
    mov     si, runner_str_summary
    call    output_puts
    call    output_newline

    mov     si, runner_str_total
    call    output_puts
    mov     ax, [g_total_count]
    call    output_dec16
    call    output_newline

    mov     si, runner_str_passed
    call    output_puts
    mov     ax, [g_pass_count]
    call    output_dec16
    call    output_newline

    mov     si, runner_str_failed
    call    output_puts
    mov     ax, [g_fail_count]
    call    output_dec16
    call    output_newline

    mov     si, runner_str_skipped
    call    output_puts
    mov     ax, [g_skip_count]
    call    output_dec16
    call    output_newline

    pop     si
    pop     bp
    pop     bx
    pop     ax
    ret

; --- runner data ---
g_pass_count:   dw 0
g_fail_count:   dw 0
g_skip_count:   dw 0
g_total_count:  dw 0

runner_str_header:  db 'Running tests...', 0
runner_str_bullet:  db '  ', 0
runner_str_sep:     db ' ... ', 0
runner_str_pass:    db 'PASS', 0
runner_str_fail:    db 'FAIL', 0
runner_str_skip:    db 'SKIP', 0
runner_str_summary: db '--- Summary ---', 0
runner_str_total:   db 'Total:   ', 0
runner_str_passed:  db 'Passed:  ', 0
runner_str_failed:  db 'Failed:  ', 0
runner_str_skipped: db 'Skipped: ', 0

; --- Test module registration table ---
; Add modules here as they are created, e.g.:
;   dw smoke_run,  smoke_init,  smoke_cleanup,  smoke_name
;   dw arith_run,  arith_init,  arith_cleanup,  arith_name
test_module_table:
    dw smoke_run, smoke_init, smoke_cleanup, smoke_name
    dw arith_run, arith_init, arith_cleanup, arith_name
    dw shift_run, shift_init, shift_cleanup, shift_name
    dw logic_run, logic_init, logic_cleanup, logic_name
    dw string_run, string_init, string_cleanup, string_name
    dw incdec_run, incdec_init, incdec_cleanup, incdec_name
    dw div_run, div_init, div_cleanup, div_name
    dw stack_run, stack_init, stack_cleanup, stack_name
    dw bcd_run, bcd_init, bcd_cleanup, bcd_name
    dw control_run, control_init, control_cleanup, control_name
    dw xfer_run, xfer_init, xfer_cleanup, xfer_name
    dw mul_run, mul_init, mul_cleanup, mul_name
    ; 80186+
    dw insns186_run, insns186_init, insns186_cleanup, insns186_name
    dw enh186_run, enh186_init, enh186_cleanup, enh186_name
    ; 80286+
    dw real286_run, real286_init, real286_cleanup, real286_name
    dw pm286_run, pm286_init, pm286_cleanup, pm286_name
    ; FPU 8087+
    dw fpu_basic_run, fpu_basic_init, fpu_basic_cleanup, fpu_basic_name
    dw fpu_arith_run, fpu_arith_init, fpu_arith_cleanup, fpu_arith_name
    dw fpu_cmp_run, fpu_cmp_init, fpu_cmp_cleanup, fpu_cmp_name
    dw fpu_cs_run, fpu_cs_init, fpu_cs_cleanup, fpu_cs_name
    dw fpu_trans_run, fpu_trans_init, fpu_trans_cleanup, fpu_trans_name
    dw fpu_misc_run, fpu_misc_init, fpu_misc_cleanup, fpu_misc_name
    dw fpu_extra_run, fpu_extra_init, fpu_extra_cleanup, fpu_extra_name
    dw 0                               ; end sentinel
