# Spec: FPU Save/Restore (FSAVE/FRSTOR)

## Metadata
- **Source file:** `src/fpu/8087/save.asm`
- **TIER:** UNIVERSAL | VENUE: G+H | GEN: 8086+ | ORACLE: manual
- **Impl-plan:** Phase 3, area `FPU-Save`
- **Coverage:** [§4.7](../../coverage-matrix.md#47-hard-cases--exception-delivery-and-fsavefrstor)
- **Detail:** [prep-analysis §10](../../prep-analysis.md#10-fpu-state-image-format-detail)

## Purpose

Verify FSAVE/FNSAVE/FRSTOR — state image format per generation, 94 vs 108
byte layout, and that FRSTOR restores exact state including tag word.

## State Image Formats

### 8087/287 — 94 bytes (16-bit PM/RM)

```
Offset  Size  Field
0       2     Control Word
2       2     Status Word
4       2     Tag Word
6       2     FIP (instruction pointer offset)
8       2     FCS (IP selector)
10      2     FDP (data pointer offset)
12      2     FDS (data pointer selector)
14      80    ST(0)..ST(7) (10 bytes each)
= 94 bytes total
```

### 386+ — 108 bytes (32-bit or 16-bit)

```
Offset  Size  Field
0       2     Control Word
2       2     (reserved)
4       2     Status Word
6       2     (reserved)
8       2     Tag Word
10      2     (reserved)
12      4     FIP (instruction pointer offset, 32-bit)
16      2     FCS (IP selector)
18      2     opcode
20      4     FDP (data pointer offset, 32-bit)
24      2     FDS (data pointer selector)
26      2     (reserved)
28      80    ST(0)..ST(7) (10 bytes each)
= 108 bytes total
```

## Test Cases

### FSAVE zeroes the FPU state

| # | Action | Expected | Notes |
|---|--------|----------|-------|
| 1 | FSAVE [buf] | FPU state cleared, stack empty, CW=0x0040 | CW after FSAVE = 0x0040 (all masks clear) |

> **Critical:** FSAVE initializes the FPU. After FSAVE, TOP=0 (empty stack),
> all registers tagged empty, CW=0x0040, SW=0x0000.

### FRSTOR restores exact state

| # | Pre-state | FSAVE | Modify buffer | FRSTOR | Expected |
|---|-----------|-------|---------------|--------|----------|
| 1 | ST(0)=3.14, ST(1)=2.0 | save | no change | restore | ST(0)=3.14, ST(1)=2.0 |
| 2 | various | save | flip tag word bit | restore | tag word reflects modification |

### State image size per generation

| # | Gen | Expected size | Format | Notes |
|---|-----|:------------:|--------|-------|
| 1 | 8087/287 | 94 bytes | 16-bit compact | 7 header + 80 data |
| 2 | 386+ (PM16) | 94 bytes | 16-bit compact | same as 8087/287 |
| 3 | 386+ (PM32) | 108 bytes | 32-bit expanded | 28 header + 80 data |

### Tag word preservation

| # | ST(i) value | Tag after FSAVE | Tag after FRSTOR | Notes |
|---|-------------|:---------------:|:----------------:|-------|
| 1 | 1.0 | 00 (valid) | 00 (valid) | |
| 2 | 0.0 | 01 (zero) | 01 (zero) | |
| 3 | Inf | 10 (special) | 10 (special) | |
| 4 | empty | 11 (empty) | 11 (empty) | |

> **Gen-gate:** 8087/287 tag word uses the saved tag image verbatim.
> 387+ recalculates tags from the register contents during FRSTOR.

### Register order in image

| # | Position | Register | Notes |
|---|----------|----------|-------|
| 1 | bytes 0-9 | ST(0) | current top of stack |
| 2 | bytes 10-19 | ST(1) | |
| ... | | | |
| 8 | bytes 70-79 | ST(7) | bottom |

## Pre/Post State (representative cases)

### FSAVE — saves + initializes

```
PRE (after loading 3 values):
  CW = 0x037F
  SW = 0x3000 (TOP=6, two values on stack)
  TW = 0x2FFF (R6=01(zero), R7=00(valid), rest=11(empty))
  ST(0) = +0.0 (at R6),  ST(1) = 1.0 (at R7)
  Buffer at DS:0x1000 = uninitialized

  OP:  FSAVE [0x1000]   (8087/287, 16-bit mode)

POST:
  [0x1000] = 0x037F  (CW, with reserved bits as stored)
  [0x1002] = 0x3000  (SW)
  [0x1004] = 0x2FFF  (TW)
  [0x1006..0x100D] = FIP/FCS/FDP/FDS
  [0x000E..0x005D] = ST(0)..ST(7) register images (80 bytes)
  Total: 94 bytes written

  FPU state AFTER FSAVE = initialized:
    CW = 0x0040  (all masks CLEARED — different from FNINIT's 0x037F!)
    SW = 0x0000  (TOP=0, empty)
    TW = 0xFFFF  (all empty)
    (FSAVE initializes like FINIT but with masks=0)
```

### FRSTOR — restores exact state

```
PRE:
  FPU state = freshly initialized (CW=0x037F after FNINIT)
  TOP = 0, Stack empty
  Buffer at DS:0x1000 contains saved image from previous FSAVE
  (which had CW=0x037F, SW=0x3000, TW=0x2FFF, 2 values)

  OP:  FRSTOR [0x1000]

POST:
  CW = 0x037F  (restored from buffer)
  SW = 0x3000  (TOP=6, restored)
  TW = 0x2FFF  (restored)
  ST(0) = +0.0  (restored from register image)
  ST(1) = 1.0
```

### Tag word — 8087/287 vs 387+ FRSTOR

```
8087/287:
  FSAVE stores actual tag values as-is.
  FRSTOR loads them verbatim.
  → A buffer with TW=0x0000 (all valid) will set all tags to valid,
    even if the register images are garbage.

387+:
  FRSTOR recalculates tags from register contents.
  → A buffer with TW=0x0000 but garbage register images will get
    tags recalculated (e.g., if value looks like NaN → tag=10(special)).
```

### 386+ 32-bit state image — 108 bytes

```
PRE:
  PM32 mode, 386+ FPU
  Buffer at DS:0x1000

  OP:  FSAVE [0x1000]

POST:
  [0x0000] = CW (2 bytes) + reserved (2 bytes)
  [0x0004] = SW (2 bytes) + reserved (2 bytes)
  [0x0008] = TW (2 bytes) + reserved (2 bytes)
  [0x000C] = FIP (4 bytes, 32-bit offset)
  [0x0010] = FCS (2 bytes) + opcode (2 bytes)
  [0x0014] = FDP (4 bytes, 32-bit offset)
  [0x0018] = FDS (2 bytes) + reserved (2 bytes)
  [0x001C..0x006B] = ST(0)..ST(7) (80 bytes)
  Total: 108 bytes
```

## State Save/Restore

- This module IS the save/restore test.  Use a second buffer to save/restore
  the test's own state.

## Known Divergences

| Behavior | 8087/287 | 387+ | Action |
|----------|----------|------|--------|
| Image size | 94B | 108B | gen-gate |
| Tag on FRSTOR | preserved | recalculated | verify matches |
| Opcode field | absent | present (386+) | gen-gate |

## Pass/Fail Criteria

- **PASS:** image format correct size; FRSTOR restores exact values; FSAVE zeroes FPU
- **FAIL:** format mismatch or value corruption
- **SKIP:** FPU not detected
