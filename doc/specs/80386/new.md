# Spec: 386 New Instructions

## Metadata
- **Source file:** `src/cpu/80386/new.asm`
- **TIER:** UNIVERSAL | VENUE: G+H | GEN: 80386+ | ORACLE: manual
- **Impl-plan:** Phase 5, area `386-New`
- **Coverage:** [§7](../../coverage-matrix.md#7-cpu--80386-pri-1-32-bit--paging--v86)

## Purpose

Verify new 386 instructions: BITTEST/BITTRC/BITSET/BITCLR, BSF/BSR,
MOVZX/MOVSX, SETcc, SHLD/SHRD, CDQ/CWDE, LSS/LFS/LGS.

## Test Cases

### BT/BTS/BTR/BTC (bit test/set/reset/complement)

| # | Instruction | Base | Bit index | Expected CF | Result | Notes |
|---|-------------|------|:---------:|:-----------:|--------|-------|
| 1 | BT [mem], 5 | 0x00000020 | 5 | 1 | unchanged | bit 5 was set |
| 2 | BTS [mem], 0 | 0x00000000 | 0 | 0 | mem=0x00000001 | set bit 0 |
| 3 | BTR [mem], 5 | 0x00000020 | 5 | 1 | mem=0x00000000 | clear bit 5 |
| 4 | BTC [mem], 5 | 0x00000000 | 5 | 0 | mem=0x00000020 | complement |

> Bit index can exceed the operand size — it addresses into memory at
> `base + (index / 8)` with bit `(index % 8)`.

### BSF/BSR (bit scan forward/reverse)

| # | Instruction | Source | Expected ZF | Result | Notes |
|---|-------------|--------|:-----------:|--------|-------|
| 1 | BSF EAX, 0x00000008 | 8 | ZF=0 | EAX=3 | first set bit from LSB |
| 2 | BSR EAX, 0x00000008 | 8 | ZF=0 | EAX=3 | first set bit from MSB |
| 3 | BSF EAX, 0x00000000 | 0 | ZF=1 | EAX undefined | no set bits |

### MOVZX/MOVSX (zero/sign extend)

| # | Instruction | Source | Expected dest | Notes |
|---|-------------|--------|---------------|-------|
| 1 | MOVZX EAX, AL(0xFF) | 0xFF | EAX=0x000000FF | zero-extend 8→32 |
| 2 | MOVSX EAX, AL(0xFF) | 0xFF | EAX=0xFFFFFFFF | sign-extend 8→32 |
| 3 | MOVZX EAX, AX(0xFFFF) | 0xFFFF | EAX=0x0000FFFF | zero-extend 16→32 |
| 4 | MOVSX EAX, AX(0x8000) | 0x8000 | EAX=0xFFFF8000 | sign-extend 16→32 |

### SETcc (set byte on condition)

| # | Condition | Flag state | Result AL | Notes |
|---|-----------|-----------|-----------|-------|
| 1 | SETE | ZF=1 | AL=1 | |
| 2 | SETE | ZF=0 | AL=0 | |
| 3 | SETG | ZF=0, SF=OF | AL=1 | signed greater |

> Test all 16 conditions with pre-seeded flags.

### SHLD/SHRD (double-precision shift)

| # | Instruction | op1 | op2 | Count | Result | CF | Notes |
|---|-------------|-----|-----|:-----:|--------|:--:|-------|
| 1 | SHLD EAX, ECX, 4 | 0x12345678 | 0x9ABCDEF0 | 4 | 0x23456789 | 1 | shift left, fill from ECX |
| 2 | SHRD EAX, ECX, 4 | 0x12345678 | 0x9ABCDEF0 | 4 | 0x81234567 | 0 | shift right, fill from ECX |

> Count masking: CL & 0x1F (5 bits, same as single shifts).

### CWDE / CDQ

| # | Instruction | Input | Expected | Notes |
|---|-------------|-------|----------|-------|
| 1 | CWDE | AX=0xFF80 | EAX=0xFFFFFF80 | sign-extend AX→EAX |
| 2 | CDQ | EAX=0x80000000 | EDX=0xFFFFFFFF, EAX unchanged | sign-extend EAX→EDX:EAX |

### LSS/LFS/LGS (far pointer load with segment)

| # | Instruction | mem | Expected | Notes |
|---|-------------|-----|----------|-------|
| 1 | LSS ESP, [mem] | off=0x1000, seg=0x0010 | ESP=0x1000, SS=0x0010 | load SS:ESP |
| 2 | LFS EAX, [mem] | off=0x2000, seg=0x0020 | EAX=0x2000, FS=0x0020 | |
| 3 | LGS EAX, [mem] | off=0x3000, seg=0x0030 | EAX=0x3000, GS=0x0030 | |

## Pre/Post State (representative cases)

### BT — bit test, load CF
PRE:
  EAX = 0x00000020   (bit 5 set)
  FLAGS = 0x0000     (CF=0 seed)
OP:  BT EAX, 5
POST:
  CF = 1             ← bit 5 was set
  EAX = 0x00000020   ← unchanged (BT is read-only)
  Other flags unchanged

### BTS — bit test and set
PRE:
  mem dword at [EBX] = 0x00000000
  FLAGS = 0x0000
OP:  BTS DWORD [EBX], 0
POST:
  CF = 0             ← bit 0 was clear before
  mem = 0x00000001   ← bit 0 now set

### BTR — bit test and reset
PRE:
  mem dword at [EBX] = 0x00000020   (bit 5 set)
  FLAGS = 0x0000
OP:  BTR DWORD [EBX], 5
POST:
  CF = 1             ← bit 5 was set before
  mem = 0x00000000   ← bit 5 now cleared

### BSF — bit scan forward
PRE:
  ECX = 0x00000100   (bit 8 is first set bit)
  EAX = 0x00000000   (undefined)
  FLAGS = 0x0000
OP:  BSF EAX, ECX
POST:
  EAX = 8            ← index of first set bit from LSB
  ZF = 0             ← source was non-zero

### BSF on zero source
PRE:
  ECX = 0x00000000
  EAX = 0xDEADBEEF
  FLAGS = 0x0000
OP:  BSF EAX, ECX
POST:
  ZF = 1             ← source is zero
  EAX = 0xDEADBEEF   ← UNDEFINED; CPU may or may not modify

### MOVZX — zero extend 8→32
PRE:
  AL = 0xFF
  EAX = 0x123456FF
OP:  MOVZX EAX, AL
POST:
  EAX = 0x000000FF   ← upper 24 bits zeroed

### MOVSX — sign extend 8→32
PRE:
  AL = 0xFF          (-1 signed)
  EAX = 0x123456FF
OP:  MOVSX EAX, AL
POST:
  EAX = 0xFFFFFFFF   ← sign-extended (0xFF has bit7=1)

### MOVSX — sign extend 16→32 (positive)
PRE:
  AX = 0x7FFF        (+32767)
  EAX = 0x00007FFF
OP:  MOVSX EAX, AX
POST:
  EAX = 0x00007FFF   ← sign bit 0, upper 16 zeroed

### SETcc — set byte on condition
PRE:
  FLAGS = 0x0040     (ZF=1 bit6)
  AL = 0x00
OP:  SETE AL         (set if ZF=1)
POST:
  AL = 0x01          ← ZF was set

PRE:
  FLAGS = 0x0000     (ZF=0)
  AL = 0xFF
OP:  SETE AL
POST:
  AL = 0x00          ← ZF was clear

### SHLD — double-precision shift left
PRE:
  EAX = 0x12345678
  ECX = 0x9ABCDEF0
  FLAGS = 0x0000
OP:  SHLD EAX, ECX, 4
POST:
  EAX = 0x23456789   ← shifted left 4, filled with top 4 bits of ECX (0x9)
  CF = 1             ← bit 28 of original EAX (0x12345678) was 1, last bit shifted out

### SHRD — double-precision shift right
PRE:
  EAX = 0x12345678
  ECX = 0x9ABCDEF0
  FLAGS = 0x0000
OP:  SHRD EAX, ECX, 4
POST:
  EAX = 0x81234567   ← shifted right 4, filled with top 4 bits of ECX (0x9)
  CF = 1             ← bit 3 of original EAX (0x12345678) was 1, last bit shifted out

### CWDE — sign extend AX to EAX
PRE:
  AX = 0xFF80        (-128 signed)
  EAX = 0x0000FF80
OP:  CWDE
POST:
  EAX = 0xFFFFFF80   ← sign-extended (bit15=1)

### CDQ — sign extend EAX to EDX:EAX
PRE:
  EAX = 0x80000000   (negative: MSB=1)
  EDX = 0x00000000
OP:  CDQ
POST:
  EDX = 0xFFFFFFFF   ← sign-extended to EDX
  EAX = 0x80000000   ← unchanged

### LSS — load SS:ESP far pointer
PRE:
  mem at [EBX]: offset=0x00001000, segment=0x0010
  SS:ESP = old values
OP:  LSS ESP, [EBX]
POST:
  ESP = 0x00001000
  SS  = 0x0010        ← both loaded atomically

## State Save/Restore

- **Save:** all GPRs, FLAGS, FS, GS, SS
- **Restore:** `RESTORE_STATE`

## Pass/Fail Criteria

- **PASS:** all new instructions produce correct results + flags
- **FAIL:** any incorrect bit operation or sign extension
- **SKIP:** GEN < 80386
