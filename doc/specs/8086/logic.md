# Spec: 8086 Logic Instructions

## Metadata
- **Source file:** `src/cpu/8086/logic.asm`
- **TIER:** UNIVERSAL
- **VENUE:** G + H (oracle)
- **GEN:** 8086+
- **ORACLE:** manual + golden (AF)
- **Impl-plan:** Phase 2, area `8086-Logic`
- **Coverage:** [§3](../../coverage-matrix.md#3-cpu--80868088-pri-1-foundation), [§3.1 AF undefined](../../coverage-matrix.md#31-hard-cases--flag-semantics)
- **Divergences:** [prep-analysis §1.2](../../prep-analysis.md#12-behavioral-divergences-same-instruction-different-result)

## Purpose

Verify AND/OR/XOR/TEST/NOT — result, CF/OF always cleared, and the
**undefined AF** pin from golden vectors.

## Prerequisites

- `SAVE_STATE` / `RESTORE_STATE` macros

## Golden Vector Files

| File | Contents | Per-generation |
|------|----------|:--------------:|
| `data/vectors/golden_logic_af.json` | AF values for AND/OR/XOR/TEST | yes |

> **AF rule:** AF is undefined for logic ops. Pin from golden vectors per CPU.

## Test Cases

### AND r8, r8

| # | op1 | op2 | Expected | CF | OF | PF | ZF | SF | AF | Notes |
|---|-----|-----|----------|:--:|:--:|:--:|:--:|:--:|:--:|-------|
| 1 | 0xFF | 0x0F | 0x0F | 0 | 0 | 1 | 0 | 0 | golden | mask lower nibble |
| 2 | 0xFF | 0x00 | 0x00 | 0 | 0 | 1 | 1 | 0 | golden | AND with zero |
| 3 | 0xAA | 0x55 | 0x00 | 0 | 0 | 1 | 1 | 0 | golden | no overlap |
| 4 | 0xFF | 0xFF | 0xFF | 0 | 0 | 0 | 0 | 1 | golden | AND with self |

> **AF is undefined** for AND/OR/XOR/TEST.  Pin from golden.  CF=0, OF=0
> always.  SF/ZF/PF are defined from the result.

### OR r8, r8

| # | op1 | op2 | Expected | CF | OF | PF | ZF | SF | AF | Notes |
|---|-----|-----|----------|:--:|:--:|:--:|:--:|:--:|:--:|-------|
| 1 | 0xF0 | 0x0F | 0xFF | 0 | 0 | 0 | 0 | 1 | golden | combine nibbles |
| 2 | 0x00 | 0x00 | 0x00 | 0 | 0 | 1 | 1 | 0 | golden | zero OR zero |
| 3 | 0xAA | 0x55 | 0xFF | 0 | 0 | 0 | 0 | 1 | golden | complement bits |

### XOR r8, r8

| # | op1 | op2 | Expected | CF | OF | PF | ZF | SF | AF | Notes |
|---|-----|-----|----------|:--:|:--:|:--:|:--:|:--:|:--:|-------|
| 1 | 0xFF | 0xFF | 0x00 | 0 | 0 | 1 | 1 | 0 | golden | XOR with self = zero |
| 2 | 0xFF | 0x00 | 0xFF | 0 | 0 | 0 | 0 | 1 | golden | XOR with zero = self |
| 3 | 0xAA | 0x55 | 0xFF | 0 | 0 | 0 | 0 | 1 | golden | toggle all bits |
| 4 | 0x0F | 0xF0 | 0xFF | 0 | 0 | 0 | 0 | 1 | golden | swap nibbles |

### TEST r8, r8

Same flags as AND but **operands are NOT modified**.
After TEST, verify both op1 and op2 are unchanged.

### NOT r8

| # | op1 | Expected | Flags | Notes |
|---|-----|----------|-------|-------|
| 1 | 0x00 | 0xFF | **none** | NOT affects NO flags |
| 2 | 0xFF | 0x00 | **none** | |
| 3 | 0x55 | 0xAA | **none** | |

> **NOT affects no flags at all** — verify by pre-seeding flags, running NOT,
> and confirming they are identical afterward.

## 16-bit Variants

Repeat with AX/BX and 16-bit operands from the value classes.

## Pre/Post State (representative cases)

### AND r8, r8 — mask lower nibble

```
PRE:
  AL = 0xFF
  BL = 0x0F
  FLAGS = 0x0000

  OP:  AND AL, BL

POST:
  AL = 0x0F       (lower nibble preserved, upper cleared)
  BL = 0x0F       (unchanged)
  CF=0  OF=0      (logic ops always clear these)
  PF=1  (0x0F has 4 ones → even → PF=1)
  ZF=0  SF=0
  AF=golden       (undefined — pin from golden_logic_af.json)
```

### AND r8, r8 — zero result

```
PRE:
  AL = 0xAA
  BL = 0x55
  FLAGS = 0x0000

  OP:  AND AL, BL

POST:
  AL = 0x00       (no overlapping bits)
  BL = 0x55       (unchanged)
  CF=0  OF=0  PF=1  ZF=1  SF=0
  AF=golden
```

### TEST r8, r8 — operands NOT modified

```
PRE:
  AL = 0xFF
  BL = 0x0F
  FLAGS = 0x0000

  OP:  TEST AL, BL

POST:
  AL = 0xFF       (unchanged — TEST = AND without writeback)
  BL = 0x0F       (unchanged)
  Flags set as if AND was performed: CF=0 OF=0 PF=1 ZF=0 SF=0
  AF=golden
```

### OR r8, r8 — combine nibbles

```
PRE:
  AL = 0xF0
  BL = 0x0F
  FLAGS = 0x0000

  OP:  OR AL, BL

POST:
  AL = 0xFF       (all bits set)
  BL = 0x0F       (unchanged)
  CF=0  OF=0  PF=0  ZF=0  SF=1
  AF=golden
```

### NOT r8 — no flags affected

```
PRE:
  AL = 0x00
  FLAGS = 0x0FD5   (all-set seed)

  OP:  NOT AL

POST:
  AL = 0xFF
  FLAGS = 0x0FD5   (unchanged — NOT affects NO flags)
```

## State Save/Restore

- **Save:** AX, BX, CX, DX, FLAGS
- **Restore:** `RESTORE_STATE`

## Known Divergences

| Behavior | 8086 | 286+ | Action |
|----------|------|------|--------|
| AF after logic ops | specific value | may differ | golden per-gen |

## Pass/Fail Criteria

- **PASS:** result + CF/OF/PF/ZF/SF match; AF matches golden
- **FAIL:** any flag mismatch (including AF vs golden)
- **SKIP:** never
