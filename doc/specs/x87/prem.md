# Spec: FPREM / FPREM1

## Metadata
- **Source file:** `src/fpu/8087/prem.asm`
- **TIER:** UNIVERSAL | VENUE: G+H | GEN: 8086+ | ORACLE: manual
- **Impl-plan:** Phase 3, area `FPU-PREM`
- **Coverage:** [§4.6](../../coverage-matrix.md#46-hard-cases--fpremfprem1)
- **Divergences:** [prep-analysis §1.2a](../../prep-analysis.md#12a-generation-specific-divergences-286-vs-386-vs-486)

## Purpose

Verify FPREM and FPREM1 — IEEE remainder vs partial remainder.
These are iterative operations; verify the C2 "incomplete" flag and
multi-step reduction.

## Test Cases

### FPREM (8087+)

| # | ST(0)=dividend | ST(1)=divisor | Expected remainder | Q | Notes |
|---|----------------|---------------|-------------------|:---:|-------|
| 1 | 7.0 | 3.0 | 1.0 | 2 | simple |
| 2 | 7.5 | 3.0 | 1.5 | 2 | |
| 3 | -7.0 | 3.0 | -1.0 | -2 | sign follows dividend |

### FPREM1 (387+)

| # | ST(0) | ST(1) | Expected | Notes |
|---|-------|-------|----------|-------|
| 1 | 7.0 | 3.0 | -2.0 | IEEE: rounds to nearest, result in [-1.5, 1.5] |
| 2 | 8.0 | 3.0 | -1.0 | 8 = 3×3 - 1 |

> **Key difference:** FPREM truncates quotient; FPREM1 rounds to nearest.
> FPREM remainder has sign of dividend; FPREM1 can differ.

### Multi-step reduction (large dividend)

| # | ST(0) | ST(1) | Iterations | C2 | Notes |
|---|-------|-------|:----------:|:--:|-------|
| 1 | 1e100 | 1.0 | multiple | set then clear | C2=1 until done |

> FPREM reduces by up to 64 bits per iteration. For very large exponents,
> C2 is set to indicate "incomplete" — caller must loop. Test that:
> 1. C2=1 when partial reduction performed
> 2. Eventually C2=0 when complete
> 3. The final remainder is correct

### C3:C1 quotient bits

After FPREM completes (C2=0), bits C3:C1 contain the low 3 bits of Q:

| Q mod 8 | C3 | C1 | C0 |
|---------|:--:|:--:|:--:|
| 0 | 0 | 0 | 0 |
| 1 | 0 | 0 | 1 |
| 2 | 0 | 1 | 0 |
| ... | | | |
| 7 | 1 | 1 | 1 |

> These bits are used for argument reduction in trig functions.

### Special values

| # | ST(0) | ST(1) | Expected | Notes |
|---|-------|-------|----------|-------|
| 1 | Inf | 1.0 | NaN + #IA | invalid |
| 2 | 1.0 | 0.0 | NaN + #IA | div by zero in remainder |
| 3 | 1.0 | Inf | 1.0 (no reduction) | ST(1) > ST(0) → no reduction |

## Pre/Post State (representative cases)

### FPREM — simple remainder

```
PRE:
  CW = 0x037F (default)
  TOP = 7
  ST(0) = 7.0   (dividend)
  ST(1) = 3.0   (divisor)
  SW = 0x3800   (TOP=7, no exceptions)

  OP:  FPREM

POST:
  ST(0) = 1.0   (7.0 mod 3.0 = 1.0)
  ST(1) = 3.0   (divisor unchanged)
  SW: C2=0 (complete), C3:C1:C0 = 0:1:0 (Q mod 8 = 2)
  TOP = 7 (FPREM does NOT pop)
```

### FPREM — sign follows dividend

```
PRE:
  TOP = 7
  ST(0) = -7.0
  ST(1) = 3.0

  OP:  FPREM

POST:
  ST(0) = -1.0  (sign of dividend preserved)
  SW: C2=0, Q=-2 → C3:C1:C0 = 0:1:1 (6 mod 8, Q encoded unsigned then bit-negated)
```

### FPREM — multi-step (C2=1 incomplete)

```
PRE:
  TOP = 7
  ST(0) = 1e100   (very large dividend)
  ST(1) = 1.0     (divisor)

  OP:  FPREM   (first iteration)

POST (partial):
  ST(0) = reduced (but still > divisor)
  SW: C2=1  (incomplete — caller must loop)

  OP:  FPREM   (repeat)

POST (after multiple iterations):
  ST(0) = 0.0   (fully reduced)
  SW: C2=0  (complete)
```

### FPREM1 — IEEE remainder (387+)

```
PRE:
  TOP = 7
  ST(0) = 7.0
  ST(1) = 3.0

  OP:  FPREM1

POST:
  ST(0) = -2.0   (IEEE rounds quotient to nearest: 7 = 3×3 - 2)
  (FPREM would give +1.0 since 7 = 3×2 + 1)
  SW: C2=0
```

## State Save/Restore

- Full FPU state save/restore

## Known Divergences

| Behavior | 8087/287 | 387+ | Action |
|----------|----------|------|--------|
| FPREM1 | unavailable | available | gen-gate SKIP |
| Reduction step count | up to 64 | up to 64 | same |

## Pass/Fail Criteria

- **PASS:** remainder correct; C2 set/cleared correctly; Q bits match
- **FAIL:** wrong remainder or C2 handling
- **SKIP:** FPREM1 on 8087/287
