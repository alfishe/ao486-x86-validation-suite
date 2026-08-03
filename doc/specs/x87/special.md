# Spec: FPU Special Values

## Metadata
- **Source file:** `src/fpu/8087/special.asm`
- **TIER:** UNIVERSAL | VENUE: G+H | GEN: 8086+ | ORACLE: manual + golden
- **Impl-plan:** Phase 3, area `FPU-Special`
- **Coverage:** [§4](../../coverage-matrix.md#4-fpu--8087--287--387--486-pri-1-a-domain-of-its-own), [§4.1](../../coverage-matrix.md#41-hard-cases--ieee-special-values)
- **Detail:** [prep-analysis §5](../../prep-analysis.md#5-fpu-corner-cases), [§1.2a](../../prep-analysis.md#12a-generation-specific-divergences-286-vs-386-vs-486)

## Purpose

Verify behavior with NaN (QNaN/SNaN), Inf (±), Zero (±), Denormals,
Pseudo-denormals.  This is where emulators most frequently go wrong.

## Test Cases

### QNaN propagation

| # | op1 | op2 | Op | Expected | Notes |
|---|-----|-----|----|----------|-------|
| 1 | QNaN | 1.0 | FADD | QNaN (same bits) | propagates unchanged |
| 2 | QNaN | +Inf | FMUL | QNaN | |
| 3 | 1.0 | QNaN | FSUB | QNaN | |

### SNaN → QNaN conversion

| # | op1 | op2 | Op | Expected | #IA? |
|---|-----|-----|----|----------|:----:|
| 1 | SNaN | 1.0 | FADD | QNaN (bit set) | yes |
| 2 | SNaN | QNaN | FADD | QNaN | yes |

> When SNaN is operand: result is QNaN (significand bit 63 set to 1), #IA raised.

### Infinity arithmetic (PROJECTIVE vs AFFINE)

| # | op1 | op2 | Op | 8087/287 (projective) | 387+ (affine) | Notes |
|---|-----|-----|----|----------------------|---------------|-------|
| 1 | +Inf | +Inf | FADD | +Inf | +Inf | |
| 2 | +Inf | -Inf | FADD | **NaN** | **NaN** | Inf-Inf=invalid |
| 3 | +Inf | +Inf | FSUB | **NaN** | **NaN** | Inf-Inf=invalid |
| 4 | -Inf | -Inf | FADD | -Inf | -Inf | |
| 5 | +Inf | +Inf | FMUL | +Inf | +Inf | |
| 6 | +Inf | -Inf | FMUL | **-Inf** | **-Inf** | |

> **Key divergence:** under projective (8087/287), +Inf and -Inf are the same
> point.  The practical difference is in FCOM: comparing +Inf vs -Inf returns
> "equal" on projective, "greater" on affine.  See [compare](compare.md).

### Zero arithmetic

| # | op1 | op2 | Op | Expected | Notes |
|---|-----|-----|----|----------|-------|
| 1 | +0 | +0 | ADD | +0 | |
| 2 | -0 | -0 | ADD | -0 | sign preserved |
| 3 | +0 | -0 | ADD | +0 | (rounding=nearest: +0) |
| 4 | +1.0 | +0 | MUL | +0 | |
| 5 | -1.0 | +0 | MUL | -0 | sign from xor |

### Signed zero in comparisons

| # | op1 | op2 | Expected C3:C2:C0 | Notes |
|---|-----|-----|:-----------------:|-------|
| 1 | +0 | -0 | C3=1 (equal) | |
| 2 | -0 | +0 | C3=1 (equal) | |

> +0 and -0 compare equal.  But their sign bits differ — verify via FXAM.

### Denormal handling

| # | Value | Action | Expected | Notes |
|---|-------|--------|----------|-------|
| 1 | denormal (ext) | FLD | loaded as denormal | |
| 2 | denormal × 2.0 | FMUL | normal or denormal | depends on exponent |
| 3 | result denormal | FMUL | **#DE if unmasked** | denormal exception |

### Pseudo-denormal (8087/287 only)

| # | Value | 8087/287 | 387+ | Notes |
|---|-------|----------|------|-------|
| 1 | pseudo-denormal FLD | supported | **#IA** or unsupported | 387+ rejects |

> Pseudo-denormals: exponent is non-zero (min normal) but integer bit is 0.
> These are valid on 8087/287, invalid on 387+.

## Pre/Post State (representative cases)

### QNaN propagation through FADD

```
PRE:
  CW = 0x037F  (#IE masked)
  TOP = 7
  ST(0) = QNaN  (7FFF C0000000 00000000)
  ST(1) = 1.0   (3FFF 80000000 00000000)

  OP:  FADD ST(0), ST(1)

POST:
  ST(0) = QNaN  (same bits: 7FFF C0000000 00000000)
  ST(1) = 1.0   (unchanged)
  SW: #IE NOT set  (QNaN does not raise #IE)
```

### SNaN → QNaN conversion

```
PRE:
  CW = 0x037F  (#IE masked)
  TOP = 7
  ST(0) = SNaN  (7FFF 40000000 00000000, bit63=0 → signaling)
  ST(1) = 1.0

  OP:  FADD ST(0), ST(1)

POST:
  ST(0) = QNaN  (7FFF C0000000 00000000, bit63 set → quiet)
  SW: #IE bit set  (SNaN detected → invalid operation)
```

### Signed zero arithmetic

```
PRE:
  CW = 0x037F  (RC=nearest)
  TOP = 7
  ST(0) = +0.0  (0000 00000000 00000000)
  ST(1) = -0.0  (8000 00000000 00000000)

  OP:  FADD ST(0), ST(1)   (+0 + -0)

POST:
  ST(0) = +0.0  (RC=nearest: +0; RC=down: -0)
  (sign of zero result depends on rounding mode)
```

### Denormal operand

```
PRE:
  CW = 0x037F  (#DE masked)
  TOP = 7
  ST(0) = denormal  (0000 C0000000 00000000, exp=0, integer bit=0)
  ST(1) = 2.0

  OP:  FMUL ST(0), ST(1)

POST:
  ST(0) = normal or denormal (depends on magnitude)
  SW: #DE bit set (bit 1)  — denormal operand detected
  If result fits in normal range: tag=00 (valid)
  If result still denormal: tag=00 (valid, but denormal)
```

### Pseudo-denormal (8087/287 only)

```
8087/287:
PRE:
  ST(0) = pseudo-denormal  (0001 40000000 00000000, exp=min but integer bit=0)
  OP:  FLD pseudo-denormal
POST:
  Loaded successfully, FXAM classifies specially
  SW: C3:C2:C1:C0 depends on sign (golden)

387+:
PRE:
  Same value
  OP:  FLD pseudo-denormal
POST:
  #IE raised (unsupported format on 387+)
  (387+ strictly validates the integer bit)
```

## State Save/Restore

- Full FPU state save/restore

## Known Divergences

| Behavior | 8087/287 | 387+ | Action |
|----------|----------|------|--------|
| Infinity model | projective | affine | golden for FCOM |
| Pseudo-denormal | supported | invalid | gen-gate |
| NaN payload | 64-bit preserved | 64-bit preserved | should match |

## Pass/Fail Criteria

- **PASS:** IEEE special value behavior matches manual; golden for projective/affine
- **SKIP:** FPU not detected
