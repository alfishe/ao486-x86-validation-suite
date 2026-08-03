# Spec: 8086 Miscellaneous Instructions

## Metadata
- **Source file:** `src/cpu/8086/misc.asm`
- **TIER:** UNIVERSAL | VENUE: G+H | GEN: 8086+ | ORACLE: manual + golden
- **Impl-plan:** Phase 2, area `8086-Misc`
- **Coverage:** [§3](../../coverage-matrix.md#3-cpu--80868088-pri-1-foundation)

## Purpose

Verify XCHG, XLAT, LEA, CBW, CWD, and the undocumented SALC (D6).

## Test Cases

### XCHG

| # | op1 | op2 | Expected op1 | Expected op2 | Notes |
|---|-----|-----|-------------|-------------|-------|
| 1 | 0x1234 | 0x5678 | 0x5678 | 0x1234 | exchange |
| 2 | 0x0000 | 0xFFFF | 0xFFFF | 0x0000 | |
| 3 | AX | AX | unchanged | — | XCHG with self = NOP |

> XCHG with memory has an implicit LOCK on 8086. Verify no #UD.

### XLAT

| # | AL_in | BX (table base) | [BX+AL] | Expected AL | Notes |
|---|-------|-----------------|---------|-------------|-------|
| 1 | 0x03 | table | 0x42 | 0x42 | AL = [DS:BX+AL] |
| 2 | 0x00 | table | 0xFF | 0xFF | first entry |

### LEA

| # | Operand | Expected | Notes |
|---|---------|----------|-------|
| 1 | `LEA AX, [BX+SI]` | AX = BX + SI | address math, no memory access |
| 2 | `LEA AX, [BX+0x100]` | AX = BX + 0x100 | |
| 3 | `LEA AX, [0x1234]` | AX = 0x1234 | direct offset |

### CBW

| # | AL | Expected AX | Notes |
|---|----|-------------|-------|
| 1 | 0x7F | 0x007F | positive: AH=0 |
| 2 | 0x80 | 0xFF80 | negative: AH=0xFF |
| 3 | 0x00 | 0x0000 | zero |
| 4 | 0xFF | 0xFFFF | -1 |

### CWD

| # | AX | Expected DX:AX | Notes |
|---|----|----------------|-------|
| 1 | 0x7FFF | 0x0000:0x7FFF | positive: DX=0 |
| 2 | 0x8000 | 0xFFFF:0x8000 | negative: DX=0xFFFF |

### SALC (D6 — undocumented)

| # | CF_in | Expected AL | Notes |
|---|:------:|-------------|-------|
| 1 | 0 | 0x00 | CF clear → AL=0 |
| 2 | 1 | 0xFF | CF set → AL=0xFF |

> SALC is undocumented but present on all generations.  Flags are NOT affected.
> Oracle: golden (documented in no official manual).

## Pre/Post State (representative cases)

### XCHG r16, r16

```
PRE:
  AX = 0x1234
  BX = 0x5678

  OP:  XCHG AX, BX

POST:
  AX = 0x5678    ← swapped
  BX = 0x1234
  FLAGS = unchanged
```

### XCHG AX, [mem] — implicit LOCK on 8086

```
PRE:
  AX = 0x1111
  [DS:0x1000] = 0x2222

  OP:  XCHG AX, [0x1000]

POST:
  AX = 0x2222
  [DS:0x1000] = 0x1111
  FLAGS = unchanged
  LOCK asserted on bus (8086 only — no #UD)
```

### XLAT — table lookup

```
PRE:
  BX  = 0x1000      (table base)
  AL  = 0x03        (index)
  [DS:0x1000+0] = 0x10
  [DS:0x1000+1] = 0x20
  [DS:0x1000+2] = 0x30
  [DS:0x1000+3] = 0x42    ← target entry

  OP:  XLAT

POST:
  AL  = 0x42        ← AL = [DS:BX + old_AL]
  BX  = 0x1000      (unchanged)
  FLAGS = unchanged
```

### CBW — sign-extend AL to AX

```
PRE:
  AL = 0x80        (negative: -128)
  AH = 0x00

  OP:  CBW

POST:
  AX = 0xFF80      (AH = 0xFF, sign-extended)
  FLAGS = unchanged
```

### CWD — sign-extend AX to DX:AX

```
PRE:
  AX = 0x8000      (negative: -32768)
  DX = 0x0000

  OP:  CWD

POST:
  DX:AX = 0xFFFF:0x8000   (DX = 0xFFFF, sign-extended)
  FLAGS = unchanged
```

### LEA — effective address computation

```
PRE:
  BX = 0x1000
  SI = 0x0040

  OP:  LEA AX, [BX+SI+0x10]

POST:
  AX = 0x1050      ← BX + SI + 0x10 = 0x1000 + 0x0040 + 0x0010
  BX = 0x1000      (unchanged)
  SI = 0x0040      (unchanged)
  No memory access performed
  FLAGS = unchanged
```

### SALC (D6) — undocumented

```
PRE:
  CF = 1
  AL = 0x42

  OP:  SALC          (opcode D6)

POST:
  AL = 0xFF          ← CF set → AL = 0xFF
  FLAGS = unchanged
```

## State Save/Restore

- **Save:** AX, BX, SI, DX, FLAGS
- **Restore:** `RESTORE_STATE`

## Pass/Fail Criteria

- **PASS:** all results match
- **FAIL:** any mismatch
- **SKIP:** never (SALC works on all target generations)
