# Spec: 8086 String Operations

## Metadata
- **Source file:** `src/cpu/8086/string.asm`
- **TIER:** UNIVERSAL
- **VENUE:** G + H (oracle)
- **GEN:** 8086+
- **ORACLE:** manual
- **Impl-plan:** Phase 2, area `8086-String`
- **Coverage:** [§3](../../coverage-matrix.md#3-cpu--80868088-pri-1-foundation)

## Purpose

Verify MOVS/STOS/LODS/CMPS/SCAS with REP/REPZ/REPNZ prefixes, DF direction,
segment overrides, and CX=0/CX=1/CX=N boundary cases.

## Prerequisites

- Scratch memory buffers (source + destination) in `.bss`
- DF save/restore (critical — a stray DF poisons later tests)

## Test Cases

### MOVS direction

| # | DF | SI | DI | CX | Expected DI delta | Notes |
|---|:--:|----|----|:--:|:-----------------:|-------|
| 1 | 0 | src | dst | 1 | +1 (byte), +2 (word) | forward |
| 2 | 1 | src+N | dst+N | 1 | -1 (byte), -2 (word) | backward |

### REP MOVS with CX

| # | CX | Expected copies | SI/DI delta | Notes |
|---|:--:|:---------------:|:-----------:|-------|
| 1 | 0 | 0 | 0 | CX=0 does nothing |
| 2 | 1 | 1 | ±1 or ±2 | single copy |
| 3 | 16 | 16 | ±16 or ±32 | block copy |

### REPZ/REPNZ CMPS (early termination)

| # | data | prefix | CX | Expected iterations | ZF | Notes |
|---|------|--------|:--:|:-------------------:|:--:|-------|
| 1 | equal | REPZ | 4 | 4 | 1 | all match, CX exhausted |
| 2 | mismatch at idx 2 | REPZ | 4 | 2 | 0 | stops at mismatch |
| 3 | mismatch at idx 2 | REPNZ | 4 | 3 | 1 | stops at match (after idx 2) |
| 4 | all mismatch | REPNZ | 4 | 4 | 0 | CX exhausted, no match |

### REPZ/REPNZ SCAS

| # | AL | data | prefix | CX | Expected iterations | Notes |
|---|----|------|--------|:--:|:-------------------:|-------|
| 1 | 0x00 | all 0xFF | REPNZ | 4 | 4 | no match, CX exhausted |
| 2 | 0x00 | 0xFF,0x00,... | REPNZ | 4 | 1 | match at idx 0 |

### Segment override on MOVS

- Default source segment for MOVS is DS, destination is ES
- Test: `DS:SI` → `ES:DI` (default)
- Test: `CS:SI` → `ES:DI` (override source)
- Test: `ES:SI` → `ES:DI` (override source to ES)

### Width variants

Test byte (MOVSB) and word (MOVSW) for each of the above.

## Pre/Post State (representative cases)

### REP MOVSB — CX=4, DF=0 (forward)

```
PRE:
  DS:SI = 0x1000:0x0100  →  src = [41 42 43 44]
  ES:DI = 0x2000:0x0200  →  dst = [00 00 00 00]
  CX    = 0x0004
  DF    = 0
  FLAGS = 0x0002

  OP:  REP MOVSB

POST:
  ES:DI →  dst = [41 42 43 44]   ← copied
  SI    = 0x0104                  ← +4
  DI    = 0x0204                  ← +4
  CX    = 0x0000                  ← exhausted
  FLAGS = 0x0002                  ← unchanged (MOVS does not affect flags)
```

### REP MOVSB — CX=4, DF=1 (backward)

```
PRE:
  DS:SI = 0x1000:0x0103  →  src = [41 42 43 44]
  ES:DI = 0x2000:0x0203  →  dst = [00 00 00 00]
  CX    = 0x0004
  DF    = 1

  OP:  REP MOVSB

POST:
  dst = [41 42 43 44]   ← copied (pointers started high, decremented)
  SI    = 0x00FF                  ← -4
  DI    = 0x01FF                  ← -4
  CX    = 0x0000
```

### REP MOVSW — CX=2, DF=0

```
PRE:
  DS:SI = 0x1000:0x0100  →  src = [34 12 78 56]
  ES:DI = 0x2000:0x0200  →  dst = [00 00 00 00]
  CX    = 0x0002
  DF    = 0

  OP:  REP MOVSW

POST:
  dst = [34 12 78 56]             ← two 16-bit words copied
  SI    = 0x0104                  ← +4 (2 words × 2 bytes)
  DI    = 0x0204                  ← +4
  CX    = 0x0000
```

### REPZ CMPSB — mismatch at index 2, CX=4

```
PRE:
  DS:SI = 0x1000:0x0100  →  src = [41 41 42 41]
  ES:DI = 0x2000:0x0200  →  dst = [41 41 41 41]
  CX    = 0x0004
  DF    = 0

  OP:  REPE CMPSB

POST:
  SI    = 0x0103                  ← stopped at idx 2 (SI advanced past mismatch)
  DI    = 0x0203                  ← +3 iterations
  CX    = 0x0002                  ← 2 remaining
  ZF    = 0                       ← last comparison was unequal
```

### REPNE SCASB — match at index 0, CX=4

```
PRE:
  ES:DI = 0x2000:0x0200  →  buf = [00 FF FF FF]
  AL    = 0x00
  CX    = 0x0004
  DF    = 0

  OP:  REPNE SCASB

POST:
  DI    = 0x0201                  ← matched at idx 0 (DI advanced past match)
  CX    = 0x0003                  ← 3 remaining
  ZF    = 1                       ← last comparison was equal
```

### CX=0 — no operation

```
PRE:
  SI = 0x0100, DI = 0x0200, CX = 0x0000, DF = 0

  OP:  REP MOVSB

POST:
  SI = 0x0100, DI = 0x0200, CX = 0x0000   ← no change at all
```

## State Save/Restore

- **Save:** CX, SI, DI, DF, ES, DS
- **Restore:** explicitly restore DF=0 and segment registers

## Known Divergences

None — string ops are architecturally uniform.

## Pass/Fail Criteria

- **PASS:** destination buffer matches expected; SI/DI advanced correctly; CX correct
- **FAIL:** data mismatch or pointer arithmetic wrong
- **SKIP:** never
