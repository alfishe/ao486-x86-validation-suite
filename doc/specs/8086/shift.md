# Spec: 8086 Shift & Rotate

## Metadata
- **Source file:** `src/cpu/8086/shift.asm`
- **TIER:** UNIVERSAL
- **VENUE:** G + H (oracle)
- **GEN:** 8086+
- **ORACLE:** manual + golden (OF for count>1)
- **Impl-plan:** Phase 2, area `8086-Shift`
- **Coverage:** [§3](../../coverage-matrix.md#3-cpu--80868088-pri-1-foundation), [§3.1 count masking](../../coverage-matrix.md#31-hard-cases--flag-semantics)
- **Divergences:** [prep-analysis §1.2](../../prep-analysis.md#12-behavioral-divergences-same-instruction-different-result) — shift count masking

## Purpose

Verify SHL/SHR/SAR/ROL/ROR/RCL/RCR — result + CF threading + the
**8086-vs-286 count-masking divergence** + **count=0 no-op** + **OF
undefined for count>1**.

## Prerequisites

- `SAVE_STATE` / `RESTORE_STATE` macros

## Golden Vector Files

| File | Contents | Per-generation |
|------|----------|:--------------:|
| `data/vectors/golden_shift_of.json` | OF values for shift count > 1 | yes |
| `data/vectors/golden_shift_cf.json` | CF values for boundary cases | yes |

> **OF rule:** OF is defined only for count=1. For count>1, OF is undefined —
> pin from golden vectors per CPU generation.

## Count Classes

Test with CL set to: `{0, 1, 2, 7, 8, 15, 16, 17, 31, 32, 33, 255}`

These straddle:
- 0 (no-op)
- 1 (OF defined)
- width boundaries (8, 16)
- 8086-vs-286 mask boundary (31=0x1F, 32=0x20)
- unmasked extremes (33, 255)

## Test Cases

### SHL r8, CL — count masking

| # | op1 | CL | 8086 result | 286+ result | CF | Notes |
|---|-----|-----|------------|-------------|:--:|-------|
| 1 | 0x01 | 0 | 0x01 | 0x01 | unchanged | count=0: ALL flags unchanged |
| 2 | 0x01 | 1 | 0x02 | 0x02 | 0 | OF defined (bit6≠bit7) |
| 3 | 0x80 | 1 | 0x00 | 0x00 | 1 | CF=MSB before shift |
| 4 | 0x01 | 7 | 0x80 | 0x80 | 0 | 7 shifts |
| 5 | 0x01 | 8 | 0x00 | 0x00 | 0 | full-width shift |
| 6 | 0x01 | 16 | 0x00 (8086: 16 shifts) | 0x01 (286+: 16&31=16, 16%8=0 → no shift for 8-bit!) | golden | **KEY DIVERGENCE** |
| 7 | 0x01 | 31 | 0x00 (8086: 31 shifts) | 0x80 (286+: 31%8=7) | golden | **KEY DIVERGENCE** |
| 8 | 0x01 | 32 | 0x00 (8086: 32 shifts) | 0x01 (286+: 32&31=0 → no-op) | unchanged | **KEY DIVERGENCE** |

> **8086:** CL is used raw (no masking).  CL=255 = 255 shifts.
> **286+:** CL is masked to 5 bits (`& 0x1F`).  CL=255 → 31 shifts.
> For 8-bit operands, 286+ further reduces: the effective count is `masked_CL % 8`.

### SHL r8, 1 (immediate)

| # | op1 | Expected | CF | OF | Notes |
|---|-----|----------|:--:|:--:|-------|
| 1 | 0x01 | 0x02 | 0 | 0 | OF = bit7 XOR bit6 = 0 XOR 0 = 0 |
| 2 | 0x40 | 0x80 | 0 | 1 | OF = bit7 XOR bit6 = 0 XOR 1 = 1 |
| 3 | 0x80 | 0x00 | 1 | 1 | OF = bit7 XOR bit6 = 1 XOR 0 = 1 |
| 4 | 0xC0 | 0x80 | 1 | 0 | OF = bit7 XOR bit6 = 1 XOR 1 = 0 |

> OF is **defined only for count=1**.  For count>1, OF is undefined — pin golden.

### SHR r8, CL

Same count-masking logic. CF = last bit shifted out (LSB).

### SAR r8, CL

Sign-preserving shift. CF = last bit shifted out. SF preserved.

### ROL/ROR/RCL/RCR — CF threading

| # | op | op1 | CL | Expected | CF | Notes |
|---|-----|-----|-----|----------|:--:|-------|
| 1 | ROL | 0x80 | 1 | 0x01 | 1 | MSB rotates to LSB and CF |
| 2 | ROL | 0x01 | 1 | 0x02 | 0 | simple left rotate |
| 3 | ROR | 0x01 | 1 | 0x80 | 1 | LSB rotates to MSB and CF |
| 4 | ROR | 0x80 | 1 | 0x40 | 0 | simple right rotate |
| 5 | RCL | 0x00 | 1 (CF=1) | 0x01 | 0 | CF rotates into LSB |
| 6 | RCL | 0x80 | 1 (CF=0) | 0x00 | 1 | MSB rotates into CF |
| 7 | RCR | 0x01 | 1 (CF=1) | 0x80 | 1 | CF rotates into MSB |
| 8 | RCR | 0x00 | 1 (CF=1) | 0x80 | 0 | CF rotates into MSB, LSB→CF |

> Pre-seed CF before RCL/RCR tests — the carry is part of the rotation.

### OF for count=1 only (all rotate ops)

For ROL/ROR: OF = MSB XOR CF_after (or bit6 XOR bit7, implementation-dependent).
For RCL/RCR: OF = bit7 XOR CF_after.
OF for count>1 is **undefined** — pin golden.

### count=0 no-op (ALL shift/rotate ops)

For every shift/rotate instruction with CL=0:
- **Result** unchanged
- **ALL flags** unchanged (CF, PF, AF, ZF, SF, OF — all must match pre-state)

> This is **very commonly wrong** in emulators.  Test every op with CL=0.

## 16-bit Variants

Repeat with AX and 16-bit operands.  For 286+, the effective count for 16-bit
ops is `masked_CL % 16`.

## Pre/Post State (representative cases)

### SHL r8, 1 — OF defined for count=1

```
PRE:
  AL = 0x40       (bit6 set, bit7 clear)
  FLAGS = 0x0000

  OP:  SHL AL, 1

POST:
  AL = 0x80       (shifted left)
  CF=0  (MSB before shift = 0)
  OF=1  (bit7 XOR bit6 = 1 XOR 0 = 1)
  PF, AF, ZF, SF defined from result (0x80)
```

### SHL r8, CL — count=0 no-op (all flags preserved)

```
PRE:
  AL = 0x42
  CL = 0x00
  FLAGS = 0x0FD5   (all-set seed: CF=1 PF=1 AF=1 ZF=1 SF=1 OF=1)

  OP:  SHL AL, CL

POST:
  AL = 0x42        (unchanged)
  FLAGS = 0x0FD5   (ALL flags unchanged — count=0 is true no-op)
```

### SHL r8, CL=16 — KEY DIVERGENCE (8086 vs 286+)

```
8086 PRE:
  AL = 0x01, CL = 16, FLAGS = 0x0000
  OP:  SHL AL, CL
8086 POST:
  AL = 0x00        (16 raw shifts → all bits shifted out)
  CF = 0           (last bit shifted out was 0)

286+ PRE:
  AL = 0x01, CL = 16, FLAGS = 0x0000
  OP:  SHL AL, CL
286+ POST:
  AL = 0x01        (CL & 0x1F = 16, then 16 % 8 = 0 → no-op for 8-bit)
  FLAGS unchanged  (effective count = 0 → no-op)
```

### SHL r8, CL=31 — divergence (8086 vs 286+)

```
8086 PRE:
  AL = 0x01, CL = 31
8086 POST:
  AL = 0x00        (31 raw shifts)
  CF = 0

286+ PRE:
  AL = 0x01, CL = 31
286+ POST:
  AL = 0x80        (CL & 0x1F = 31, then 31 % 8 = 7 → 7 shifts)
  CF = 0           (bit7 before 7th shift was 0)
```

### ROL r8, 1 — CF threading

```
PRE:
  AL = 0x80       (only MSB set)
  FLAGS = 0x0000

  OP:  ROL AL, 1

POST:
  AL = 0x01       (MSB rotated to LSB)
  CF = 1          (MSB before shift copied to CF)
  OF = 1          (bit7 XOR CF_after = 0 XOR 1 = 1)
```

### RCR r8, 1 — CF pre-seed required

```
PRE:
  AL = 0x01
  CF = 1          (pre-seeded via STC)
  FLAGS = 0x0001

  OP:  RCR AL, 1

POST:
  AL = 0x80       (CF rotated into MSB, LSB shifted to CF)
  CF = 1          (old LSB = 1 shifted out)
```

## State Save/Restore

- **Save:** AX, BX, CX (CL is consumed), FLAGS, DF
- **Restore:** `RESTORE_STATE`

## Known Divergences

| Behavior | 8086 | 286+ | Action |
|----------|------|------|--------|
| Count masking | raw CL | CL & 0x1F | gen-gated test |
| OF for count>1 | specific | different | golden per-gen |

## Pass/Fail Criteria

- **PASS:** result + CF + OF (count=1) match; flags unchanged for count=0
- **FAIL:** any mismatch
- **SKIP:** never (8086 raw-count path tested at GEN 8086; masked path tested at GEN 286+)
