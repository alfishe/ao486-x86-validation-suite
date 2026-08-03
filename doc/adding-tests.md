# Adding Tests to x86 Validation Suite

## Quick Start

1. **Read the spec** — find the detailed test specification for your module in
   [doc/specs/index.md](specs/index.md). Each spec has exact test-case tables,
   expected flag values, state save/restore contracts, and known divergences.
2. Create test file in appropriate directory
3. Implement required interface
4. Add to build system
5. Test on real hardware if possible
6. Document the test

## Test Module Structure

Every test module must implement the standard interface:

```nasm
; file: src/cpu/8086/example.asm

%include "include/test.inc"
%include "include/x86.inc"

section .data
    module_name     db 'example', 0
    module_desc     db 'Example test module', 0

; Module header - MUST be at start
; DECISION (prep-phase E2): all pointer fields are 32-bit FAR (seg:off).
; The binary struct is defined in include/test.inc as MODULE_HEADER.
section .text
global MODULE_HEADER
MODULE_HEADER:
    dd MODULE_MAGIC         ; 'TEST' magic number
    dw MODULE_VERSION       ; Interface version
    dw CPU_8086             ; Minimum CPU generation (CPU_8086 … CPU_80486)
    dd module_name          ; Far ptr (seg:off)
    dd module_desc          ; Far ptr
    dd module_init          ; Far ptr
    dd module_run           ; Far ptr
    dd module_cleanup       ; Far ptr
    dd TEST_COUNT           ; Number of tests
    dd test_table           ; Far ptr to test table

; Test table
test_table:
    TEST_ENTRY test_case_1, 'test_case_1', 0
    TEST_ENTRY test_case_2, 'test_case_2', 0
    ; ...
TEST_COUNT equ ($ - test_table) / TEST_ENTRY_SIZE

; Required functions
module_init:
    ; Initialize module state
    ; Return: AX = 0 success, non-zero = skip module
    xor ax, ax
    ret

module_run:
    ; Run all tests (called if you want automatic iteration)
    ; Or can be empty if test_table is used
    ret

module_cleanup:
    ; Clean up any resources
    ret

; Individual test cases
test_case_1:
    ; Perform test
    ; Return: AX = STATUS_PASS/STATUS_FAIL
    mov ax, STATUS_PASS
    ret

test_case_2:
    ; ...
    ret
```

## Test Macros

Use the provided macros for consistent testing:

```nasm
%include "include/test.inc"

; Compare a register value (jumps to fail_label if mismatch)
TEST_REG reg, expected, fail_label
    ; e.g.  TEST_REG al, 0x46, .fail_result

; Test FLAGS state (3-arg form in test.inc)
TEST_FLAGS expected_flags, mask, fail_label
    ; Pushes FLAGS, ANDs with mask, compares to expected_flags.
    ; e.g.  TEST_FLAGS FLAG_CF|FLAG_OF, FLAGS_ARITH_MASK, .fail_flags

; Record a failure with details (4-arg, re-entrant)
RECORD_FAILURE buf_ptr_reg, msg, expected, actual
    ; Stores expected/actual/msg into the TEST_RESULT buffer pointed
    ; to by buf_ptr_reg (e.g. di, bx).  Sets status = STATUS_FAIL.
    ; e.g.  RECORD_FAILURE di, msg_add_fail, 0x46, eax

; Push/pop all GPRs (16-bit)
PUSH_ALL                  ; pushes ax,bx,cx,dx,si,di,bp
POP_ALL                   ; pops in reverse order

; Complete test helpers (PLANNED — not yet in test.inc; Phase 1 INFRA)
; TEST_ARITH_R8_R8   insn, op1, op2, expected_result, expected_flags
; TEST_ARITH_R16_R16 insn, op1, op2, expected_result, expected_flags
; TEST_SHIFT_R8      insn, op, count, expected_result, expected_flags
```

## Example: Testing ADD Instruction

```nasm
; src/cpu/8086/arith.asm

%include "include/test.inc"
%include "include/x86.inc"

section .data
    module_name     db '8086.arith', 0
    module_desc     db '8086 arithmetic instruction tests', 0
    
    ; Test data
    msg_add_fail    db 'ADD result mismatch', 0
    msg_flags_fail  db 'FLAGS mismatch', 0

section .bss
    test_result     resb TEST_RESULT_SIZE

section .text
global MODULE_HEADER
MODULE_HEADER:
    dd 'TEST'
    dw 1
    dw 0
    dd module_name
    dd module_desc
    dd module_init
    dd module_run
    dd module_cleanup
    dd TEST_COUNT
    dd test_table

test_table:
    TEST_ENTRY test_add_r8_r8,      'add_r8_r8', 0
    TEST_ENTRY test_add_r8_r8_cf,   'add_r8_r8_cf', 0
    TEST_ENTRY test_add_r8_r8_of,   'add_r8_r8_of', 0
    TEST_ENTRY test_add_r16_r16,    'add_r16_r16', 0
    TEST_ENTRY test_add_r8_m8,      'add_r8_m8', 0
    TEST_ENTRY test_add_r8_imm8,    'add_r8_imm8', 0
TEST_COUNT equ ($ - test_table) / TEST_ENTRY_SIZE

module_init:
    xor ax, ax
    ret

module_run:
    ret

module_cleanup:
    ret

;----------------------------------------------------------------------------
; test_add_r8_r8 - Basic ADD reg8, reg8
;----------------------------------------------------------------------------
test_add_r8_r8:
    push bx
    
    ; Test 1: Simple addition, no flags
    mov al, 0x12
    mov bl, 0x34
    add al, bl
    
    cmp al, 0x46
    jne .fail_result
    
    pushf
    pop ax
    and ax, FLAGS_ARITH_MASK    ; CF, PF, AF, ZF, SF, OF
    cmp ax, FLAGS_PARITY        ; Only PF should be set (0x46 has even parity)
    jne .fail_flags
    
    ; Test 2: Result is zero
    mov al, 0x80
    mov bl, 0x80
    add al, bl
    
    cmp al, 0x00
    jne .fail_result
    
    pushf
    pop ax
    and ax, FLAGS_ARITH_MASK
    ; Should have: CF=1, ZF=1, PF=1, OF=1
    test ax, FLAG_CF
    jz .fail_flags
    test ax, FLAG_ZF
    jz .fail_flags
    test ax, FLAG_OF
    jz .fail_flags
    
    ; All tests passed
    pop bx
    mov ax, STATUS_PASS
    ret

.fail_result:
    mov word [test_result + TEST_RESULT.message], msg_add_fail
    jmp .fail

.fail_flags:
    mov word [test_result + TEST_RESULT.message], msg_flags_fail
    
.fail:
    mov byte [test_result + TEST_RESULT.status], STATUS_FAIL
    pop bx
    mov ax, STATUS_FAIL
    ret

;----------------------------------------------------------------------------
; test_add_r8_r8_cf - ADD with carry flag output
;----------------------------------------------------------------------------
test_add_r8_r8_cf:
    ; Test carry generation
    mov al, 0xFF
    mov bl, 0x01
    add al, bl
    
    jnc .fail               ; CF should be set
    cmp al, 0x00            ; Result should be 0
    jne .fail
    
    mov ax, STATUS_PASS
    ret

.fail:
    mov ax, STATUS_FAIL
    ret

;----------------------------------------------------------------------------
; test_add_r8_r8_of - ADD with overflow detection
;----------------------------------------------------------------------------
test_add_r8_r8_of:
    ; Signed overflow: positive + positive = negative
    mov al, 0x7F            ; 127
    mov bl, 0x01            ; 1
    add al, bl              ; Should be 128, but signed = -128
    
    jno .fail               ; OF should be set
    cmp al, 0x80            ; Result
    jne .fail
    js .check_positive_of   ; SF should be set (negative result)
    jmp .fail

.check_positive_of:
    ; Signed overflow: negative + negative = positive
    mov al, 0x80            ; -128
    mov bl, 0x80            ; -128
    add al, bl              ; Should be -256, wraps to 0
    
    jno .fail               ; OF should be set
    cmp al, 0x00
    jne .fail
    
    mov ax, STATUS_PASS
    ret

.fail:
    mov ax, STATUS_FAIL
    ret

; ... more test cases ...
```

## Testing Protected Mode

For protected mode tests, use the PM framework:

```nasm
%include "include/pmode.inc"

test_gdt_limit_check:
    ; This test requires protected mode setup
    call require_286_or_higher
    test ax, ax
    jnz .skip
    
    ; Enter protected mode (self-switching — see pattern below)
    call pm_enter
    
    ; Set up test segment with small limit
    mov ax, TEST_SEL
    mov ds, ax
    
    ; Try to access beyond limit - should fault
    EXPECT_EXCEPTION EXC_GP
    mov al, [0x1000]        ; Beyond our 16-byte limit
    END_EXPECT_EXCEPTION
    
    ; Exit protected mode
    call pm_exit
    
    mov ax, STATUS_PASS
    ret

.skip:
    mov ax, STATUS_SKIP
    ret
```

### RING0 Self-Switching PM Pattern

Per AGENTS.md §3, PM tests under DOS **must self-switch** — never rely on a
DPMI host (it abstracts the CPU behavior we're testing). The self-switch
sequence is:

```nasm
; Self-switch from real mode to ring-0 PM and back.
; This is the minimal skeleton — adapt as needed.

pm_enter:
    cli

    ; 1. Build a minimal GDT (code + data segments, ring 0)
    ;    Use GDT_ENTRY macro from include/x86.inc
    ;    GDT_BASE must be in low memory accessible from real mode
    
    ; 2. Load GDTR
    lgdt [gdtr_32]          ; 32-bit GDT register
    
    ; 3. Enable PE (386+ uses MOV CR0; 286 uses LMSW)
    mov eax, cr0
    or eax, 1               ; Set PE bit
    mov cr0, eax
    
    ; 4. Far JMP to flush prefetch queue and load PM CS
    ;    MUST be immediate next instruction; selector points to code desc
    jmp dword CODE_SEL:pm_entry_32

[BITS 32]
pm_entry_32:
    ; Now in 32-bit PM at CPL=0.
    ; Load data segment registers with data selector
    mov ax, DATA_SEL
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov esp, 0x00090000     ; Stack in safe low memory
    
    ; --- PM test code goes here ---
    
    ret                     ; or fall through to pm_exit

pm_exit:
    ; 1. Return to real mode (386+)
    ;    Must be at CPL=0, interrupts disabled
    jmp CODE_SEL_RM:pm_entry_16   ; Load 16-bit code selector first

[BITS 16]
pm_entry_16:
    ; Clear PE bit
    mov eax, cr0
    and eax, ~1
    mov cr0, eax
    
    ; Far JMP to flush, reload real-mode CS
    jmp 0x0000:pm_real

pm_real:
    ; Restore real-mode segment registers
    xor ax, ax
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, 0xFFFE
    
    sti
    ret
```

> **WARNING:** The self-switch is fragile. If PE is set but the far JMP
> doesn't execute immediately, the CPU fetches garbage as 32-bit code.
> Test on DOSBox-X first, then 86Box for higher fidelity.

### Exception Handler Pattern

Exception tests install a custom IDT entry, trigger the fault, verify the
handler ran with the correct vector and error code, then recover:

```nasm
; Pattern: trigger #GP, verify handler catches it with correct error code.
; The handler must ADVANCE the saved EIP past the faulting instruction
; (for tests where the fault is expected and non-restartable).

section .data
    gp_caught       db 0
    gp_error_code   dw 0

; In PM, install the handler in the IDT:
    ; IDT entry 13 = #GP
    ; Format: offset_lo(16) | selector(16) | reserved(8) | type(8) | offset_hi(16)
    mov word [idt + 13*8 + 0], gp_handler & 0xFFFF
    mov word [idt + 13*8 + 2], CODE_SEL
    mov byte [idt + 13*8 + 4], 0
    mov byte [idt + 13*8 + 5], 0x8E   ; Present, 386 interrupt gate
    mov word [idt + 13*8 + 6], gp_handler >> 16
    
    ; Clear detection flag
    mov byte [gp_caught], 0
    
    ; --- Trigger the fault ---
    ; (e.g., load a bad selector)
    
    ; --- After handler returns ---
    ; Check handler ran
    cmp byte [gp_caught], 1
    jne .fail_no_exception
    
    ; Check error code
    cmp word [gp_error_code], EXPECTED_ERROR
    jne .fail_wrong_code
    
    ; PASS
    
[BITS 32]
gp_handler:
    ; ESP points to: EIP, CS, EFLAGS [, error code]
    mov eax, [esp]           ; Error code (if applicable)
    mov [gp_error_code], eax
    
    ; Skip the faulting instruction (advance saved EIP)
    ; NOTE: only do this for non-restartable test faults!
    add dword [esp + 4], FAULTING_INSN_LEN
    
    mov byte [gp_caught], 1
    iretd                    ; Return to instruction after the fault
```

> **Key:** the handler skips the faulting instruction by adding its byte
> length to the saved EIP on the stack. This is only safe for **expected**
> faults where you know the exact instruction length. For restartable
> faults (like #PF), leave EIP unchanged so the CPU retries after the
> handler fixes the page mapping.

## Testing FPU

```nasm
%include "include/fpu.inc"

test_fdiv_basic:
    call require_fpu
    test ax, ax
    jnz .skip
    
    ; Initialize FPU
    fninit
    
    ; Load operands
    fld dword [float_10]    ; ST(0) = 10.0
    fld dword [float_2]     ; ST(0) = 2.0, ST(1) = 10.0
    
    ; Divide
    fdiv st1, st0           ; ST(1) = 10.0 / 2.0 = 5.0
    
    ; Pop and check result
    fstp st0                ; Remove divisor
    
    ; Compare with expected
    fld dword [float_5]     ; Load expected
    fcompp                  ; Compare and pop both
    fstsw ax
    sahf
    jne .fail
    
    mov ax, STATUS_PASS
    ret

.skip:
    mov ax, STATUS_SKIP
    ret

.fail:
    mov ax, STATUS_FAIL
    ret

section .data
    float_2     dd 2.0
    float_5     dd 5.0
    float_10    dd 10.0
```

## Testing Peripherals

```nasm
%include "include/ports.inc"

test_pit_mode2:
    ; Save current state
    call pit_save
    
    ; Configure channel 0 for mode 2
    mov al, 00110100b       ; Chan 0, LSB/MSB, Mode 2, Binary
    out PORT_PIT_CTRL, al
    
    ; Load count value
    mov al, 100 & 0xFF
    out PORT_PIT_CH0, al
    mov al, 100 >> 8
    out PORT_PIT_CH0, al
    
    ; Small delay
    DELAY_US 100
    
    ; Read back count
    mov al, 00000000b       ; Latch channel 0
    out PORT_PIT_CTRL, al
    in al, PORT_PIT_CH0     ; LSB
    mov ah, al
    in al, PORT_PIT_CH0     ; MSB
    xchg al, ah
    
    ; Count should be less than initial
    cmp ax, 100
    jae .fail
    
    ; Restore and pass
    call pit_restore
    mov ax, STATUS_PASS
    ret

.fail:
    call pit_restore
    mov ax, STATUS_FAIL
    ret
```

## Documentation Requirements

Every test MUST have:

1. **Header comment** explaining what is tested
2. **Expected behavior** documented
3. **Reference** to specification (Intel manual section, etc.)
4. **Known issues** if any CPUs/emulators behave differently

```nasm
;============================================================================
; TEST: ADD r8, r8 - Overflow flag behavior
;
; Tests that the overflow flag is correctly set when adding two signed
; numbers produces a result that cannot be represented in the destination.
;
; Cases tested:
;   1. 0x7F + 0x01 = 0x80 (127 + 1 = -128 in signed) -> OF=1
;   2. 0x80 + 0x80 = 0x00 (-128 + -128 = 0 with OF) -> OF=1
;   3. 0x40 + 0x20 = 0x60 (no overflow) -> OF=0
;
; Reference: Intel 8086 Family User's Manual, Section 2.5.4
;           "Conditional Transfer on Overflow"
;
; Known issues:
;   - Early 8086 stepping A1 may not set OF correctly (unverified)
;
; Author: <name>
; Date: YYYY-MM-DD
;============================================================================
```

## Adding to Build System

Edit `Makefile`:

```makefile
# Add new object file to appropriate list
CPU_8086_OBJS += $(OBJ)/cpu/8086/newtest.obj
```

## Testing Your Tests

1. **Build and run locally**
   ```bash
   make
   dosbox-x build/bin/x86val.exe
   ```

2. **Test with verbose output**
   ```
   C:\> X86VAL.EXE /module:8086.arith /verbose:3
   ```

3. **Compare with reference (if available)**
   ```bash
   python3 tools/compare.py reference.json my_results.json
   ```

4. **Test on real hardware**
   - Boot DOS on real 486 (or earlier as appropriate)
   - Run tests
   - Save results for reference

## Common Pitfalls

1. **Don't assume FLAGS state** - Clear or set FLAGS explicitly before test
2. **Save/restore state** - Tests must not affect subsequent tests
3. **Handle CPU differences** - Check CPU type before using newer instructions
4. **Document undefined behavior** - Note when behavior is undefined/varies
5. **Test edge cases** - 0, -1, MAX, MIN, boundary conditions
