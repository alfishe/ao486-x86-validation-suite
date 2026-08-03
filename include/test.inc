; x86 Validation Suite - Test Framework Definitions
; ==================================================

%ifndef TEST_INC
%define TEST_INC

; Status codes
STATUS_PASS     equ 0
STATUS_FAIL     equ 1
STATUS_SKIP     equ 2
STATUS_ERROR    equ 3
STATUS_TIMEOUT  equ 4

; Module magic number
MODULE_MAGIC    equ 'TEST'
MODULE_VERSION  equ 1

;===========================================================================
; MODULE_HEADER — binary header at the start of every test module.
; DECISION (prep-phase E2): all pointer fields are 32-bit FAR pointers
;   (seg:off, stored as dd).  This allows the runner to dispatch to
;   modules loaded as overlays or residing in a different segment without
;   a near-data-group assumption.  The exact NASM/OMF relocation encoding
;   for far symbols is finalized in the DOS shim phase.
;===========================================================================
struc MODULE_HEADER
    .magic      resd 1      ; MODULE_MAGIC ('TEST')
    .version    resw 1      ; MODULE_VERSION
    .gen        resw 1      ; Minimum CPU generation (CPU_8086 … CPU_80486)
    .name       resd 1      ; Far ptr to module name string
    .desc       resd 1      ; Far ptr to description string
    .init       resd 1      ; Far ptr to init function
    .run        resd 1      ; Far ptr to run function
    .cleanup    resd 1      ; Far ptr to cleanup function
    .test_count resd 1      ; Number of test cases
    .test_table resd 1      ; Far ptr to TEST_ENTRY table
endstruc
MODULE_HEADER_SIZE equ 36

; Test entry structure — pointers are far (seg:off), same rationale.
struc TEST_ENTRY_STRUCT
    .func       resd 1      ; Far ptr to test function
    .name       resd 1      ; Far ptr to name string
    .flags      resw 1      ; Flags
    .reserved   resw 1      ; Alignment
endstruc
TEST_ENTRY_SIZE equ 12

; Test result structure
; DECISION: expected/actual are 32-bit (resd).  All 8086–486 GPR/flag
;   values fit in 32 bits.  FPU 80-bit mantissa comparison is done via a
;   stored memory image + integer compare, NOT through this struct.
struc TEST_RESULT
    .status     resb 1      ; STATUS_xxx
    .flags      resb 1      ; Additional flags
    .reserved   resw 1      ; Alignment
    .duration   resd 1      ; Execution time (ticks)
    .expected   resd 1      ; Expected value (32-bit)
    .actual     resd 1      ; Actual value (32-bit)
    .message    resd 1      ; Far ptr to error message string
endstruc
TEST_RESULT_SIZE equ 20

; FLAGS masks
FLAG_CF         equ 0x0001  ; Carry Flag
FLAG_PF         equ 0x0004  ; Parity Flag
FLAG_AF         equ 0x0010  ; Auxiliary Carry Flag
FLAG_ZF         equ 0x0040  ; Zero Flag
FLAG_SF         equ 0x0080  ; Sign Flag
FLAG_TF         equ 0x0100  ; Trap Flag
FLAG_IF         equ 0x0200  ; Interrupt Enable Flag
FLAG_DF         equ 0x0400  ; Direction Flag
FLAG_OF         equ 0x0800  ; Overflow Flag

; Combined flag masks
FLAGS_ARITH_MASK    equ FLAG_CF | FLAG_PF | FLAG_AF | FLAG_ZF | FLAG_SF | FLAG_OF
FLAGS_LOGIC_MASK    equ FLAG_PF | FLAG_ZF | FLAG_SF     ; OF=0, CF=0 after logic ops
FLAGS_SHIFT_MASK    equ FLAG_CF | FLAG_PF | FLAG_ZF | FLAG_SF | FLAG_OF

; Test entry macro
%macro TEST_ENTRY 3
    ; %1 = function, %2 = name string, %3 = flags
    dd %1
    dd %%name
    dw %3
    dw 0

    section .rodata
    %%name: db %2, 0
    section .text
%endmacro

; Save all registers
%macro PUSH_ALL 0
    push ax
    push bx
    push cx
    push dx
    push si
    push di
    push bp
%endmacro

; Restore all registers
%macro POP_ALL 0
    pop bp
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
%endmacro

; Test a register value
%macro TEST_REG 3
    ; %1 = register, %2 = expected, %3 = fail_label
    cmp %1, %2
    jne %3
%endmacro

; Test FLAGS after operation
%macro TEST_FLAGS 3
    ; %1 = expected, %2 = mask, %3 = fail_label
    pushf
    pop ax
    and ax, %2
    cmp ax, %1
    jne %3
%endmacro

; Record failure — stores expected/actual/message into a TEST_RESULT buffer.
; DECISION (prep-phase E4): the first operand is a REGISTER or memory
;   operand pointing to the result buffer (e.g. `di`, `bx`), so the macro
;   is re-entrant and does not depend on a global symbol.
;   The message field stores a far pointer; the low word is written here
;   and the high word (segment) is finalized by the shim's pointer-encoding
;   convention.
; Usage:  RECORD_FAILURE di, msg_no_exception, EXPECTED_FLAGS, ax
%macro RECORD_FAILURE 4
    ; %1 = result buffer ptr (register), %2 = msg label,
    ; %3 = expected dword, %4 = actual dword
    mov dword [%1 + TEST_RESULT.expected], %3
    mov dword [%1 + TEST_RESULT.actual], %4
    mov word  [%1 + TEST_RESULT.message + 0], %2
    mov word  [%1 + TEST_RESULT.message + 2], 0       ; seg placeholder (shim resolves)
    mov byte  [%1 + TEST_RESULT.status], STATUS_FAIL
%endmacro

; Simple delay using loop
%macro DELAY_LOOP 1
    ; %1 = iteration count
    mov cx, %1
%%loop:
    loop %%loop
%endmacro

; Microsecond delay (approximate, depends on CPU speed)
%macro DELAY_US 1
    ; %1 = microseconds (very approximate)
    mov cx, %1
%%outer:
    mov ax, 10
%%inner:
    dec ax
    jnz %%inner
    loop %%outer
%endmacro

%endif ; TEST_INC
