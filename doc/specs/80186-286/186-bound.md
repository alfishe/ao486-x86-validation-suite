# Spec: 80186 BOUND Instruction

## Metadata
- **Source file:** `src/cpu/80186/bound.asm`
- **TIER:** UNIVERSAL | VENUE: G+H | GEN: 80186+ | ORACLE: manual
- **Impl-plan:** Phase 4, area `186-BOUND`
- **Coverage:** [§5](../../coverage-matrix.md#5-cpu--80186-pri-3-thin-layer)

## Purpose

Verify BOUND instruction: array bounds checking with #BR exception on violation.
Tests signed comparison semantics, 16-bit and 32-bit forms, and exception handling.

## Prerequisites

- #BR (INT 5) exception handler installed
- Memory area for bounds pair

## Instruction Format

```
BOUND r16, m16&16     ; 62 /r — check r16 against [m]:lower, [m+2]:upper
BOUND r32, m32&32     ; 62 /r — check r32 against [m]:lower, [m+4]:upper (386+)
```

The bounds are **signed** integers: lower ≤ index ≤ upper (inclusive).

## Test Cases

### 16-bit BOUND — in range

| # | Index (reg) | Lower | Upper | Expected | Notes |
|---|:-----------:|:-----:|:-----:|----------|-------|
| 1 | 0x0000 | 0x0000 | 0x000A | OK | at lower bound |
| 2 | 0x000A | 0x0000 | 0x000A | OK | at upper bound |
| 3 | 0x0005 | 0x0000 | 0x000A | OK | in middle |
| 4 | 0xFFFF (-1) | 0xFFF0 (-16) | 0xFFFF (-1) | OK | negative range |
| 5 | 0x8000 | 0x8000 | 0x8010 | OK | around INT_MIN |

### 16-bit BOUND — out of range (#BR)

| # | Index (reg) | Lower | Upper | Expected | Notes |
|---|:-----------:|:-----:|:-----:|----------|-------|
| 1 | 0x000B | 0x0000 | 0x000A | #BR | above upper |
| 2 | 0xFFFF (-1) | 0x0000 | 0x000A | #BR | below lower (signed) |
| 3 | 0x7FFF | 0x8000 | 0x8010 | #BR | positive > negative upper |
| 4 | 0x8000 | 0x0000 | 0x7FFF | #BR | INT_MIN < 0 |

### 32-bit BOUND (386+)

| # | Index (EAX) | Lower | Upper | Expected | Notes |
|---|:-----------:|:-----:|:-----:|----------|-------|
| 1 | 0x00000000 | 0x00000000 | 0x0000FFFF | OK | |
| 2 | 0x00010000 | 0x00000000 | 0x0000FFFF | #BR | |
| 3 | 0x80000000 | 0x80000000 | 0xFFFFFFFF | OK | negative range |
| 4 | 0x7FFFFFFF | 0x80000000 | 0xFFFFFFFF | #BR | positive in negative range |

### Signed comparison semantics

The bounds check uses **signed** comparison:
- 0x8000 (−32768) is LESS than 0x0000 (0)
- 0xFFFF (−1) is LESS than 0x0000 (0)
- 0x7FFF (+32767) is GREATER than 0x0000 (0)

| # | Index | Lower | Upper | Signed interpretation | Expected |
|---|:-----:|:-----:|:-----:|:---------------------:|----------|
| 1 | 0x0000 | 0xFFFF | 0x0001 | 0 in [-1, +1] | OK |
| 2 | 0xFFFE | 0xFFFF | 0x0001 | -2 in [-1, +1] | #BR |
| 3 | 0x0002 | 0xFFFF | 0x0001 | +2 in [-1, +1] | #BR |

### Edge cases

| # | Test | Index | Lower | Upper | Expected | Notes |
|---|------|:-----:|:-----:|:-----:|----------|-------|
| 1 | Empty range | 0x0005 | 0x000A | 0x0005 | #BR | lower > upper |
| 2 | Single value | 0x0005 | 0x0005 | 0x0005 | OK | index == lower == upper |
| 3 | Max range | 0x0000 | 0x8000 | 0x7FFF | OK | full signed range |

## #BR Exception Details

When BOUND fails:
1. #BR (INT 5) is raised
2. Return address pushed = address of BOUND instruction (not next instruction)
3. No error code pushed

| # | Verify | Expected |
|---|--------|----------|
| 1 | Return CS:IP | Points to BOUND instruction |
| 2 | Error code | None (unlike #GP) |
| 3 | Index register | Unchanged |

## Pre/Post State

### BOUND — in range (no exception)

```
PRE:
  AX = 0x0005              (array index = 5)
  [DS:0x1000] = 0x0000     (lower bound = 0)
  [DS:0x1002] = 0x000A     (upper bound = 10)

  OP:  BOUND AX, [0x1000]

POST:
  No exception             (0 ≤ 5 ≤ 10)
  AX = 0x0005              (unchanged)
  Execution continues at next instruction
```

### BOUND — above upper bound (#BR)

```
PRE:
  AX = 0x000B              (index = 11)
  [DS:0x1000] = 0x0000     (lower = 0)
  [DS:0x1002] = 0x000A     (upper = 10)
  #BR handler installed at IVT[5]

  OP:  BOUND AX, [0x1000]  (at address 0x0200)

POST:
  #BR exception raised
  [SS:SP] = 0x0200         ← return IP = BOUND instruction address
  [SS:SP+2] = CS           ← return CS
  [SS:SP+4] = FLAGS        ← saved FLAGS
  Execution transfers to #BR handler
```

### BOUND — negative index below positive lower (#BR)

```
PRE:
  AX = 0xFFFF              (index = -1 signed)
  [DS:0x1000] = 0x0000     (lower = 0)
  [DS:0x1002] = 0x000A     (upper = 10)

  OP:  BOUND AX, [0x1000]

POST:
  #BR exception            (-1 < 0, below lower bound)
```

### BOUND — negative range (valid)

```
PRE:
  AX = 0xFFF8              (index = -8)
  [DS:0x1000] = 0xFFF0     (lower = -16)
  [DS:0x1002] = 0x0000     (upper = 0)

  OP:  BOUND AX, [0x1000]

POST:
  No exception             (-16 ≤ -8 ≤ 0)
```

### 32-bit BOUND (386+)

```
PRE:
  EAX = 0x00001000         (index = 4096)
  [DS:0x2000] = 0x00000000 (lower = 0)
  [DS:0x2004] = 0x00000FFF (upper = 4095)

  OP:  BOUND EAX, [0x2000]

POST:
  #BR exception            (4096 > 4095)
```

## Handler Verification

```nasm
; Install #BR handler
br_handler:
    ; Verify return address points to BOUND instruction
    mov bp, sp
    mov ax, [bp]           ; return IP
    cmp ax, bound_insn_addr
    jne .fail
    
    ; Skip the BOUND instruction (typically 2-4 bytes)
    add word [bp], BOUND_INSN_LEN
    iret

.fail:
    ; Record failure
    ...
```

## Flags

BOUND does **not** modify any flags (unless #BR occurs, which pushes FLAGS).

## State Save/Restore

- **Save:** index register, memory bounds area, IVT[5] (or IDT entry)
- **Restore:** all above

## Known Divergences

| Behavior | 80186 | 286 | 386+ |
|----------|-------|-----|------|
| 32-bit form | N/A | N/A | BOUND EAX, m32&32 |
| #BR in PM | N/A | vector 5 | vector 5 |

## Pass/Fail Criteria

- **PASS:** no #BR when in range; #BR with correct return address when out of range
- **FAIL:** #BR when in range; no #BR when out of range; wrong return address
- **SKIP:** GEN < 80186
