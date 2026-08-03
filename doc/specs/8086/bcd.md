# Spec: 8086 BCD Instructions

## Metadata
- **Source file:** `src/cpu/8086/bcd.asm`
- **TIER:** UNIVERSAL
- **VENUE:** G + H (oracle)
- **GEN:** 8086+
- **ORACLE:** manual + golden (undefined flags)
- **Impl-plan:** Phase 2, area `8086-BCD`
- **Coverage:** [§3.2](../../coverage-matrix.md#32-hard-cases--arithmetic-edge-cases), [§3.3](../../coverage-matrix.md#33-hard-cases--encoding--decoding)
- **Divergences:** [prep-analysis §1.2](../../prep-analysis.md#12-behavioral-divergences-same-instruction-different-result)
- **Golden:** `data/vectors/golden_bcd_flags.json`

## Purpose

Verify AAA/AAS/AAM/AAD/DAA/DAS — correct result, AF/CF adjustment, and
**undefined flags pinned from golden**.  Also test the undocumented
non-10 immediate for AAM/AAD.

## Test Cases

### DAA (packed BCD adjust after ADD)

| # | AL_before | AF_before | CF_before | Expected AL | AF_after | CF_after | Notes |
|---|-----------|:---------:|:---------:|------------|:--------:|:--------:|-------|
| 1 | 0x46 | 0 | 0 | 0x46 | 0 | 0 | no adjustment needed |
| 2 | 0x3A | 1 | 0 | 0x40 | 0 | 0 | low nibble > 9 → +6 |
| 3 | 0xA0 | 0 | 1 | 0x00 | 0 | 1 | high nibble > 9 → +0x60 |
| 4 | 0xAA | 1 | 1 | 0x10 | 1 | 1 | both nibbles adjust |

> SF/ZF/PF are defined from result.  OF is **undefined** — pin golden.

### DAS (packed BCD adjust after SUB)

| # | AL_before | AF_before | CF_before | Expected AL | AF_after | CF_after | Notes |
|---|-----------|:---------:|:---------:|------------|:--------:|:--------:|-------|
| 1 | 0x46 | 0 | 0 | 0x46 | 0 | 0 | no adjustment |
| 2 | 0x0A | 1 | 0 | 0x04 | 1 | 0 | low nibble borrow → -6 |
| 3 | 0xA0 | 0 | 1 | 0x40 | 0 | 1 | high nibble borrow → -0x60 |

### AAA (ASCII adjust after ADD)

| # | AL_before | AF_before | Expected AL | AH_adjust | AF_after | CF_after | Notes |
|---|-----------|:---------:|------------|:---------:|:--------:|:--------:|-------|
| 1 | 0x09 | 0 | 0x09 | none | 0 | 0 | no adjust |
| 2 | 0x0A | 0 | 0x00 | AH+=1 | 1 | 1 | low nibble > 9 |
| 3 | 0x0A | 1 | 0x00 | AH+=1 | 1 | 1 | AF set → adjust |

> AAA clears high nibble of AL.  SF/ZF/PF/OF undefined — pin golden.

### AAS (ASCII adjust after SUB)

| # | AL_before | AF_before | Expected AL | AH_adjust | AF_after | CF_after |
|---|-----------|:---------:|------------|:---------:|:--------:|:--------:|
| 1 | 0x09 | 0 | 0x09 | none | 0 | 0 |
| 2 | 0x00 | 1 | 0x0A | AH-=1 | 1 | 1 |

### AAM (ASCII adjust after MUL)

| # | AL_before | imm byte | Expected AX | Notes |
|---|-----------|:--------:|------------|-------|
| 1 | 0x06 | 0x0A (default) | AH=0, AL=0x06 | 6/10=0 rem 6 |
| 2 | 0xFF | 0x0A | AH=0x19, AL=0x05 | 255/10=25 rem 5 |
| 3 | 0xFF | 0x08 | AH=0x1F, AL=0x07 | **non-10 imm**: 255/8=31 rem 7 |
| 4 | 0xFF | 0x10 | AH=0x0F, AL=0x0F | **non-10 imm**: 255/16=15 rem 15 |

> Encoding: `D4 imm8`.  Default is `D4 0A`.  Test `D4 08`, `D4 10`, `D5 02`.
> OF/CF/AF undefined — pin golden.

### AAD (ASCII adjust before DIV)

| # | AX_before | imm byte | Expected AX | Notes |
|---|-----------|:--------:|------------|-------|
| 1 | AH=0x02, AL=0x05 | 0x0A | 0x0019 | 2*10+5=25 |
| 2 | AH=0x01, AL=0x0F | 0x0A | 0x0019 | 1*10+15=25 |
| 3 | AH=0x03, AL=0x02 | 0x08 | 0x001A | **non-10 imm**: 3*8+2=26 |

> Encoding: `D5 imm8`.

## Pre/Post State (representative cases)

### DAA — both nibbles adjust

```
PRE:
  AL = 0xAA
  AF = 1, CF = 1   (pre-seeded via STC + OR FLAGS,FLAG_AF)
  FLAGS image = 0x...11

  OP:  DAA

POST:
  AL = 0x10        (0xAA + 0x06 + 0x60 = 0x110 → AL=0x10, carry consumed)
  AF = 1, CF = 1
  SF/ZF/PF defined from result (0x10)
  OF = golden      (undefined)
```

### DAS — low nibble borrow

```
PRE:
  AL = 0x0A
  AF = 1, CF = 0   (pre-seeded)

  OP:  DAS

POST:
  AL = 0x04        (0x0A - 0x06 = 0x04, low-nibble adjustment)
  AF = 1, CF = 0
  OF = golden
```

### AAA — AH incremented, AL cleared

```
PRE:
  AX = 0x000A     (AH=0x00, AL=0x0A)
  AF = 0

  OP:  AAA

POST:
  AX = 0x0100     (AH = 0x01 incremented, AL = 0x00 high nibble cleared)
  AF = 1, CF = 1
  SF/ZF/PF/OF = golden   (all undefined after AAA)
```

### AAS — AH decremented

```
PRE:
  AX = 0x0000     (AH=0x00, AL=0x00)
  AF = 1

  OP:  AAS

POST:
  AX = 0xFF0A     (AH = 0xFF decremented, AL = 0x0A after adjustment)
  AF = 1, CF = 1
  SF/ZF/PF/OF = golden
```

### AAM — default base 10

```
PRE:
  AX = 0x00FF     (AH=0x00, AL=0xFF=255)
  FLAGS = 0x0000

  OP:  AAM         (D4 0A)

POST:
  AX = 0x1905     (AH = 25 = 0x19, AL = 5 = 0x05; 255/10 = 25 rem 5)
  SF/ZF/PF defined from AL result (0x05)
  OF/CF/AF = golden
```

### AAD — non-10 immediate

```
PRE:
  AX = 0x0302     (AH=0x03, AL=0x02)
  FLAGS = 0x0000

  OP:  AAD 8       (D5 08 — base 8)

POST:
  AX = 0x001A     (3*8 + 2 = 26 = 0x1A)
  SF=0 ZF=0 PF=0   (0x1A = 00011010, 3 ones → odd → PF=0)
  CF/AF/OF = golden
```

## State Save/Restore

- **Save:** AX, FLAGS (AF and CF are critical inputs)
- **Restore:** `RESTORE_STATE`
- Pre-seed AF/CF before each test case using `stc`/`clc`/`pushf`/`popf`.

## Known Divergences

All undefined flags (OF, SF, ZF, PF for AAA/AAS; OF for DAA/DAS; OF/CF/AF for AAM/AAD)
vary across generations.  Pin per-gen golden.

## Pass/Fail Criteria

- **PASS:** result + defined flags match; undefined flags match golden
- **FAIL:** any mismatch
- **SKIP:** never
