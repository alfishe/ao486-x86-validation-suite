# x86 Validation Suite - Product Requirements Document

## Executive Summary

A comprehensive, modular test suite for validating x86 CPU implementations from 8086 through 80486, targeting FPGA cores (ao486), software emulators, and real hardware. Designed for correctness validation, timing verification, and peripheral compatibility testing.

## Problem Statement

### Current Gaps

1. **No comprehensive open-source x86 validation suite** exists that covers the full ISA progression from 8086 to 486
2. **Emulator testing is fragmented** - each project creates ad-hoc tests
3. **486TEST and similar tools are misleading** - they test marketing features, not actual CPU coverage (see: our 486TEST reverse engineering findings)
4. **Timing validation is nearly non-existent** in available test suites
5. **Peripheral testing** is scattered across different tools with no unified framework

### Target Users

- FPGA core developers (MiSTer ao486, MAME, etc.)
- Software emulator developers (DOSBox, 86Box, PCem, QEMU, MartyPC)
- Vintage hardware collectors verifying authentic operation
- Educational/research users studying x86 architecture

## Goals

### Primary Goals

1. **Complete ISA coverage** for 8086, 8087, 80186, 80286, 80287, 80386, 80387, 80486
2. **Modular test architecture** - each test group independently runnable
3. **Detailed failure reporting** - not just pass/fail, but WHY it failed
4. **Cross-platform output** - console, serial port, file logging
5. **Real hardware + emulator compatible** - runs on anything that boots DOS

### Secondary Goals

1. **Bootable standalone image** for pre-DOS testing
2. **Timing validation suites** for cycle-accurate implementations
3. **Integration with existing test vectors** (SingleStep, etc.)
4. **Automated regression testing** support

## Scope

### In Scope - Phase 1 (MVP)

| Category | Components |
|----------|------------|
| CPU 8086/88 | All instructions, FLAGS, addressing modes, prefixes |
| CPU 80186/88 | New instructions (ENTER, LEAVE, BOUND, INS, OUTS, etc.) |
| CPU 80286 | Protected mode, descriptors, exceptions, LOADALL |
| CPU 80386 | 32-bit ops, paging, V86 mode, debug registers |
| CPU 80486 | BSWAP, XADD, CMPXCHG, INVD, WBINVD, cache, CPUID |
| FPU 8087 | All x87 instructions, exceptions, precision modes |
| FPU 80287 | Protected mode integration |
| FPU 80387 | New instructions (FSIN, FCOS, etc.) |
| FPU 80486 | Integrated FPU (FCMOV/FCOMI are P6+ — **removed from 486 scope**, see note below) |

### In Scope - Phase 2

| Category | Components |
|----------|------------|
| Interrupt Controller | 8259A PIC - ICW/OCW, cascading, edge/level |
| Timer | 8254 PIT - all modes, read-back, gate control |
| DMA Controller | 8237A - all modes, cascade, auto-init |
| Keyboard Controller | 8042 - commands, A20 gate, PS/2 |
| RTC/CMOS | MC146818 - time, alarm, CMOS RAM |

### In Scope - Phase 3

| Category | Components |
|----------|------------|
| Storage | IDE/ATA - PIO modes, identify, CHS/LBA |
| Storage | ATAPI - packet commands, CD-ROM |
| Video | VGA - modes, registers, BIOS |
| Video | SVGA - VESA modes, linear framebuffer |
| Sound | PC Speaker - timer-based |
| Sound | AdLib/OPL2 - FM synthesis |
| Sound | Sound Blaster - DSP, DMA |
| Sound | OPL3 - 4-op FM |
| Sound | Gravis Ultrasound - RAM, voices |
| Sound | MPU-401 MIDI |
| Serial | 8250/16550 UART |
| Parallel | Centronics LPT |

### Out of Scope (Future)

- Pentium and later CPUs
- PCI bus testing
- USB (too modern for target era)
- Network cards
- SCSI controllers

> **Erratum (prep-phase §D):** FCMOV and FCOMI were previously listed under
> 80486 FPU scope. These instructions are **Pentium Pro (P6) and later** —
> they #UD on all 486 steppings and on the ao486 core. They have been
> **removed from 486 scope**. If desired in the future, they must be
> generation-gated to SKIP on anything below P6 and are out of scope for
> this suite's 8086–486 coverage target.

## Requirements

### Functional Requirements

#### FR-1: Test Execution Framework

```
FR-1.1: Tests organized as independent modules loadable at runtime
FR-1.2: Command-line interface for test selection
FR-1.3: Batch execution mode for running test groups
FR-1.4: Skip/continue on failure option
FR-1.5: Random execution order option (for timing issues)
FR-1.6: Graduated execution waves (Fail-fast: Smoke -> ALU -> Complex -> System)
```

#### FR-2: Output System

```
FR-2.1: Console output (80x25 text mode)
FR-2.2: Serial port output (configurable baud rate)
FR-2.3: File output (append to log file)
FR-2.4: Multiple outputs simultaneously
FR-2.5: Verbosity levels (summary, detailed, debug)
FR-2.6: Machine-readable format option (JSON/CSV)
```

#### FR-3: CPU Tests

```
FR-3.1: Each instruction tested with multiple operand combinations
FR-3.2: All addressing modes tested per instruction
FR-3.3: FLAGS behavior verified for each operation
FR-3.4: Segment override prefixes tested
FR-3.5: REP prefixes tested with all string operations
FR-3.6: Exception conditions deliberately triggered and verified
FR-3.7: Undefined/undocumented behavior documented and tested
```

#### FR-4: FPU Tests

```
FR-4.1: All x87 instructions tested
FR-4.2: Precision modes (single, double, extended)
FR-4.3: Rounding modes (nearest, down, up, truncate)
FR-4.4: Exception handling (all 6 exception types)
FR-4.5: Stack overflow/underflow
FR-4.6: Denormals, infinities, NaNs
FR-4.7: CPU-FPU synchronization (WAIT behavior)
```

#### FR-5: Timing Tests

```
FR-5.1: Instruction cycle count measurement
FR-5.2: Memory access timing (cached vs uncached)
FR-5.3: Interrupt latency measurement
FR-5.4: DMA timing validation
FR-5.5: PIT-based high-resolution timing
```

#### FR-6: Peripheral Tests

```
FR-6.1: Register read/write verification
FR-6.2: Interrupt generation and handling
FR-6.3: DMA transfer verification
FR-6.4: Mode switching tests
FR-6.5: Error condition handling
```

### Non-Functional Requirements

```
NFR-1: All tests runnable from MS-DOS 3.3+
NFR-2: No external dependencies (self-contained)
NFR-3: Memory footprint < 256KB conventional
NFR-4: Tests must not corrupt system state
NFR-5: Clean abort on Ctrl+C/Ctrl+Break
NFR-6: Source code in NASM (portable assembly)
NFR-7: Each test module < 64KB
NFR-8: Test execution time configurable (quick vs thorough)
```

## User Stories

### US-1: FPGA Developer

> As an ao486 core developer, I want to run a comprehensive 486 test suite so that I can verify my implementation handles all documented instructions correctly.

**Acceptance Criteria:**
- Can run tests on ao486 via MiSTer DOS boot
- Clear report of which instructions/features pass/fail
- Detailed information about failures to aid debugging

### US-2: Emulator Developer

> As a DOSBox developer, I want to compare my emulation against real hardware results so that I can identify accuracy issues.

**Acceptance Criteria:**
- Same tests produce same results on real hardware
- Machine-readable output for automated comparison
- Tests cover edge cases not exercised by games

### US-3: Hardware Collector

> As a vintage PC collector, I want to verify my 486 is functioning correctly after 30 years so that I can trust it for running period software.

**Acceptance Criteria:**
- Clear PASS/FAIL per subsystem
- Identifies specific failing components
- Non-destructive testing

### US-4: Researcher

> As a computer architecture student, I want to understand x86 behavior at a deep level so that I can learn how CPUs really work.

**Acceptance Criteria:**
- Well-documented test cases with expected behavior
- References to official documentation
- Educational comments in source code

## Success Metrics

| Metric | Target |
|--------|--------|
| ISA coverage (8086-486) | 100% of documented instructions |
| Test count | 10,000+ individual test cases |
| Platform compatibility | ao486, DOSBox, 86Box, PCem, real HW |
| Community adoption | Used by 3+ major emulator projects |
| Documentation | Every test has rationale documented |

## Milestones

### M1: Foundation (4 weeks)
- Test framework core
- Output system
- 8086 instruction tests (complete)
- Build system

### M2: FPU & Extended CPU (4 weeks)
- 8087 tests (complete)
- 80186 extensions
- 80286 real mode + protected mode intro

### M3: 32-bit Era (6 weeks)
- 80286 protected mode (complete)
- 80386 (complete)
- 80387 (complete)

### M4: 486 & Peripherals (6 weeks)
- 80486 (complete)
- PIC, PIT, DMA, KBC
- RTC/CMOS

### M5: Storage & Video (4 weeks)
- IDE/ATA/ATAPI
- VGA/SVGA

### M6: Sound & I/O (4 weeks)
- All sound cards
- Serial/Parallel

### M7: Timing & Polish (4 weeks)
- Timing validation suites
- Integration with external test vectors
- Bootable image

## Risks

| Risk | Mitigation |
|------|------------|
| Undocumented CPU behavior varies | Document and flag vendor differences |
| Real hardware increasingly rare | Establish reference results early |
| Scope creep | Strict phase boundaries |
| NASM limitations | Design for future C migration |

## References

### Existing Test Suites (to integrate/reference)

| Project | URL | Value |
|---------|-----|-------|
| **ZXALL** | https://github.com/SingleStepTests/ZXALL | Guest-side compatibility tests |
| **SingleStepTests** | https://github.com/SingleStepTests | Instruction-level test vectors |
| test386.asm | PCjs repository | Protected mode tests |
| cpu_test | https://github.com/barotto/cpu_test | 8088/8086 tests |
| Paranoia | Classic FPU test | FPU accuracy |
| CPUID tools | Various | Detection reference |

### Verification Methodology Integration

**ZXALL (Guest-Side Testing)**
- Primary methodology for our test framework
- Tests execute natively inside target environment (DOS on emulator/FPGA)
- Catches real-world issues: peripheral interaction, timing, memory-mapped I/O
- No external tooling required during test execution
- Results directly comparable between real hardware and emulation

**SingleStepTests (Co-Simulation / HDL Verification)**
- Exhaustive per-instruction test vectors with full CPU state
- Primary use: Verilator/Icarus co-simulation for RTL verification
- Secondary use: Import vectors for guest-side validation of edge cases
- Covers instruction encoding variations, undocumented behavior, FLAGS edge cases

**Our Hybrid Approach**
```
┌────────────────────────────────────────────────────────────────┐
│                    Verification Pipeline                        │
├────────────────────────────────────────────────────────────────┤
│                                                                 │
│   ┌─────────────────┐              ┌─────────────────┐         │
│   │  SingleStepTests │              │     ZXALL       │         │
│   │     Vectors      │              │   Methodology   │         │
│   └────────┬────────┘              └────────┬────────┘         │
│            │                                 │                  │
│            ▼                                 ▼                  │
│   ┌─────────────────┐              ┌─────────────────┐         │
│   │   Co-Simulation │              │  x86-validation │         │
│   │   (Verilator)   │              │  (Guest-Side)   │         │
│   │   RTL-level     │              │   DOS-based     │         │
│   └────────┬────────┘              └────────┬────────┘         │
│            │                                 │                  │
│            └──────────────┬─────────────────┘                  │
│                           ▼                                     │
│                  ┌─────────────────┐                           │
│                  │ Cross-Validate  │                           │
│                  │ Compare Results │                           │
│                  │ Find Gaps       │                           │
│                  └─────────────────┘                           │
│                                                                 │
└────────────────────────────────────────────────────────────────┘
```

**Integration Tasks**
1. Adopt ZXALL test structure and result reporting format
2. Build SingleStepTests vector importer (`tools/import_singlestep.py`)
3. Generate guest-compatible tests from SingleStepTests where feasible
4. Cross-validate results to catch methodology-specific blind spots
5. Feed discovered issues back to both projects

### Documentation Sources

| Document | Source |
|----------|--------|
| 8086/88 User's Manual | Intel 1979 |
| 80286 Programmer's Reference | Intel 1987 |
| 80386 Programmer's Reference | Intel 1986 |
| 80486 Programmer's Reference | Intel 1990 |
| x87 Programmer's Manual | Intel |
| Undocumented features | Various reverse engineering |

### Related Projects

| Project | Relevance |
|---------|-----------|
| ao486 | Primary FPGA target |
| MiSTer FPGA | Platform |
| DOSBox-X | Reference emulator |
| 86Box | Accuracy-focused emulator |
| PCem | Cycle-accurate emulator |
| MartyPC | 8088 emulator |

## Appendix A: Test Categories

```
cpu/
├── 8086/
│   ├── arithmetic/     # ADD, SUB, MUL, DIV, etc.
│   ├── logic/          # AND, OR, XOR, NOT, etc.
│   ├── shift/          # SHL, SHR, ROL, ROR, etc.
│   ├── string/         # MOVS, STOS, CMPS, SCAS, LODS
│   ├── control/        # JMP, CALL, RET, INT, etc.
│   ├── flags/          # Carry, overflow, sign, etc.
│   ├── segment/        # Segment registers, overrides
│   ├── stack/          # PUSH, POP, stack operations
│   └── misc/           # NOP, HLT, WAIT, etc.
├── 80186/
│   ├── new_insns/      # ENTER, LEAVE, BOUND, etc.
│   └── enhanced/       # Immediate MUL, shifts, etc.
├── 80286/
│   ├── real/           # Real mode extensions
│   └── protected/      # Descriptors, gates, etc.
├── 80386/
│   ├── 32bit/          # 32-bit operations
│   ├── paging/         # Page tables, TLB
│   ├── v86/            # Virtual 8086 mode
│   └── debug/          # Debug registers
└── 80486/
    ├── new_insns/      # BSWAP, XADD, CMPXCHG
    ├── cache/          # INVD, WBINVD
    └── cpuid/          # CPU identification

fpu/
├── 8087/
├── 80287/
├── 80387/
└── 80486/

peripheral/
├── pic/                # 8259A
├── pit/                # 8254
├── dma/                # 8237A
├── kbc/                # 8042
├── rtc/                # MC146818
├── ide/                # ATA/ATAPI
├── vga/                # Video
├── sound/              # Audio devices
└── serial/             # UART
```

## Appendix B: Output Format Examples

### Console Output (Verbose)
```
x86-validate v1.0 - CPU Validation Suite
========================================

[8086] Arithmetic Tests
-----------------------
  ADD r8,r8    .......... PASS (256 cases)
  ADD r16,r16  .......... PASS (256 cases)
  ADD r8,m8    .......... PASS (256 cases)
  ADD r8,imm8  .......... PASS (256 cases)
  ADC r8,r8    .......... PASS (256 cases, CF=0)
  ADC r8,r8    .......... PASS (256 cases, CF=1)
  
  SUB r8,r8    .....X.... FAIL
    Case: SUB AL,BL where AL=0x80, BL=0x01
    Expected: AL=0x7F, CF=0, OF=1, SF=0, ZF=0
    Got:      AL=0x7F, CF=0, OF=0, SF=0, ZF=0
    Issue: Overflow flag not set on sign change
```

### Machine-Readable Output (JSON)
```json
{
  "suite": "x86-validate",
  "version": "1.0",
  "timestamp": "1992-01-15T14:30:00",
  "platform": {
    "cpu": "80486DX",
    "clock": "33MHz",
    "fpu": "integrated"
  },
  "results": [
    {
      "test": "8086.arithmetic.sub",
      "status": "FAIL",
      "cases_total": 256,
      "cases_passed": 250,
      "failures": [
        {
          "case": "SUB AL,BL",
          "operands": {"AL": "0x80", "BL": "0x01"},
          "expected": {"AL": "0x7F", "FLAGS": "0x0812"},
          "actual": {"AL": "0x7F", "FLAGS": "0x0012"},
          "issue": "OF not set"
        }
      ]
    }
  ]
}
```
