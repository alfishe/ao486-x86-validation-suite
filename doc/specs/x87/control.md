# Spec: FPU Control Word & Environment

## Metadata
- **Source file:** `src/fpu/8087/control.asm`
- **TIER:** UNIVERSAL | VENUE: G+H | GEN: 8086+ | ORACLE: manual
- **Impl-plan:** Phase 3, area `FPU-Ctrl`
- **Coverage:** [§4](../../coverage-matrix.md#4-fpu--8087--287--387--486-pri-1-a-domain-of-its-own)

## Purpose

Verify FLDCW/FSTCW, FLDEXNV/FSTENV, and that exception masks, rounding mode,
and precision control take effect.

## Test Cases

### FLDCW / FSTCW round-trip

| # | CW value | Expected | Notes |
|---|----------|----------|-------|
| 1 | 0x037F | default after FNINIT | |
| 2 | 0x0000 | all masks clear, nearest, ext | |
| 3 | 0x0F7F | all masks set, chop, ext | |
| 4 | 0x027F | all masks set, down, ext | |

> After FLDCW, verify with FSTCW that the exact same value is read back.

### Exception masking takes effect

| # | Mask | Action | Masked result | Unmasked result |
|---|------|--------|--------------|-----------------|
| 1 | #Z masked | 1.0/0.0 | +Inf, no exception | #Z exception |
| 2 | #O masked | 1e300*1e300 | +Inf, #O in SW | #O exception |
| 3 | #IA masked | Inf-Inf | NaN, #IA in SW | #IA exception |
| 4 | #P masked | 1/3 | rounded, #P in SW | #P exception |

> Test each: set mask, perform op, verify result + SW bits.
> Then clear mask, perform same op, verify exception is delivered.

### Rounding mode takes effect

| # | RC | op1 | op2 | Op | Expected | Notes |
|---|:--:|-----|-----|----|----------|-------|
| 1 | nearest | 1.0 | 1e-18 | ADD | 1.0 | absorbs (rounds to even) |
| 2 | up | 1.0 | 1e-18 | ADD | 1.0+ulp | must round up |
| 3 | down | 1.0 | 1e-18 | ADD | 1.0 | rounds down |
| 4 | chop | 1.0 | 1e-18 | ADD | 1.0 | truncates |

### Precision control takes effect

| # | PC | op1 | op2 | Op | Expected | Notes |
|---|:--:|-----|-----|----|----------|-------|
| 1 | ext | 1.0 | 1/3 | ADD | 1.333... (64-bit) | full precision |
| 2 | double | 1.0 | 1/3 | ADD | 1.333... (53-bit) | rounded |
| 3 | single | 1.0 | 1/3 | ADD | 1.333...3 (24-bit) | heavily rounded |

### FSTENV / FLDENV

| # | Gen | Format | Size | Contents |
|---|-----|--------|------|----------|
| 1 | 8087/287 | 14 bytes (16-bit) | 14B | CW, SW, TW, IP, CS, DP, DS |
| 2 | 386+ (16-bit) | 14 bytes | 14B | same layout |
| 3 | 386+ (32-bit) | 28 bytes | 28B | expanded IP/DP with upper bits |

> Verify: FSTENV stores all 7 fields; FLDENV restores them.  Round-trip must
> produce identical state (modulo SW bits that reflect post-operation state).

## Pre/Post State (representative cases)

### FLDCW / FSTCW — round-trip

```
PRE:
  CW = 0x037F  (default after FNINIT: IM=1,DM=1,ZM=1,OM=1,UM=1,PM=1, PC=11, RC=00)

  OP:  FLDCW [mem]     where [mem] = 0x0F7F

POST:
  CW = 0x0F7F  (RC=11=chop, all masks set)

  OP:  FSTCW [mem2]
POST:
  [mem2] = 0x0F7F  (exact round-trip)
```

### Exception masking takes effect

```
PRE:
  CW = 0x037F  (#ZM=1, divide-by-zero masked)
  TOP = 7
  ST(0) = 1.0,  ST(1) = 0.0

  OP:  FDIV ST(0), ST(1)

POST:
  ST(0) = +Inf
  SW: #ZE bit set (bit 2)  — exception detected but masked
  No exception handler called

---

PRE:
  CW = 0x037B  (#ZM=0, divide-by-zero UNmasked)
  TOP = 7
  ST(0) = 1.0,  ST(1) = 0.0

  OP:  FDIV ST(0), ST(1)

POST:
  Exception handler invoked (#MF on 486, IRQ13 on 387)
  ST(0) unchanged (result not written on unmasked exception)
```

### Rounding mode affects arithmetic

```
PRE:
  CW = 0x0B7F  (RC=10=round toward +∞)
  ST(0) = 1.0,  ST(1) = 1e-20

  OP:  FADD ST(0), ST(1)

POST:
  ST(0) = 1.0 + 1 ULP  (forced round-up)
  SW: C1=1 (round-up occurred)

---

PRE:
  CW = 0x077F  (RC=01=round toward -∞)
  ST(0) = 1.0,  ST(1) = 1e-20

  OP:  FADD ST(0), ST(1)

POST:
  ST(0) = 1.0  (rounds down, tiny absorbed)
  SW: C1=0
```

### FSTENV / FLDENV — 7-field save

```
PRE (8087/287, 16-bit mode):
  CW = 0x037F,  SW = 0x3801,  TW = 0x3FFF
  Buffer at DS:0x1000 = uninitialized

  OP:  FSTENV [0x1000]

POST:
  [0x1000] = 0x037F   (CW)
  [0x1002] = 0x3801   (SW)
  [0x1004] = 0x3FFF   (TW)
  [0x1006] = FIP offset
  [0x1008] = FCS selector
  [0x100A] = FDP offset
  [0x100C] = FDS selector
  Total: 14 bytes written
  FPU still operational (unlike FSAVE, FSTENV does NOT initialize)
```

## State Save/Restore

- **Save:** full FPU state (including CW — it's modified by FLDCW)
- **Restore:** FRSTOR

## Pass/Fail Criteria

- **PASS:** CW/ENV round-trip exact; masks/rounding/precision take effect
- **FAIL:** mask not respected, or rounding mode ignored
- **SKIP:** FPU not detected
