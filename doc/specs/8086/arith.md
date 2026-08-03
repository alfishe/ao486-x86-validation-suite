# Spec: 8086 Arithmetic Instructions

## Metadata
- **Source file:** `src/cpu/8086/arith.asm`
- **TIER:** UNIVERSAL
- **VENUE:** G + H (oracle)
- **GEN:** 8086+
- **ORACLE:** manual + golden (undefined flags)
- **Impl-plan:** Phase 2, area `8086-Arith`
- **Coverage:** [§3](../../coverage-matrix.md#3-cpu--80868088-pri-1-foundation), [§3.1 flag semantics](../../coverage-matrix.md#31-hard-cases--flag-semantics), [§3.2 arithmetic edges](../../coverage-matrix.md#32-hard-cases--arithmetic-edge-cases)
- **Divergences:** [prep-analysis §1.2](../../prep-analysis.md#12-behavioral-divergences-same-instruction-different-result), [§1.2a](../../prep-analysis.md#12a-generation-specific-divergences-286-vs-386-vs-486)
- **Pattern:** [adding-tests.md "Example: Testing ADD"](../../adding-tests.md#example-testing-add-instruction)

## Purpose

Verify ADD/ADC/SUB/SBB/CMP/NEG/INC/DEC/MUL/IMUL/DIV/IDIV — result AND all
6 arithmetic flags (CF, PF, AF, ZF, SF, OF).  This is the single highest
bug-yield module in the suite.

## Prerequisites

- `SAVE_STATE` / `RESTORE_STATE` macros (Phase 1 INFRA)
- `TEST_ARITH_FULL` macro or equivalent inline pattern

## Golden Vector Files

| File | Contents | Per-generation |
|------|----------|:--------------:|
| `data/vectors/golden_mul_flags.json` | MUL/IMUL undefined flags (SF, ZF, AF, PF) | yes |
| `data/vectors/golden_div_flags.json` | DIV/IDIV undefined flags | yes |
| `data/vectors/golden_de_return.json` | #DE return address (8086 vs 286+) | yes |

> **Usage:** Load the JSON for the detected CPU generation. Each entry is keyed
> by `{op1}_{op2}` and contains the exact flag values observed on real silicon.

## Operand Value Classes

Per width (8-bit and 16-bit), sample these equivalence classes:

| Class | 8-bit value | 16-bit value | Why |
|-------|------------|-------------|-----|
| zero | 0x00 | 0x0000 | identity for ADD, zero result |
| one | 0x01 | 0x0001 | minimal increment |
| all-ones | 0xFF | 0xFFFF | carry-out, -1 signed |
| max-signed-pos | 0x7F | 0x7FFF | signed overflow boundary |
| min-signed-neg | 0x80 | 0x8000 | signed overflow boundary, INT_MIN |
| max-unsigned | 0xFF | 0xFFFF | carry-out on +1 |
| mid-value | 0x55 | 0x5555 | alternating bits (parity test) |
| mid-value2 | 0xAA | 0xAAAA | alternating bits complement |

## Flag-Seed Classes

Run each operand pair with incoming FLAGS pre-seeded to:

| Seed | Value | Why |
|------|-------|-----|
| all-clear | 0x0000 | baseline |
| all-set | 0x0FD5 | defined+reserved bits set |
| CF-only | FLAG_CF | tests ADC carry-in, INC/DEC CF-preservation |
| AF-only | FLAG_AF | tests half-carry path in BCD chains |

## Test Cases

### ADD r8, r8

| # | op1 | op2 | Expected | CF | PF | AF | ZF | SF | OF | Notes |
|---|-----|-----|----------|:--:|:--:|:--:|:--:|:--:|:--:|-------|
| 1 | 0x12 | 0x34 | 0x46 | 0 | 0 | 0 | 0 | 0 | 0 | 0x46=01000110, 3 ones → odd → PF=0 |
| 2 | 0xFF | 0x01 | 0x00 | 1 | 1 | 1 | 1 | 0 | 0 | carry-out + zero result |
| 3 | 0x7F | 0x01 | 0x80 | 0 | 0 | 1 | 0 | 1 | 1 | signed overflow: pos+pos=neg |
| 4 | 0x80 | 0x80 | 0x00 | 1 | 1 | 0 | 1 | 0 | 1 | signed overflow: neg+neg=pos |
| 5 | 0x00 | 0x00 | 0x00 | 0 | 1 | 0 | 1 | 0 | 0 | zero+zero |
| 6 | 0xFF | 0xFF | 0xFE | 1 | 0 | 1 | 0 | 1 | 0 | max carry, no overflow |

> **Parity note:** PF reflects the low 8 bits of the result ONLY, even for
> 16-bit operations.  Count the 1-bits in the low byte; even → PF=1.

### ADC r8, r8 with CF pre-seed

| # | op1 | op2 | CF_in | Expected | CF_out | Notes |
|---|-----|-----|:-----:|----------|:------:|-------|
| 1 | 0x01 | 0x01 | 0 | 0x02 | 0 | no carry-in |
| 2 | 0x01 | 0x01 | 1 | 0x03 | 0 | carry-in adds 1 |
| 3 | 0xFF | 0x00 | 1 | 0x00 | 1 | carry-in wraps to zero, carry-out |
| 4 | 0xFF | 0xFF | 1 | 0xFF | 1 | full carry chain |

### SUB r8, r8

| # | op1 | op2 | Expected | CF | PF | AF | ZF | SF | OF | Notes |
|---|-----|-----|----------|:--:|:--:|:--:|:--:|:--:|:--:|-------|
| 1 | 0x46 | 0x34 | 0x12 | 0 | 0 | 0 | 0 | 0 | 0 | simple sub |
| 2 | 0x00 | 0x01 | 0xFF | 1 | 0 | 1 | 0 | 1 | 0 | borrow, sign flip |
| 3 | 0x80 | 0x01 | 0x7F | 0 | 1 | 1 | 0 | 0 | 1 | signed overflow: neg-pos=pos |
| 4 | 0x7F | 0xFF | 0x80 | 1 | 0 | 0 | 0 | 1 | 1 | signed overflow: pos-neg=neg |
| 5 | 0x00 | 0x00 | 0x00 | 0 | 1 | 0 | 1 | 0 | 0 | zero-zero |

### SBB r8, r8 with CF pre-seed

| # | op1 | op2 | CF_in | Expected | CF_out | Notes |
|---|-----|-----|:-----:|----------|:------:|-------|
| 1 | 0x02 | 0x01 | 0 | 0x01 | 0 | normal |
| 2 | 0x02 | 0x01 | 1 | 0x00 | 0 | extra borrow |
| 3 | 0x00 | 0x00 | 1 | 0xFF | 1 | borrow from zero |

### CMP r8, r8

Same operand/result/flags as SUB, but **operand1 is NOT modified**.
After CMP, verify op1 is unchanged AND flags match SUB.

### NEG r8

| # | op1 | Expected | CF | PF | AF | ZF | SF | OF | Notes |
|---|-----|----------|:--:|:--:|:--:|:--:|:--:|:--:|-------|
| 1 | 0x01 | 0xFF | 1 | 0 | 1 | 0 | 1 | 0 | negate 1 |
| 2 | 0x00 | 0x00 | 0 | 1 | 0 | 1 | 0 | 0 | **CF = (operand != 0)** |
| 3 | 0x80 | 0x80 | 1 | 0 | 0 | 0 | 1 | 1 | INT_MIN negate = overflow |
| 4 | 0xFF | 0x01 | 1 | 0 | 1 | 0 | 0 | 0 | negate -1 |

### INC r8 — CF must NOT change

| # | op1 | CF_in | Expected | CF_out | OF | Notes |
|---|-----|:-----:|----------|:------:|:--:|-------|
| 1 | 0x01 | 0 | 0x02 | 0 | 0 | normal |
| 2 | 0xFF | 0 | 0x00 | 0 | 0 | wraps, CF preserved (not set!) |
| 3 | 0xFF | 1 | 0x00 | 1 | 0 | CF still 1 after INC |
| 4 | 0x7F | 0 | 0x80 | 0 | 1 | signed overflow |

> **Critical:** INC/DEC must NOT affect CF.  Test with CF=0 and CF=1 pre-seed.

### DEC r8 — CF must NOT change

| # | op1 | CF_in | Expected | CF_out | OF | Notes |
|---|-----|:-----:|----------|:------:|:--:|-------|
| 1 | 0x01 | 0 | 0x00 | 0 | 0 | normal |
| 2 | 0x00 | 0 | 0xFF | 0 | 0 | wraps, CF preserved |
| 3 | 0x80 | 0 | 0x7F | 0 | 1 | signed overflow |

### MUL r8 (undefined flags — GOLDEN)

| # | op1 (AL) | op2 | Result in AX | SF | ZF | AF | PF | Notes |
|---|---------|-----|-------------|:--:|:--:|:--:|:--:|-------|
| 1 | 0x00 | 0x00 | 0x0000 | golden | golden | golden | golden | all undefined — pin from golden |
| 2 | 0xFF | 0xFF | 0xFE01 | golden | golden | golden | golden | CF=OF=1 (AH!=0) |
| 3 | 0x02 | 0x03 | 0x0006 | golden | golden | golden | golden | CF=OF=0 (AH==0) |

> **Oracle:** SF/ZF/AF/PF are undefined after MUL.  Pin actual values from
> `data/vectors/golden_mul_flags.json` (per-generation).
> CF and OF ARE defined: set if upper half is non-zero.

### IMUL r8 (undefined flags — GOLDEN)

Same structure as MUL.  CF/OF defined (set if upper half != sign-extended lower).

### DIV r8 — #DE conditions

| # | AX | divisor | Expected | Notes |
|---|-----|---------|----------|-------|
| 1 | 0x0006 | 0x03 | AL=0x02, AH=0x00 | normal division |
| 2 | 0x0000 | 0x03 | AL=0x00, AH=0x00 | zero/divisor |
| 3 | 0x0001 | 0x00 | **#DE** | divide by zero |
| 4 | 0x0100 | 0x01 | **#DE** | quotient overflow (256 > 255) |

> **#DE return address:** 8086 pushes next-instruction address; 286+ pushes
> the DIV instruction's own address.  Verify in handler (golden per-gen).

### IDIV r8 — INT_MIN / -1

| # | AX | divisor | Expected | Notes |
|---|-----|---------|----------|-------|
| 1 | 0x0080 | 0xFF | **#DE** | INT_MIN / -1 = overflow |

## 16-bit Variants

Repeat the full matrix above with 16-bit operands (AX/BX instead of AL/BL).
Use the 16-bit value classes from the table.

## Addressing-Mode Coverage

For ADD only (representative), test these forms:
- `ADD AL, BL` (r8, r8)
- `ADD AL, [mem8]` (r8, m8)
- `ADD AL, imm8` (r8, imm8)
- `ADD AX, BX` (r16, r16)
- `ADD AX, [mem16]` (r16, m16)
- `ADD AX, imm16` (r16, imm16)

## Pre/Post State (representative cases)

### ADD r8, r8 — signed overflow corner

```
PRE:
  AL = 0x7F       (+127, max signed positive)
  BL = 0x01       (+1)
  FLAGS = 0x0000  (all clear seed)

  OP:  ADD AL, BL

POST:
  AL = 0x80       (result = -128, wrapped)
  BL = 0x01       (unchanged — ADD r/m, r)
  CF=0  PF=0  AF=1  ZF=0  SF=1  OF=1
  Rationale: pos+pos=neg → OF=1; bit3 carry-in → AF=1;
             0x80 has 1 one → odd → PF=0; result negative → SF=1
```

### ADD with memory operand

```
PRE:
  AL = 0xFF
  [DS:0x1000] = 0x01
  FLAGS = 0x0000

  OP:  ADD AL, [0x1000]

POST:
  AL = 0x00
  [DS:0x1000] = 0x01   (unchanged)
  CF=1  PF=1  AF=1  ZF=1  SF=0  OF=0
```

### SUB — signed overflow corner

```
PRE:
  AL = 0x80       (-128, min signed negative)
  BL = 0x01       (+1)
  FLAGS = 0x0000

  OP:  SUB AL, BL

POST:
  AL = 0x7F       (+127, wrapped)
  BL = 0x01       (unchanged)
  CF=0  PF=1  AF=1  ZF=0  SF=0  OF=1
  Rationale: neg-pos=pos → OF=1; no borrow-out → CF=0;
             0x7F has 7 ones → even → PF=1
```

### MUL r8 — undefined flags

```
PRE:
  AL = 0xFF       (255)
  BL = 0xFF       (255)
  FLAGS = 0x0000

  OP:  MUL BL

POST:
  AX = 0xFE01     (255 × 255 = 65025 = 0xFE01)
  BL = 0xFF       (unchanged)
  CF=1  OF=1      (AH != 0 → upper half nonzero)
  SF=golden  ZF=golden  AF=golden  PF=golden
```

### DIV — normal division

```
PRE:
  AX = 0x0006     (dividend)
  BL = 0x03       (divisor)
  FLAGS = 0x0000

  OP:  DIV BL

POST:
  AL = 0x02       (quotient = 6 / 3 = 2)
  AH = 0x00       (remainder = 0)
  BL = 0x03       (unchanged)
  FLAGS = undefined (all 6 flags undefined after DIV)
```

### DIV — #DE divide-by-zero

```
PRE:
  AX = 0x0001
  BL = 0x00
  FLAGS = 0x0000

  OP:  DIV BL

POST:
  #DE exception triggered (INT 0)
  Pushed CS:IP = return address (8086: next insn; 286+: DIV insn)
  AL, AH unchanged (exception taken before result written)
```

## State Save/Restore

- **Save:** AX, BX, CX, DX, FLAGS, DF
- **Restore:** via `RESTORE_STATE` macro
- **FPU:** not touched
- **Segment regs:** not touched
- **Memory:** uses scratch buffer in `.bss` only

## Known Divergences

| Behavior | 8086 | 286+ | Action |
|----------|------|------|--------|
| DIV #DE return addr | next insn | DIV insn | golden pin in handler |
| MUL/IMUL undefined flags | specific values | different values | golden per-gen |
| Shift count (not this module) | — | — | — |

## Pass/Fail Criteria

- **PASS:** all cases match expected result AND flags
- **FAIL:** result mismatch → `RECORD_FAILURE di, msg, expected, actual`
- **FAIL:** flag mismatch → `RECORD_FAILURE di, msg, expected_flags, actual_flags`
- **SKIP:** never (8086 tests run on all CPUs)
