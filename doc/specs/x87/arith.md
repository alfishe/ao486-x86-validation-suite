# Spec: FPU Arithmetic

## Metadata
- **Source file:** `src/fpu/8087/arith.asm`
- **TIER:** UNIVERSAL | VENUE: G+H | GEN: 8086+ | ORACLE: manual
- **Impl-plan:** Phase 3, area `FPU-Arith`
- **Coverage:** [§4](../../coverage-matrix.md#4-fpu--8087--287--387--486-pri-1-a-domain-of-its-own), [§4.2](../../coverage-matrix.md#42-hard-cases--precision-and-rounding)
- **Detail:** [prep-analysis §5](../../prep-analysis.md#5-fpu-corner-cases)

## Purpose

Verify FADD/FSUB/FMUL/FDIV with all rounding modes, precision settings, and
special-value combinations.  Compare 80-bit results via stored image, not
FCOMPP.

## Prerequisites

- FPU detected
- FNINIT at entry (CW=0x037F, rounding=nearest, precision=ext)

## Rounding Modes (test each operation with each mode)

| Mode | CW bits 10-11 | Symbol | Behavior |
|------|:-------------:|--------|----------|
| Nearest | 00 | →N | round to nearest even |
| Down | 01 | ↓ | round toward -∞ |
| Up | 10 | ↑ | round toward +∞ |
| Chop | 11 | →0 | truncate toward 0 |

### FADD rounding

| # | op1 | op2 | Mode | Expected (80-bit hex) | Notes |
|---|-----|-----|------|----------------------|-------|
| 1 | 1.0 | 1e-20 | nearest | 1.0 (absorbed) | tiny value lost |
| 2 | 1.0 | 1e-20 | up | 1.0+ulp | must round up |
| 3 | 1.0 | 1e-20 | down | 1.0 | rounds down (same) |
| 4 | 1.0 | 3e-1 | nearest | 1.333...3 (ext) | 1+1/3 |
| 5 | 1.0 | 3e-1 | chop | truncated | toward zero |

### Precision Control (CW bits 8-9)

| Precision | CW value | Mantissa bits | Notes |
|-----------|----------|:------------:|-------|
| Single (24) | 00 | 24 | results rounded to single |
| Double (53) | 01 | 53 | results rounded to double |
| Extended (64) | 11 | 64 | full precision (default) |

### FMUL precision test

| # | op1 | op2 | PC | Expected | Notes |
|---|-----|-----|----|----------|-------|
| 1 | π (ext) | 2.0 | ext | 2π exact (ext) | |
| 2 | π (ext) | 2.0 | single | 2π (rounded to 24-bit) | |

### Special value arithmetic (NaN, Inf, Zero)

| # | op1 | op2 | Op | Expected | Notes |
|---|-----|-----|----|----------|-------|
| 1 | +Inf | 1.0 | ADD | +Inf | |
| 2 | -Inf | 1.0 | ADD | -Inf | |
| 3 | +Inf | -Inf | ADD | **NaN** | Inf-Inf=invalid |
| 4 | 0.0 | 0.0 | MUL | 0.0 | |
| 5 | +Inf | 0.0 | MUL | **NaN** | Inf*0=invalid |
| 6 | 1.0 | 0.0 | DIV | +Inf | divide by zero (if unmasked) |
| 7 | NaN | 1.0 | any | NaN | QNaN propagates |
| 8 | SNaN | 1.0 | any | NaN | SNaN → QNaN + #IA |

### FSUB ordering matters

| # | op | ST(0) | ST(1) | Result in ST(0) | Notes |
|---|-----|-------|-------|-----------------|-------|
| 1 | FSUB | 5.0 | 3.0 | ST(0)=5-3=2.0 | ST(0) -= ST(1) |
| 2 | FSUBR | 5.0 | 3.0 | ST(0)=3-5=-2.0 | reversed |

## Pre/Post State (representative cases)

### FADD with rounding mode in CW

```
PRE:
  CW = 0x0B7F  (RC=10=round-up, PC=11=ext, all masks set)
  TOP = 7
  ST(0) = 1.0  = 3FFF 80000000 00000000
  ST(1) = 1e-20 (tiny)
  SW = 0x3800  (TOP=7, no exceptions)

  OP:  FADD ST(0), ST(1)

POST:
  ST(0) = 1.0 + 1 ULP  (round-up forces increment)
  SW: C1=1 (round-up occurred)
  TOP = 7 (unchanged — 2-op FADD doesn't pop)
```

### FADD — nearest rounding, absorbed

```
PRE:
  CW = 0x037F  (RC=00=nearest, default)
  TOP = 7
  ST(0) = 1.0
  ST(1) = 1e-20

  OP:  FADD ST(0), ST(1)

POST:
  ST(0) = 1.0  (tiny value absorbed, rounds to even)
  SW: C1=0 (no rounding occurred), #PE may be set (inexact)
```

### FSUB — operand ordering

```
PRE:
  TOP = 7
  ST(0) = 5.0,  ST(1) = 3.0
  CW = 0x037F (default)

  OP:  FSUB ST(0), ST(1)    (ST(0) = ST(0) - ST(1))

POST:
  ST(0) = 2.0  (5.0 - 3.0)
  ST(1) = 3.0  (unchanged)
  TOP = 7

PRE:
  TOP = 7
  ST(0) = 5.0,  ST(1) = 3.0

  OP:  FSUBP ST(1), ST(0)   (ST(1) = ST(0) - ST(1), then pop)

POST:
  ST(0) = 2.0  (result moved to old ST(1) position after pop)
  TOP = 6 (popped)
```

### FMUL precision control

```
PRE:
  CW = 0x007F  (PC=00=single precision 24-bit)
  TOP = 7
  ST(0) = π (extended 80-bit)
  ST(1) = 2.0

  OP:  FMUL ST(0), ST(1)

POST:
  ST(0) = 2π but rounded to 24-bit mantissa
  SW: #PE set (inexact, precision lost)
```

### Inf - Inf → QNaN (#IA)

```
PRE:
  CW = 0x037F (#IE masked)
  TOP = 7
  ST(0) = +Inf  = 7FFF 80000000 00000000
  ST(1) = -Inf  = FFFF 80000000 00000000

  OP:  FADD ST(0), ST(1)

POST:
  ST(0) = QNaN (Indefinite: FFFF C0000000 00000000)
  SW = #IE bit set (bit 0)
  C1=0
```

## State Save/Restore

- **Save:** full FPU state (108 bytes)
- **Restore:** FRSTOR

## Pass/Fail Criteria

- **PASS:** 80-bit result matches expected; C1 set if rounding occurred
- **FAIL:** result mismatch in any bit
- **SKIP:** FPU not detected
