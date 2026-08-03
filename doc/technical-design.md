# x86 Validation Suite - Technical Design Document

## 1. Architecture Overview

### 1.1 High-Level Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           x86 Validation Suite                               │
├─────────────────────────────────────────────────────────────────────────────┤
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐        │
│  │   Runner    │  │   Output    │  │   Config    │  │   Utils     │        │
│  │   Engine    │──│   System    │──│   Manager   │──│   Library   │        │
│  └──────┬──────┘  └─────────────┘  └─────────────┘  └─────────────┘        │
│         │                                                                    │
│  ┌──────┴───────────────────────────────────────────────────────────────┐  │
│  │                         Test Module Interface                         │  │
│  └──────┬──────────────┬──────────────┬──────────────┬─────────────────┘  │
│         │              │              │              │                      │
│  ┌──────┴─────┐ ┌──────┴─────┐ ┌──────┴─────┐ ┌──────┴─────┐              │
│  │  CPU Tests │ │  FPU Tests │ │  Peripheral │ │  Timing    │              │
│  │  Modules   │ │  Modules   │ │  Tests      │ │  Tests     │              │
│  └────────────┘ └────────────┘ └────────────┘ └────────────┘              │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 1.2 Design Principles

1. **Modularity**: Each test is a self-contained unit
2. **No Dependencies**: Everything built from source, no external libs
3. **Minimal Memory**: Total footprint < 256KB conventional
4. **Fail-Safe**: Tests cannot corrupt system or hang indefinitely
5. **Deterministic**: Same inputs produce same outputs
6. **Documented**: Every test explains what and why

### 1.3 Directory Structure

```
x86-validation-suite/
├── README.md                   # Quick start guide
├── AGENTS.md                   # Build & maintenance rulebook
├── LICENSE                     # Open source license
├── Makefile                    # Master build
├── doc/                        # prd, technical-design, test-venues,
│                               # coverage-matrix, references, adding-tests
│
├── src/
│   ├── core/                   # Framework core
│   │   ├── runner.asm          # Test execution engine
│   │   ├── output.asm          # Output system
│   │   ├── config.asm          # Configuration
│   │   ├── memory.asm          # Memory management
│   │   ├── timing.asm          # High-res timing
│   │   └── macros.inc          # Common macros
│   │
│   ├── cpu/                    # CPU test modules
│   │   ├── 8086/
│   │   │   # NOTE: CPU detection lives in src/core/detect.asm (framework infra),
│   │   │   #       NOT under src/cpu/.  FPU detection lives in src/fpu/detect.asm.
│   │   │   ├── arith.asm       # ADD, SUB, MUL, DIV, etc.
│   │   │   ├── logic.asm       # AND, OR, XOR, NOT, TEST
│   │   │   ├── shift.asm       # SHL, SHR, SAR, ROL, ROR, RCL, RCR
│   │   │   ├── string.asm      # MOVS, STOS, CMPS, SCAS, LODS
│   │   │   ├── control.asm     # JMP, CALL, RET, INT, IRET
│   │   │   ├── flags.asm       # FLAG manipulation
│   │   │   ├── segment.asm     # Segment operations
│   │   │   ├── stack.asm       # PUSH, POP operations
│   │   │   ├── bcd.asm         # AAA, AAS, AAM, AAD, DAA, DAS
│   │   │   └── misc.asm        # NOP, HLT, WAIT, etc.
│   │   ├── 80186/
│   │   │   ├── new_insns.asm   # ENTER, LEAVE, BOUND, INS, OUTS
│   │   │   ├── imm_ops.asm     # IMUL imm, PUSH imm, SHL imm8
│   │   │   └── enhanced.asm    # Enhanced operations
│   │   ├── 80286/
│   │   │   ├── real.asm        # Real mode extensions
│   │   │   ├── prot_setup.asm  # Protected mode entry
│   │   │   ├── descriptors.asm # GDT, LDT, IDT
│   │   │   ├── segments.asm    # Segment protection
│   │   │   ├── gates.asm       # Call gates, task gates
│   │   │   ├── exceptions.asm  # Exception handling
│   │   │   └── loadall.asm     # Undocumented LOADALL
│   │   ├── 80386/
│   │   │   ├── 32bit.asm       # 32-bit operations
│   │   │   ├── new_insns.asm   # MOVSX, MOVZX, SETcc, etc.
│   │   │   ├── paging.asm      # Page tables, CR3, TLB
│   │   │   ├── v86.asm         # Virtual 8086 mode
│   │   │   ├── debug.asm       # Debug registers DR0-DR7
│   │   │   ├── control.asm     # CR0-CR3
│   │   │   └── test_regs.asm   # TR3-TR7 (test registers)
│   │   └── 80486/
│   │       ├── new_insns.asm   # BSWAP, XADD, CMPXCHG
│   │       ├── cache.asm       # INVD, WBINVD, cache tests
│   │       ├── cpuid.asm       # CPUID (late 486)
│   │       └── alignment.asm   # AC flag, alignment checks
│   │
│   ├── fpu/                    # FPU test modules
│   │   ├── detect.asm          # FPU detection (src/fpu/detect.asm)
│   │   ├── 8087/
│   │   │   ├── basic.asm       # FLD, FST, FXCH, etc.
│   │   │   ├── arith.asm       # FADD, FSUB, FMUL, FDIV
│   │   │   ├── compare.asm     # FCOM, FTST, FXAM
│   │   │   ├── transcend.asm   # FPTAN, FPATAN, F2XM1, etc.
│   │   │   ├── constant.asm    # FLD1, FLDPI, FLDL2E, etc.
│   │   │   ├── control.asm     # FLDCW, FSTCW, FCLEX, etc.
│   │   │   ├── exception.asm   # Exception handling
│   │   │   └── stack.asm       # Stack operations
│   │   ├── 80287/
│   │   │   └── protected.asm   # Protected mode FPU
│   │   ├── 80387/
│   │   │   ├── new_insns.asm   # FSIN, FCOS, FSINCOS, etc.
│   │   │   ├── fprem1.asm      # IEEE FPREM
│   │   │   └── fucom.asm       # Unordered compare
│   │   └── 80486/
│   │       ├── integrated.asm  # Integrated FPU tests
│   │
│   ├── peripheral/             # Peripheral test modules
│   │   ├── pic/
│   │   │   ├── 8259_single.asm # Single PIC tests
│   │   │   ├── 8259_cascade.asm# Cascaded PIC tests
│   │   │   └── 8259_modes.asm  # All PIC modes
│   │   ├── pit/
│   │   │   ├── 8254_mode0.asm  # Mode 0 - Interrupt on TC
│   │   │   ├── 8254_mode1.asm  # Mode 1 - Programmable one-shot
│   │   │   ├── 8254_mode2.asm  # Mode 2 - Rate generator
│   │   │   ├── 8254_mode3.asm  # Mode 3 - Square wave
│   │   │   ├── 8254_mode4.asm  # Mode 4 - Software triggered strobe
│   │   │   ├── 8254_mode5.asm  # Mode 5 - Hardware triggered strobe
│   │   │   └── 8254_readback.asm # Read-back command
│   │   ├── dma/
│   │   │   ├── 8237_single.asm # Single transfers
│   │   │   ├── 8237_block.asm  # Block transfers
│   │   │   ├── 8237_demand.asm # Demand transfers
│   │   │   ├── 8237_cascade.asm# Cascade mode
│   │   │   └── 8237_autoinit.asm # Auto-init
│   │   ├── kbc/
│   │   │   ├── 8042_basic.asm  # Basic commands
│   │   │   ├── 8042_a20.asm    # A20 gate control
│   │   │   └── 8042_ps2.asm    # PS/2 mouse
│   │   ├── rtc/
│   │   │   ├── mc146818_time.asm    # Time functions
│   │   │   ├── mc146818_alarm.asm   # Alarm functions
│   │   │   └── mc146818_cmos.asm    # CMOS RAM
│   │   ├── ide/
│   │   │   ├── ata_identify.asm     # IDENTIFY DEVICE
│   │   │   ├── ata_pio.asm          # PIO transfers
│   │   │   ├── ata_diag.asm         # Diagnostics
│   │   │   └── atapi_packet.asm     # ATAPI commands
│   │   ├── vga/
│   │   │   ├── vga_mode.asm         # Mode setting
│   │   │   ├── vga_seq.asm          # Sequencer
│   │   │   ├── vga_crtc.asm         # CRT controller
│   │   │   ├── vga_gc.asm           # Graphics controller
│   │   │   ├── vga_attr.asm         # Attribute controller
│   │   │   ├── vga_dac.asm          # DAC/palette
│   │   │   └── vesa.asm             # VESA BIOS
│   │   ├── sound/
│   │   │   ├── speaker.asm          # PC speaker
│   │   │   ├── adlib.asm            # OPL2
│   │   │   ├── sb_dsp.asm           # SB DSP
│   │   │   ├── sb_mixer.asm         # SB mixer
│   │   │   ├── opl3.asm             # OPL3
│   │   │   ├── gus.asm              # Gravis Ultrasound
│   │   │   └── mpu401.asm           # MIDI
│   │   └── serial/
│   │       ├── 8250.asm             # Basic UART
│   │       ├── 16550.asm            # FIFO UART
│   │       └── lpt.asm              # Parallel port
│   │
│   ├── timing/                 # Timing validation
│   │   ├── cycles.asm          # Cycle counting
│   │   ├── memory.asm          # Memory timing
│   │   ├── cache.asm           # Cache timing
│   │   └── interrupt.asm       # Interrupt latency
│   │
│   └── main.asm                # Entry point
│
├── include/
│   ├── x86.inc                 # CPU definitions
│   ├── fpu.inc                 # FPU definitions
│   ├── ports.inc               # I/O port addresses
│   ├── bios.inc                # BIOS data area
│   ├── dos.inc                 # DOS functions
│   ├── test.inc                # Test framework macros
│   └── output.inc              # Output macros
│
├── data/
│   ├── vectors/                # Test vectors
│   │   ├── singlestep/         # SingleStep integration
│   │   └── reference/          # Reference results
│   └── strings/                # Test descriptions
│
├── tools/
│   ├── gentest.py              # Test vector generator
│   ├── compare.py              # Result comparison
│   ├── analyze.py              # Failure analysis
│   └── bootimg.py              # Bootable image creator
│
├── docs/
│   ├── architecture.md         # Detailed architecture
│   ├── adding_tests.md         # How to add tests
│   ├── output_formats.md       # Output format specs
│   ├── references.md           # External references
│   └── cpu/
│       ├── 8086.md             # 8086 test documentation
│       ├── 80186.md
│       ├── 80286.md
│       ├── 80386.md
│       └── 80486.md
│
└── build/
    ├── bin/                    # Compiled binaries
    ├── obj/                    # Object files
    └── boot/                   # Bootable images
```

## 2. Core Components

### 2.1 Test Module Interface

Every test module implements a standard interface.

> **DECISION (prep-phase E2):** All pointer fields in `MODULE_HEADER` and
> `TEST_ENTRY` are **32-bit far pointers** (`seg:off`, stored as `dd`).
> This allows the runner to dispatch to modules loaded as overlays or
> residing in a different segment.  The binary struct is defined in
> [include/test.inc](../include/test.inc) as `MODULE_HEADER` /
> `MODULE_HEADER_SIZE`.

```nasm
; Module header - must be at start of each test module
MODULE_HEADER:
    dd MODULE_MAGIC         ; 'TEST' magic number
    dw MODULE_VERSION       ; Interface version
    dw MIN_GEN              ; Minimum CPU generation (CPU_8086 … CPU_80486)
    dd module_name          ; Far ptr to name string (seg:off)
    dd module_desc          ; Far ptr to description
    dd module_init          ; Far ptr to init function
    dd module_run           ; Far ptr to main test function
    dd module_cleanup       ; Far ptr to cleanup function
    dd test_count           ; Number of test cases
    dd test_table           ; Far ptr to test case table

; Test case table entry
struc TEST_CASE
    .name       resd 1      ; Test name pointer
    .func       resd 1      ; Test function pointer
    .flags      resw 1      ; Test flags
    .expected   resw 1      ; Expected duration (ms) or 0
endstruc
```

> **TERMINOLOGY DECISION (prep-phase E1):** This document previously used
> "Tier" for execution-order, colliding with the AGENTS.md `TIER` field
> (build-target: `UNIVERSAL/REALMODE/RING0/HARDWARE/TIMING`). To resolve,
> execution-order is now **Wave** (0–3) everywhere; build-target stays
> **TIER**. The two are orthogonal axes — a `UNIVERSAL` module may run in
> any Wave; a `RING0` module may also run in Wave 2.

### 2.2 CPU-Scoped Execution-Wave Strategy

To avoid running multi-hour iterations for complex edge cases (e.g., cache coherency) when foundational instructions are broken, the suite employs a graduated execution strategy. Crucially, **these waves are not a single universal block**; they are strictly scoped per CPU family and feature set.

The system uses a CPU family and feature identification router to dynamically select the isolated sets of tests applicable to the host. Within each isolated scope (e.g., 8086 Core, 80286 Protected Mode, 80387 FPU), the suite sequences tests through graduated waves:

* **Wave 0 (Smoke):** Basic CPU state validation, register integrity, and fundamental ALU ops for the specific family (e.g., simple `ADD r, r`).
* **Wave 1 (Base ISA):** Complete coverage of standard instructions, flags, and memory addressing within the identified scope.
* **Wave 2 (Complex/Protected):** Exceptions, protected mode transitions, descriptors, and segment violations (if applicable to the CPU family).
* **Wave 3 (System & Coherency):** Page faults, TLB invalidation, FPU precision, and cache coherency (if applicable).

If a lower wave fails within a specific CPU scope, the runner halts further tests for that scope (unless overridden by a `--force` flag).

> **Build-target TIER vs execution WAVE — quick reference:**
> | Axis | Name | Values | Set by | Determines |
> |------|------|--------|--------|------------|
> | Build target | **TIER** | `UNIVERSAL`/`REALMODE`/`RING0`/`HARDWARE`/`TIMING` | Module header §6.1 | Which target executables include the module (DOS-all / Linux-oracle / Win32-oracle) |
> | Execution order | **Wave** | 0–3 | Coverage-matrix per-area | When the test runs *within* a CPU scope (fail-fast ordering) |

### 2.3 Test Execution Flow

```
┌─────────────┐
│ Parse Args  │
└──────┬──────┘
       ▼
┌─────────────┐
│ Init Output │◄── Console/Serial/File
└──────┬──────┘
       ▼
┌─────────────┐
│ Detect HW   │◄── Router: Identify CPU Family & Features
└──────┬──────┘
       ▼
┌──────────────────────────────────────────────┐
│ For each identified HW scope/feature:        │
│  ┌────────────────────────────────────────┐  │
│  │ For Wave = 0 to 3:                     │  │
│  │  ┌──────────────────────────────────┐  │  │
│  │  │ Load Tests for Scope + Wave      │  │  │
│  │  └──────┬───────────────────────────┘  │  │
│  │         ▼                              │  │
│  │  ┌──────────────────────────────────┐  │  │
│  │  │ For each test module:            │  │  │
│  │  │  - module_init                   │  │  │
│  │  │  - For each test case:           │  │  │
│  │  │      Run test & Record result    │  │  │
│  │  │  - module_cleanup                │  │  │
│  │  └──────┬───────────────────────────┘  │  │
│  │         ▼                              │  │
│  │  ┌──────────────────────────────────┐  │  │
│  │  │ If Wave failed, abort this scope │  │  │
│  │  └──────────────────────────────────┘  │  │
│  └────────────────────────────────────────┘  │
└──────────────────────┬───────────────────────┘
       ▼
┌─────────────┐
│ Summary     │
└─────────────┘
```

### 2.4 Output System

```nasm
; Output configuration structure
struc OUTPUT_CONFIG
    .flags      resw 1      ; OUTPUT_CONSOLE | OUTPUT_SERIAL | OUTPUT_FILE
    .com_port   resw 1      ; COM port base (0x3F8, 0x2F8, etc.)
    .baud       resd 1      ; Baud rate
    .file_handle resw 1     ; DOS file handle
    .verbosity  resb 1      ; 0=summary, 1=normal, 2=verbose, 3=debug
    .format     resb 1      ; 0=text, 1=json, 2=csv
endstruc

; Output flags
OUTPUT_CONSOLE  equ 0x01
OUTPUT_SERIAL   equ 0x02
OUTPUT_FILE     equ 0x04
OUTPUT_ALL      equ 0x07
```

### 2.5 Result Reporting

```nasm
; Test result structure
; DECISION (prep-phase E3): expected/actual are resd (32-bit), NOT resq.
;   All 8086–486 GPR/flag values fit in 32 bits.  FPU 80-bit comparisons
;   are done via stored memory image + integer compare, not this struct.
;   Must match include/test.inc exactly.
struc TEST_RESULT
    .status     resb 1      ; PASS, FAIL, SKIP, ERROR
    .flags      resb 1      ; Additional flags
    .reserved   resw 1      ; Alignment
    .duration   resd 1      ; Execution time (timer ticks)
    .expected   resd 1      ; Expected value (32-bit)
    .actual     resd 1      ; Actual value (32-bit)
    .message    resd 1      ; Far ptr to error message string
endstruc
TEST_RESULT_SIZE equ 20

; Status codes
STATUS_PASS     equ 0
STATUS_FAIL     equ 1
STATUS_SKIP     equ 2
STATUS_ERROR    equ 3
STATUS_TIMEOUT  equ 4
```

## 3. Test Design Patterns

### 3.1 Basic Instruction Test Pattern

```nasm
; Example: Testing ADD r8, r8
test_add_r8_r8:
    PUSH_ALL
    
    ; Test case 1: Simple addition
    mov al, 0x12
    mov bl, 0x34
    add al, bl
    
    ; Verify result
    cmp al, 0x46
    jne .fail_result
    
    ; Verify FLAGS
    pushf
    pop ax
    and ax, FLAGS_ARITH_MASK  ; CF, OF, SF, ZF, AF, PF
    cmp ax, EXPECTED_FLAGS
    jne .fail_flags
    
    ; Test case 2: Overflow condition
    mov al, 0x7F
    mov bl, 0x01
    add al, bl
    
    pushf
    pop ax
    test ax, FLAG_OF
    jz .fail_overflow       ; OF should be set
    
    ; ... more test cases ...
    
    POP_ALL
    mov ax, STATUS_PASS
    ret

.fail_result:
    ; Record detailed failure info
    ; NOTE: expected/actual are resd (32-bit), message is a FAR ptr (seg:off)
    mov dword [result + TEST_RESULT.expected], 0x46
    movzx eax, al                  ; zero-extend 8-bit result into 32-bit field
    mov [result + TEST_RESULT.actual], eax
    mov word [result + TEST_RESULT.message], fail_msg_result      ; offset
    mov word [result + TEST_RESULT.message + 2], ds               ; segment
    jmp .fail

.fail_flags:
    ; ax = actual masked flags (from pushf/pop ax/and above)
    movzx ecx, ax                 ; save actual flags
    mov dword [result + TEST_RESULT.expected], EXPECTED_FLAGS
    mov [result + TEST_RESULT.actual], ecx
    mov word [result + TEST_RESULT.message], fail_msg_flags
    mov word [result + TEST_RESULT.message + 2], ds
    jmp .fail

.fail_overflow:
    mov word [result + TEST_RESULT.message], fail_msg_of
    mov word [result + TEST_RESULT.message + 2], ds
    
.fail:
    POP_ALL
    mov ax, STATUS_FAIL
    ret
```

### 3.2 FLAGS Testing Pattern

```nasm
; Comprehensive arithmetic test: executes instruction, checks BOTH result
; and flags, and records detailed failure info via RECORD_FAILURE.
;
; NOTE: This macro is named TEST_ARITH_FULL to avoid collision with the
; simpler 3-arg TEST_FLAGS in include/test.inc (which only checks FLAGS).
; The 3-arg TEST_FLAGS(expected, mask, fail_label) is the building block;
; TEST_ARITH_FULL wraps it with instruction execution + result checking.
;
; NOTE: RECORD_FAILURE takes 4 args: buf_ptr_reg, msg, expected, actual
%macro TEST_ARITH_FULL 6
    ; %1 = instruction (e.g., add)
    ; %2 = operand 1
    ; %3 = operand 2
    ; %4 = expected result
    ; %5 = expected FLAGS (masked)
    ; %6 = result buffer register (e.g., di, bx)
    
    mov ax, %2
    %1 ax, %3
    
    ; Save result and flags
    mov [temp_result], ax
    pushf
    pop word [temp_flags]
    
    ; Verify result
    cmp ax, %4
    jne %%fail_result
    
    ; Verify FLAGS
    mov ax, [temp_flags]
    and ax, FLAGS_ARITH_MASK
    cmp ax, %5
    jne %%fail_flags
    
    jmp %%pass

%%fail_result:
    RECORD_FAILURE %6, msg_result_mismatch, %4, [temp_result]
    jmp %%done
    
%%fail_flags:
    RECORD_FAILURE %6, msg_flags_mismatch, %5, ax
    jmp %%done
    
%%pass:
    inc dword [tests_passed]
    
%%done:
    inc dword [tests_total]
%endmacro
```

### 3.3 Exception Testing Pattern (Protected Mode)

```nasm
; Test that an operation generates expected exception
test_gp_fault_on_limit:
    ; Set up exception handler
    ; Install #GP handler (IDT entry 13)
    ; 386 gate format: off_lo(16) | sel(16) | 0(8) | attr(8) | off_hi(16)
    mov eax, gp_handler
    mov word [idt + 13*8 + 0], ax          ; offset low 16 bits
    mov word [idt + 13*8 + 2], CODE_SEL    ; code segment selector
    mov byte [idt + 13*8 + 4], 0           ; reserved
    mov byte [idt + 13*8 + 5], 0x8E        ; P=1, DPL=0, 386 intr gate
    shr eax, 16
    mov word [idt + 13*8 + 6], ax          ; offset high 16 bits
    
    ; Set flag to detect if handler ran
    mov byte [exception_caught], 0
    mov word [expected_exception], 13  ; GP fault
    
    ; Trigger exception - access beyond limit
    mov ax, TINY_DATA_SEL   ; Segment with limit = 0
    mov ds, ax
    mov al, [0x100]         ; Access beyond limit
    
    ; If we get here, exception didn't fire
    cmp byte [exception_caught], 1
    jne .fail_no_exception
    
    mov ax, STATUS_PASS
    ret

.fail_no_exception:
    mov word [result + TEST_RESULT.message], msg_no_exception
    mov word [result + TEST_RESULT.message + 2], ds
    mov ax, STATUS_FAIL
    ret

gp_handler:
    ; Verify we got the expected exception
    mov byte [exception_caught], 1
    
    ; Verify error code if applicable
    ; ...
    
    ; Skip the faulting instruction (32-bit PM → IRETD, dword EIP)
    add dword [esp], INSN_LEN
    iretd
```

### 3.4 FPU Testing Pattern

```nasm
; FPU test with proper exception handling
test_fdiv_precision:
    ; Clear exceptions and set precision
    fninit
    
    ; Load control word with all exceptions masked
    fldcw [cw_all_masked]
    
    ; Test case: 1.0 / 3.0
    fld dword [one]
    fld dword [three]
    fdiv st1, st0
    
    ; Check result against known value
    fld tword [expected_one_third]
    fcompp
    fstsw ax
    sahf
    jne .fail_precision
    
    ; Clear stack
    fstp st0
    
    ; Now test exception generation
    fldcw [cw_none_masked]
    fld dword [one]
    fld dword [zero]
    fdiv st1, st0           ; Should trigger ZE
    
    fstsw ax
    test ax, FPU_ZE
    jz .fail_no_exception
    
    mov ax, STATUS_PASS
    ret

.fail_precision:
    ; Record actual vs expected
    ; ...
    mov ax, STATUS_FAIL
    ret

.fail_no_exception:
    mov word [result + TEST_RESULT.message], msg_no_fpu_exception
    mov word [result + TEST_RESULT.message + 2], ds
    mov ax, STATUS_FAIL
    ret
```

### 3.5 Peripheral Testing Pattern

```nasm
; PIT Mode 2 test
test_pit_mode2:
    cli                     ; Disable interrupts during setup
    
    ; Save current PIT state
    call pit_save_state
    
    ; Configure channel 0 for mode 2, rate generator
    mov al, 00110100b       ; Chan 0, LSB/MSB, Mode 2, Binary
    out PIT_CTRL, al
    
    ; Set count to 1000
    mov al, 1000 & 0xFF
    out PIT_CH0, al
    mov al, 1000 >> 8
    out PIT_CH0, al
    
    ; Read back and verify
    mov al, 11000010b       ; Readback, chan 0, latch count
    out PIT_CTRL, al
    
    in al, PIT_CH0          ; LSB
    mov bl, al
    in al, PIT_CH0          ; MSB
    mov bh, al
    
    ; Count should be <= 1000 (it's counting down)
    cmp bx, 1000
    ja .fail_count_high
    
    ; Restore and return
    call pit_restore_state
    sti
    mov ax, STATUS_PASS
    ret

.fail_count_high:
    call pit_restore_state
    sti
    mov word [result + TEST_RESULT.message], msg_pit_count_error
    mov word [result + TEST_RESULT.message + 2], ds
    mov ax, STATUS_FAIL
    ret
```

## 4. Timing Measurement

### 4.1 High-Resolution Timer

```nasm
; Use PIT channel 2 for high-resolution timing
; Provides ~838ns resolution

timer_init:
    ; Configure PIT channel 2 for timing
    mov al, 10110100b       ; Chan 2, LSB/MSB, Mode 2
    out PIT_CTRL, al
    mov al, 0xFF
    out PIT_CH2, al
    out PIT_CH2, al
    
    ; Enable speaker gate (but not speaker)
    in al, PORT_B
    and al, 0xFC            ; Clear speaker enable and gate
    or al, 0x01             ; Enable gate only
    out PORT_B, al
    ret

timer_start:
    ; Latch current count
    mov al, 10000000b       ; Latch channel 2
    out PIT_CTRL, al
    in al, PIT_CH2
    mov bl, al
    in al, PIT_CH2
    mov bh, al
    mov [timer_start_val], bx
    ret

timer_stop:
    ; Latch current count
    mov al, 10000000b
    out PIT_CTRL, al
    in al, PIT_CH2
    mov bl, al
    in al, PIT_CH2
    mov bh, al
    
    ; Calculate elapsed (start - end, handling wrap)
    mov ax, [timer_start_val]
    sub ax, bx
    jnc .no_wrap
    add ax, 0xFFFF          ; Handle wrap
.no_wrap:
    ; AX now contains elapsed ticks
    ; Each tick = 838.095 ns at 1.193182 MHz
    ret
```

### 4.2 RDTSC for Modern Testing

> **Generation gating note:** RDTSC exists from the **486DX** (CPUID feature
> bit EDX[4]); however, **CPUID itself** appears only on later 486 steppings.
> On an early 486 (or 486SX) without CPUID, the TSC feature bit cannot be
> queried via CPUID — the test must fall back gracefully to PIT ch2 rather
> than #UD on a missing CPUID.  The detection guard must distinguish:
> 1. CPUID present?  (EFLAGS.ID toggle)
> 2. If yes, TSC bit set?  (CPUID leaf 1 EDX[4])
> 3. If no CPUID, assume TSC unavailable and use PIT.

```nasm
; Use RDTSC if available (486DX+ with CPUID feature bit, or Pentium+)
timer_rdtsc_start:
    ; Check if RDTSC available (CPUID required)
    pushfd
    pop eax
    mov ebx, eax
    xor eax, 1 << 21        ; Toggle CPUID bit
    push eax
    popfd
    pushfd
    pop eax
    cmp eax, ebx
    je .no_cpuid
    
    mov eax, 1
    cpuid
    test edx, 1 << 4        ; TSC feature bit
    jz .no_rdtsc
    
    rdtsc
    mov [tsc_start_lo], eax
    mov [tsc_start_hi], edx
    ret

.no_cpuid:
.no_rdtsc:
    ; Fall back to PIT
    jmp timer_start
```

## 5. Integration with External Test Vectors

### 5.1 SingleStep Format Support

```python
# tools/import_singlestep.py
# Converts SingleStep JSON test vectors to our format

import json

def convert_singlestep(input_file, output_dir):
    with open(input_file) as f:
        tests = json.load(f)
    
    for test in tests:
        # Extract initial state
        initial_regs = test['initial']['regs']
        initial_mem = test['initial']['mem']
        
        # Extract expected final state
        final_regs = test['final']['regs']
        final_mem = test['final']['mem']
        
        # Generate NASM test case
        generate_test_case(test['name'], 
                          initial_regs, initial_mem,
                          final_regs, final_mem,
                          test['bytes'])
```

### 5.2 Reference Result Format

```json
{
  "format_version": 1,
  "cpu_type": "80486DX-33",
  "platform": "real_hardware",
  "date": "2024-01-15",
  "tests": [
    {
      "module": "8086.arith.add",
      "case": "add_al_bl_overflow",
      "initial": {
        "AL": "0x7F",
        "BL": "0x01",
        "FLAGS": "0x0000"
      },
      "final": {
        "AL": "0x80",
        "FLAGS": "0x0894"
      },
      "cycles": 3
    }
  ]
}
```

## 6. Build System

### 6.1 Makefile Structure

```makefile
# Master Makefile

NASM = nasm
NASMFLAGS = -f obj -Iinclude/
LD = wlink  # or TLINK, MS LINK

# Directories
SRC = src
BUILD = build
BIN = $(BUILD)/bin
OBJ = $(BUILD)/obj

# Core modules (always included)
CORE_OBJS = \
    $(OBJ)/runner.obj \
    $(OBJ)/output.obj \
    $(OBJ)/config.obj \
    $(OBJ)/memory.obj \
    $(OBJ)/timing.obj

# CPU test modules
CPU_8086_OBJS = \
    $(OBJ)/cpu/8086/arith.obj \
    $(OBJ)/cpu/8086/logic.obj \
    $(OBJ)/cpu/8086/shift.obj \
    # ...

# Default target
all: $(BIN)/x86val.exe

# Main executable
$(BIN)/x86val.exe: $(CORE_OBJS) $(CPU_8086_OBJS) $(OBJ)/main.obj
    $(LD) @link.rsp

# Pattern rule for assembly
$(OBJ)/%.obj: $(SRC)/%.asm
    @mkdir -p $(dir $@)
    $(NASM) $(NASMFLAGS) -o $@ $<

# Individual module builds for testing
cpu-8086: $(CPU_8086_OBJS)
    # Build 8086 tests only

# Clean
clean:
    rm -rf $(BUILD)

# Bootable image
boot: all
    python3 tools/bootimg.py $(BIN)/x86val.exe $(BUILD)/boot/x86val.img
```

## 7. References and Resources

### 7.1 Official Documentation

| Document | Description | Source |
|----------|-------------|--------|
| Intel 8086 Family User's Manual | Original 8086/88 reference | Intel 1979 |
| iAPX 286 Programmer's Reference | Protected mode intro | Intel 1983 |
| 80386 Programmer's Reference Manual | 32-bit, paging | Intel 1986 |
| i486 Processor Programmer's Reference | Cache, BSWAP, etc | Intel 1990 |
| Intel 64 and IA-32 Architectures SDM | Modern canonical reference | Intel current |

### 7.2 Existing Test Suites

| Project | URL | Notes |
|---------|-----|-------|
| SingleStep Tests | https://github.com/SingleStepTests/8088 | Per-instruction vectors |
| test386.asm | PCjs project | Protected mode |
| CPU test | https://github.com/barotto/cpu_test | 8088 focus |
| Paranoia | Classic | FPU precision |
| nasm-test | Various | Assembler tests |

### 7.3 Emulator Projects (for cross-validation)

| Emulator | Focus | URL |
|----------|-------|-----|
| ao486 | FPGA accuracy | MiSTer project |
| DOSBox-X | Compatibility | https://dosbox-x.com |
| 86Box | Accuracy | https://86box.net |
| PCem | Cycle accuracy | https://pcem-emulator.co.uk |
| MartyPC | 8088 accuracy | https://github.com/dbalsom/martypc |
| MAME PC | Historical | MAME project |

### 7.4 Hardware Documentation

| Chip | Description | Datasheet |
|------|-------------|-----------|
| 8259A | PIC | Intel |
| 8254 | PIT | Intel |
| 8237A | DMA | Intel |
| 8042 | KBC | Various |
| MC146818 | RTC | Motorola |
| ATA/ATAPI | Storage | T13 specs |
| VGA | Video | IBM, various |
| OPL3 | FM Synth | Yamaha YMF262 |
| SB16 | Sound | Creative |
| GUS | Sound | Gravis |
| 16550 | UART | TI |

### 7.5 Undocumented Behavior References

| Resource | Content |
|----------|---------|
| "Undocumented PC" (Frank van Gilluwe) | BIOS, hardware |
| "Undocumented DOS" (Andrew Schulman) | DOS internals |
| "PC Interrupts" (Ralf Brown) | Interrupt list |
| x86 documentation project | CPU errata |
| bochs mailing list archives | Emulation edge cases |
| DOSEMU documentation | DOS emulation issues |

## 8. Appendix: Test Case Counts (Estimated)

> **NOTE:** These estimates are approximate and pre-implementation.
> The authoritative accounting lives in
> [coverage-matrix.md](coverage-matrix.md) §12 (~18,500 guest-implementable).
> This table is retained for historical granularity per-module.  If the
> two disagree, coverage-matrix §12 wins.

| Module | Test Cases | Notes |
|--------|-----------|-------|
| 8086 Arithmetic | 2,000 | All operand combinations |
| 8086 Logic | 1,500 | |
| 8086 Shift | 1,000 | All shift counts |
| 8086 String | 500 | REP combinations |
| 8086 Control | 300 | Branches, calls |
| 8086 FLAGS | 1,000 | Edge cases |
| 8086 Segment | 200 | |
| 8086 Misc | 100 | |
| 8086 BCD/Encoding | 400 | Golden flags, undocumented opcodes |
| 80186 New | 400 | |
| 80286 Protected | 2,000 | Descriptors, exceptions, gates |
| 80386 32-bit | 3,000 | |
| 80386 Paging | 500 | |
| 80386 V86 | 300 | |
| 80386 Debug/CR/TR | 700 | DR0-7, CR0-3, TR3-7 |
| 80486 New | 400 | |
| 80486 Cache | 200 | |
| 80486 CPUID/#AC | 200 | |
| FPU 8087 | 2,000 | All operations |
| FPU 80387 | 500 | New instructions |
| FPU Edge cases | 1,500 | Denormals, NaN, specials |
| Peripherals (all) | 1,500 | PIC/PIT/DMA/KBC/RTC/IDE/VGA/Sound/UART |
| System Integration | 600 | A20, mode transitions, int boundaries |
| Timing (bands) | 150 | Ratios, never hard-fail |
| **Total** | **~18,500** | see coverage-matrix §12 |
