# Spec: 8086 Flag Manipulation

## Metadata
- **Source file:** `src/cpu/8086/flags.asm`
- **TIER:** UNIVERSAL | VENUE: G+H | GEN: 8086+ | ORACLE: manual
- **Impl-plan:** Phase 2, area `8086-Flags`
- **Coverage:** [§3](../../coverage-matrix.md#3-cpu--80868088-pri-1-foundation)

## Purpose

Verify direct flag manipulation: STC/CLC/CMC, STD/CLD, STI/CLI, LAHF/SAHF,
PUSHF/POPF.  Confirm each flag can be set, cleared, and toggled independently.

## Test Cases

### CF manipulation

| # | Instruction | CF_before | Expected CF_after | Notes |
|---|-------------|:---------:|:-----------------:|-------|
| 1 | STC | 0 | 1 | set carry |
| 2 | CLC | 1 | 0 | clear carry |
| 3 | CMC | 0 | 1 | complement carry |
| 4 | CMC | 1 | 0 | complement carry |

### DF manipulation

| # | Instruction | DF_before | Expected DF_after | Notes |
|---|-------------|:---------:|:-----------------:|-------|
| 1 | STD | 0 | 1 | set direction (string ops decrement) |
| 2 | CLD | 1 | 0 | clear direction (string op increment) |

> **Critical:** DF must be cleared after every test that uses it.

### IF manipulation

| # | Instruction | IF_before | Expected IF_after | Notes |
|---|-------------|:---------:|:-----------------:|-------|
| 1 | STI | 0 | 1 | enable interrupts |
| 2 | CLI | 1 | 0 | disable interrupts |

> **Note:** IF is not readable via PUSHF in virtual 8086 mode at IOPL<3.
> In real mode, IF is always accessible.

### LAHF/SAHF (low byte of FLAGS)

| # | AH_value | Action | Expected SF,ZF,AF,PF,CF | Notes |
|---|----------|--------|-------------------------|-------|
| 1 | 0x00 | SAHF | all clear | |
| 2 | 0xFF | SAHF | all set | bits not in AH (TF, IF, DF, OF) unchanged |
| 3 | — | LAHF | AH = low byte of FLAGS | |

> LAHF/SAHF only affect SF, ZF, AF, PF, CF (bits 7,6,4,2,0).
> They do NOT touch TF, IF, DF, OF (bits 8,9,10,11).

### PUSHF/POPF (full FLAGS word)

| # | Action | Expected | Notes |
|---|--------|----------|-------|
| 1 | PUSHF; POP AX | AX = FLAGS image | full 16-bit read |
| 2 | PUSH AX; POPF | FLAGS = AX | full 16-bit write |
| 3 | round-trip | second PUSHF == first | no side effects |

> On 8086: bits 12-15 always read as 1s.
> On 286+: bits 12-15 clear in real mode.

### Flag independence (set one, verify others unchanged)

| # | Set flag | Verify other flags unchanged |
|---|----------|------------------------------|
| 1 | STC | DF, IF, TF, OF unchanged |
| 2 | STD | CF, IF, TF, OF unchanged |
| 3 | STI | CF, DF, TF, OF unchanged |

## Pre/Post State (representative cases)

### STC / CLC / CMC — CF manipulation

```
PRE:  FLAGS = 0x0002  (bit1=1 always set, CF=0)
  OP:  STC
POST: FLAGS = 0x0003  (CF=1)

PRE:  FLAGS = 0x0003  (CF=1)
  OP:  CLC
POST: FLAGS = 0x0002  (CF=0)

PRE:  FLAGS = 0x0002  (CF=0)
  OP:  CMC
POST: FLAGS = 0x0003  (CF toggled to 1)

PRE:  FLAGS = 0x0003  (CF=1)
  OP:  CMC
POST: FLAGS = 0x0002  (CF toggled to 0)
```

### STD / CLD — DF manipulation

```
PRE:  FLAGS = 0x0002  (DF=0)
  OP:  STD
POST: FLAGS = 0x0402  (DF=1, bit10 set)

PRE:  FLAGS = 0x0402  (DF=1)
  OP:  CLD
POST: FLAGS = 0x0002  (DF=0)
```

### STI / CLI — IF manipulation

```
PRE:  FLAGS = 0x0002  (IF=0, interrupts disabled)
  OP:  STI
POST: FLAGS = 0x0202  (IF=1, bit9 set)

PRE:  FLAGS = 0x0202  (IF=1)
  OP:  CLI
POST: FLAGS = 0x0002  (IF=0)
```

### Flag independence — set one, verify others unchanged

```
PRE:  FLAGS = 0x0002  (all clear, bit1 only)
  OP:  STC
POST: FLAGS = 0x0003  (only CF changed; DF=0, IF=0, TF=0, OF=0)
  ✓ DF still 0 (bit10 = 0)
  ✓ IF still 0 (bit9 = 0)
  ✓ OF still 0 (bit11 = 0)
```

```
PRE:  FLAGS = 0x0003  (CF=1)
  OP:  STD
POST: FLAGS = 0x0403  (only DF changed; CF=1 still)
  ✓ CF still 1 (bit0 = 1)
  ✓ IF still 0 (bit9 = 0)
```

### SAHF — low-byte load

```
PRE:  AH = 0xFF      (SF=1 ZF=1 AF=1 PF=1 CF=1)
  FLAGS = 0x0002     (SF=0 ZF=0 AF=0 PF=0 CF=0)

  OP:  SAHF

POST: FLAGS = 0x00D7  (bits 7,6,4,2,0 loaded from AH)
  SF=1(7) ZF=1(6) AF=1(4) PF=1(2) CF=1(0)
  TF/IF/DF/OF unchanged (bits 8,9,10,11 = 0)
```

### LAHF — low-byte read

```
PRE:  FLAGS = 0x00D7  (SF=1 ZF=1 AF=1 PF=1 CF=1)
  AH = 0x00

  OP:  LAHF

POST: AH = 0xD7       (loaded from low byte of FLAGS)
  FLAGS unchanged
```

## State Save/Restore

- **Save:** FLAGS (full word), AX
- **Restore:** `RESTORE_STATE` — especially IF (restore original interrupt state)

## Pass/Fail Criteria

- **PASS:** each flag correctly set/cleared/toggled; other flags unaffected
- **FAIL:** cross-contamination between flags
- **SKIP:** never
