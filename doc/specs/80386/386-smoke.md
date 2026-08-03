# Spec: 80386 Smoke Test (CPU Detection)

## Metadata
- **Source file:** `src/cpu/80386/smoke.asm`
- **TIER:** UNIVERSAL | VENUE: G | GEN: 80386+ | ORACLE: manual
- **Impl-plan:** Phase 1, Level 0
- **Coverage:** [§7](../../coverage-matrix.md#7-cpu--80386-pri-1-32-bit--paging--v86)

## Purpose

Detect 80386+ CPU presence. The 386 introduced 32-bit registers and EFLAGS.
Detection uses the fact that bits 12-13 (IOPL) can be modified in protected
mode on 386+, or by checking if 32-bit register operations work.

## Detection Methods

### Method 1: 32-bit register test
```nasm
; Try to use EAX (32-bit register)
; On 286, the 0x66 prefix is ignored or causes issues
    db 0x66             ; operand size prefix
    mov ax, 0x1234      ; becomes MOV EAX, ... on 386+
```

### Method 2: EFLAGS bit 18 (AC) — actually 486 detection
See 486-smoke.md for AC bit test.

### Method 3: Try BSF/BSR (386+ instruction)
```nasm
    mov ax, 0x0001
    bsf bx, ax          ; 0F BC — #UD on 286, works on 386+
```

## Test Cases

| # | Test | 286 result | 386+ result | Detection |
|---|------|------------|-------------|-----------|
| 1 | BSF instruction | #UD (INT 6) | BX = 0 | 386+ if no fault |
| 2 | MOVZX instruction | #UD (INT 6) | executes | 386+ if no fault |
| 3 | 32-bit MOV | truncated/ignored | full 32-bit | 386+ |

## Pre/Post State

### BSF detection
```
PRE (real mode):
  INT 6 handler installed → sets detection flag = 0 (286)
  Detection flag = 1 (assume 386+)
  AX = 0x0001

OP:  BSF BX, AX         ; 0F BC D8

POST (286):
  INT 6 triggered → handler sets flag = 0
  Detection flag = 0 → CPU is 286

POST (386+):
  No exception
  BX = 0 (bit 0 is first set bit)
  Detection flag = 1 → CPU is 386+
```

### MOVZX detection
```
PRE (real mode):
  INT 6 handler installed
  AL = 0x80

OP:  MOVZX BX, AL       ; 0F B6 D8

POST (286):
  INT 6 triggered → CPU is 286

POST (386+):
  BX = 0x0080 (zero-extended)
  → CPU is 386+
```

## Pass/Fail Criteria

- **PASS:** detection method correctly identifies CPU as 286 vs 386+
- **FAIL:** misdetection
- **SKIP:** never (this is the gate for all 386+ tests)

## Known Divergences

- **386SX vs 386DX:** both detected as 386+; external bus width differs but
  instruction set is identical.
- **386 vs 486:** both pass these tests; use 486-smoke.md for further distinction.
