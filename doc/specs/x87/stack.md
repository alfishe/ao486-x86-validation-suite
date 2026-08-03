# Spec: FPU Stack & Tag Word

## Metadata
- **Source file:** `src/fpu/8087/stack.asm`
- **TIER:** UNIVERSAL | VENUE: G+H | GEN: 8086+ | ORACLE: manual + golden
- **Impl-plan:** Phase 3, area `FPU-Stack`
- **Coverage:** [§4](../../coverage-matrix.md#4-fpu--8087--287--387--486-pri-1-a-domain-of-its-own), [§4.3](../../coverage-matrix.md#43-hard-cases--stack-management-and-tag-word)
- **Detail:** [prep-analysis §10](../../prep-analysis.md#10-fpu-state-image-format-detail)

## Purpose

Verify FPU register stack push/pop semantics, tag word maintenance,
stack overflow/underflow (#IS), and FXAM classification.

## Test Cases

### Stack push (FLD) — TOP decrements

| # | Before TOP | Action | After TOP | Notes |
|---|:----------:|--------|:---------:|-------|
| 1 | 0 | FLD 1.0 | 7 | wraps around |
| 2 | 4 | FLD 1.0 | 3 | normal |

### Stack pop (FSTP/FREE) — TOP increments

| # | Before TOP | Action | After TOP | Notes |
|---|:----------:|--------|:---------:|-------|
| 1 | 3 | FSTP [mem] | 4 | |
| 2 | 7 | FSTP [mem] | 0 | wraps |
| 3 | 3 | FFREE ST(0) | 4? No — FREE doesn't change TOP | just sets tag |

### Stack overflow (#IS)

| # | State | Action | Expected | Notes |
|---|-------|--------|----------|-------|
| 1 | 8 values loaded | FLD 1.0 | #IS, ST set in SW | stack overflow |

> On overflow: TOP decremented, ST set. If #IS masked, old ST(0) is overwritten
> with QNaN. If unmasked, exception handler called.

### Stack underflow (#IS)

| # | State | Action | Expected | Notes |
|---|-------|--------|----------|-------|
| 1 | empty stack | FSTP [mem] | #IS, ST set | reads garbage/QNaN |
| 2 | empty stack | FADD ST(1) | #IS | |

### Tag word

| Tag value | Meaning | How to trigger |
|-----------|---------|----------------|
| 00 | Valid | FLD of normal/denormal value |
| 01 | Zero | FLD of ±0 |
| 10 | Special | FLD of Inf/NaN |
| 11 | Empty | FNINIT or FFREE |

### FXAM classification

| # | ST(0) value | Expected C3:C2:C1:C0 | Class | Notes |
|---|-------------|:--------------------:|-------|-------|
| 1 | +1.0 | 0:0:0:0 | normal, positive | |
| 2 | -1.0 | 0:0:1:0 | normal, negative | C1=sign |
| 3 | +0 | 1:0:0:0 | zero, positive | |
| 4 | -0 | 1:0:1:0 | zero, negative | |
| 5 | +Inf | 0:1:0:0 | infinity, positive | |
| 6 | -Inf | 0:1:1:0 | infinity, negative | |
| 7 | QNaN | 0:1:0:1 | NaN | |
| 8 | SNaN | 0:0:0:1 | unsupported/SNaN | |
| 9 | denormal | 1:1:0:0 | denormal | |
| 10 | empty | 1:1:1:1 | empty | |

> **Divergence:** pseudo-denormal classification differs between 8087/287 and 387+.
> See [prep-analysis §1.2a](../../prep-analysis.md#12a-generation-specific-divergences-286-vs-386-vs-486).
> Pin C1 per-generation from golden.

## Pre/Post State (representative cases)

### Push sequence — TOP wraps

```
PRE:
  FNINIT state:
  SW = 0x0000  (TOP=0, all CCs clear, all exceptions clear)
  TW = 0xFFFF  (all 8 registers tagged empty=11)
  Physical R0=empty R1=empty ... R7=empty

  OP:  FLD1   (first push)
POST:
  SW = 0x3800  (TOP=7, i.e., bits 11-13 = 111b)
  TW = 0x3FFF  (R7 tagged valid=00, rest empty=11)
  Physical R7=1.0 → ST(0) at TOP=7

  OP:  FLDZ    (second push)
POST:
  SW = 0x3000  (TOP=6)
  TW = 0x2FFF  (R6=01(zero), R7=00(valid), rest=11(empty))
  ST(0)=+0.0 (R6), ST(1)=1.0 (R7)
```

### Pop sequence — tag set to empty

```
PRE:
  TOP = 6
  ST(0) = +0.0, ST(1) = 1.0
  TW: R6=01(zero), R7=00(valid)

  OP:  FSTP [mem]   (pop ST0)

POST:
  TOP = 7
  [mem] = 0.0
  TW: R6=11(empty), R7=00(valid)  ← R6 tagged empty after pop
  ST(0) = 1.0 (R7)
```

### Stack overflow (#IS) — 9th push

```
PRE:
  TOP = 0, all 8 regs valid
  SW = 0x0000 (TOP=0, no exceptions)
  TW = 0x0000 (all valid)

  OP:  FLD1  (9th push on full stack)

POST:
  SW = 0x0001  (#IE bit set, bit 0)
  TOP = 7 (decremented, wrapping to R7)
  R7 overwritten with QNaN (real 8087/287) or unchanged (387+ returns QNaN)
  TW: R7 tagged as before or special (gen-dependent)
  C1 = 0 (stack overflow: C1 indicates overflow direction)
```

### Stack underflow (#IS) — pop empty

```
PRE:
  TOP = 0, all regs empty
  TW = 0xFFFF (all empty)

  OP:  FSTP [mem]   (pop from empty stack)

POST:
  SW = 0x0001  (#IE bit set)
  [mem] = INDEF (QNaN 0x7FFF C090...) or indeterminate
  C1 = 1 (stack underflow direction)
```

### FXAM classification — C3:C2:C1:C0 in SW

```
PRE:
  ST(0) = +1.0
  SW condition codes: C3:C2:C1:C0 = 0:0:0:0 (arbitrary)

  OP:  FXAM

POST:
  SW bits: C3=0 C2=0 C1=0 C0=0  (normal, positive, sign=0)

PRE:
  ST(0) = -0.0
  OP:  FXAM
POST:
  SW bits: C3=1 C2=0 C1=1 C0=0  (zero, negative, sign=1)

PRE:
  ST(0) = QNaN
  OP:  FXAM
POST:
  SW bits: C3=0 C2=1 C1=0 C0=1  (NaN)

PRE:
  ST(0) = empty register
  OP:  FXAM
POST:
  SW bits: C3=1 C2=1 C1=1 C0=1  (empty)
```

## State Save/Restore

- Full FPU state (tag word is part of state image)

## Pass/Fail Criteria

- **PASS:** TOP changes correctly; tag word matches value type; #IS on overflow/underflow
- **SKIP:** FPU not detected
