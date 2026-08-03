# Spec: FPU Transcendental Functions

## Metadata
- **Source file:** `src/fpu/8087/trans.asm`
- **TIER:** UNIVERSAL | VENUE: G+H | GEN: 8086+ | ORACLE: manual + golden
- **Impl-plan:** Phase 3, area `FPU-Trans`
- **Coverage:** [§4.5](../../coverage-matrix.md#45-hard-cases--transcendentals)
- **Divergences:** [prep-analysis §1.2a](../../prep-analysis.md#12a-generation-specific-divergences-286-vs-386-vs-486)

## Purpose

Verify FSQRT, FSIN, FCOS, FSINCOS, FPTAN, FPATAN, F2XM1, FYL2X, FYL2XP1.
These are approximations — verify to within the documented precision
(< 1 ulp for most; FPTAN range-limited).

## Prerequisites

- FPU detected
- 387+ for FSIN/FCOS/FSINCOS (not on 8087/287)

## Test Cases

### FSQRT

| # | Input | Expected | Notes |
|---|-------|----------|-------|
| 1 | 4.0 | 2.0 | exact |
| 2 | 2.0 | 1.4142135... | within 1 ulp |
| 3 | 0.0 | 0.0 | |
| 4 | -1.0 | **NaN + #IA** | invalid |
| 5 | +Inf | +Inf | |

### FSIN (387+ only)

| # | Input | Expected | Notes |
|---|-------|----------|-------|
| 1 | 0.0 | 0.0 | exact |
| 2 | π/4 | 0.7071... | within 1 ulp |
| 3 | π/2 | 1.0 | |
| 4 | π | 0.0 | (approximate) |

> Range: |input| < 2^63. Outside this range, C2=1 (out of range, no result).

### FCOS (387+ only)

| # | Input | Expected | Notes |
|---|-------|----------|-------|
| 1 | 0.0 | 1.0 | exact |
| 2 | π/2 | 0.0 | |
| 3 | π | -1.0 | |

### FSINCOS (387+ only)

Computes both: ST(0)←sin, pushes cos.
Verify both values and that stack grew by 1.

### FPTAN (all gens)

| # | Input | Expected ST(0) | Expected ST(1) | Notes |
|---|-------|----------------|----------------|-------|
| 1 | 0.0 | 0.0 (tan=0) | 1.0 (pushed) | FPTAN always pushes 1.0 as ST(1) |
| 2 | π/4 | 1.0 (tan=1) | 1.0 | |

> FPTAN computes tan(θ), puts it in ST(0), pushes 1.0 into ST(1).
> The "1.0" allows division to get cotangent.  Range: |input| < 2^63.
> **8087/287:** only FPTAN (no FSIN/FCOS). To get sin, compute `FPTAN; FDIV`.

### FPATAN

| # | ST(0)=y | ST(1)=x | Expected arctan(y/x) | Notes |
|---|---------|---------|---------------------|-------|
| 1 | 1.0 | 1.0 | π/4 | |
| 2 | 0.0 | 1.0 | 0.0 | |
| 3 | 1.0 | 0.0 | π/2 | |

> FPATAN pops ST(0), result in ST(0) (=old ST(1)). Handles all 4 quadrants.

### F2XM1 (2^x - 1)

| # | Input | Expected | Notes |
|---|-------|----------|-------|
| 1 | 0.0 | 0.0 (2^0 - 1) | exact |
| 2 | 1.0 | 1.0 (2^1 - 1) | exact |
| 3 | -1.0 | -0.5 (2^-1 - 1) | exact |

> Range: -1.0 ≤ input ≤ +1.0.  For full 2^x, use FYL2X or decomposition.

### FYL2X (y × log2(x))

| # | ST(0)=x | ST(1)=y | Expected | Notes |
|---|---------|---------|----------|-------|
| 1 | 2.0 | 1.0 | 1.0 (log2(2)=1, 1×1=1) | exact |
| 2 | 8.0 | 1.0 | 3.0 | |
| 3 | 1.0 | 1.0 | 0.0 (log2(1)=0) | |
| 4 | 0.0 | 1.0 | -Inf + #Z | log(0) |

> x must be > 0. Pops ST(0), result in ST(0).

### FYL2XP1 (y × log2(x+1))

| # | ST(0)=x | ST(1)=y | Expected | Notes |
|---|---------|---------|----------|-------|
| 1 | 1.0 | 1.0 | 1.0 (log2(2)=1) | |
| 2 | 0.0 | 1.0 | 0.0 | |

> Used for accurate log near 1.  Range: 0 < |x| < 1 - √2/2.

## Pre/Post State (representative cases)

### FSQRT — exact result

```
PRE:
  CW = 0x037F (default)
  TOP = 7
  ST(0) = 4.0
  SW = 0x3800

  OP:  FSQRT

POST:
  ST(0) = 2.0
  TOP = 7 (FSQRT does not pop)
  SW: no exceptions set
```

### FSQRT — invalid (negative)

```
PRE:
  CW = 0x037F (#IE masked)
  TOP = 7
  ST(0) = -1.0

  OP:  FSQRT

POST:
  ST(0) = QNaN Indefinite (FFFF C0000000 00000000)
  SW: #IE bit set (bit 0)
```

### FSIN (387+) — range check

```
PRE:
  CW = 0x037F
  TOP = 7
  ST(0) = π/4
  SW = 0x3800

  OP:  FSIN

POST:
  ST(0) = 0.70710678... (within 1 ulp of sin(π/4))
  SW: C2=0 (in range, result valid)
  TOP = 7 (FSIN does not pop)

PRE:
  ST(0) = 2^63 + 1.0  (out of range)

  OP:  FSIN

POST:
  ST(0) = unchanged (operand not modified)
  SW: C2=1  (out of range, no result computed)
```

### FPTAN — pushes 1.0 as ST(1)

```
PRE:
  CW = 0x037F
  TOP = 7
  ST(0) = π/4
  TW: R7=00(valid), rest=11(empty)

  OP:  FPTAN

POST:
  TOP = 6  (decremented — a value was pushed!)
  ST(0) = 1.0  (the constant 1.0 that FPTAN always pushes)
  ST(1) = tan(π/4) = 1.0
  TW: R6=00(valid), R7=00(valid)
  (To get actual tan value: divide ST(1)/ST(0) via FDIVP)
```

### FPATAN — pops one operand

```
PRE:
  CW = 0x037F
  TOP = 7
  ST(0) = 1.0   (y)
  ST(1) = 1.0   (x)

  OP:  FPATAN

POST:
  TOP = 6  (popped ST(0), result in old ST(1) → now ST(0))
  ST(0) = π/4  (arctan(1.0/1.0))
```

### F2XM1 — range limited

```
PRE:
  CW = 0x037F
  TOP = 7
  ST(0) = 1.0

  OP:  F2XM1

POST:
  ST(0) = 1.0  (2^1 - 1 = 1.0, exact)
  TOP = 7 (no pop)
```

### FYL2X — pops and computes

```
PRE:
  CW = 0x037F
  TOP = 7
  ST(0) = 2.0   (x)
  ST(1) = 1.0   (y)

  OP:  FYL2X

POST:
  TOP = 6  (popped ST(0))
  ST(0) = 1.0  (y × log2(x) = 1.0 × log2(2.0) = 1.0 × 1 = 1.0)
```

## State Save/Restore

- Full FPU state save/restore

## Known Divergences

| Behavior | 8087/287 | 387+ | Action |
|----------|----------|------|--------|
| FSIN/FCOS/FSINCOS | unavailable | available | gen-gate SKIP |
| FSCALE accuracy | lower | higher | golden |
| FPTAN range check | C2 flag | C2 flag | same mechanism |

## Pass/Fail Criteria

- **PASS:** result within 1 ulp of reference; special values handled
- **FAIL:** result outside tolerance; C2 not set for out-of-range
- **SKIP:** FSIN/FCOS on 8087/287
