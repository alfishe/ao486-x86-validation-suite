# Spec: FPU Exceptions

## Metadata
- **Source file:** `src/fpu/8087/exception.asm`
- **TIER:** HARDWARE | VENUE: G | GEN: 8086+ | ORACLE: manual + golden
- **Impl-plan:** Phase 3, area `FPU-Exc`
- **Coverage:** [§4](../../coverage-matrix.md#4-fpu--8087--287--387--486-pri-1-a-domain-of-its-own), [§4.7](../../coverage-matrix.md#47-hard-cases--exception-delivery-and-fsavefrstor)
- **Detail:** [prep-analysis §5](../../prep-analysis.md#5-fpu-corner-cases), [§1.2a](../../prep-analysis.md#12a-generation-specific-divergences-286-vs-386-vs-486)

## Purpose

Verify the 6 FPU exceptions (#IM, #DM, #Z, #O, #U, #P) are detected,
reported in the status word, and (when unmasked) delivered to the CPU.

## Exception Types

| # | Mnemonic | Bit in SW | Name | Cause |
|---|----------|:---------:|------|-------|
| 0 | #IE / #IA | 0 | Invalid operation | NaN, Inf-Inf, stack overflow/underflow |
| 1 | #DE | 1 | Denormal operand | denormal input |
| 2 | #ZE | 2 | Divide by zero | 1.0 / 0.0 |
| 3 | #OE | 3 | Overflow | result exceeds max normal |
| 4 | #UE | 4 | Underflow | result too small + precision lost |
| 5 | #PE | 5 | Precision (inexact) | rounded result |

## Test Cases

### #IE — Invalid operation (masked)

| # | Action | Expected result | SW bit 0 | Notes |
|---|--------|----------------|:--------:|-------|
| 1 | FADD +Inf, -Inf | QNaN | set | |
| 2 | FMUL +Inf, 0.0 | QNaN | set | |
| 3 | FSQRT(-1.0) | QNaN | set | |
| 4 | FLD of empty stack | QNaN (old ST) | set | stack underflow |

### #ZE — Divide by zero (masked)

| # | Action | Expected | SW bit 2 | Notes |
|---|--------|----------|:--------:|-------|
| 1 | FDIV 1.0, +0.0 | +Inf | set | |
| 2 | FDIV -1.0, +0.0 | -Inf | set | |
| 3 | FDIV 0.0, 0.0 | **NaN** | set (#IE, not #ZE) | 0/0 is invalid, not div0 |

### #OE — Overflow (masked)

| # | Action | Expected | SW bit 3 | Notes |
|---|--------|----------|:--------:|-------|
| 1 | FMUL max_real, max_real | ±Inf | set | depends on rounding mode |

> Unmasked overflow delivers the "rounded" value (±Inf or ±max_real),
> depending on rounding mode. When masked, result is ±Inf.

### #UE — Underflow (masked)

| # | Action | Expected | SW bit 4 | Notes |
|---|--------|----------|:--------:|-------|
| 1 | FMUL min_real, 0.5 | denormal or 0 | set | |

> #UE is set only if: result is tiny (denormal range) AND precision was lost.
> If result is tiny but exact (e.g., ×2^−64 of exact), #UE is NOT set on some gens.

### #PE — Precision (masked)

| # | Action | Expected | SW bit 5 | Notes |
|---|--------|----------|:--------:|-------|
| 1 | FADD 1.0, 1e-20 | 1.0 (rounded) | set | result is inexact |

### Exception delivery (unmasked)

| # | Gen | Exception path | Notes |
|---|-----|---------------|-------|
| 1 | 8087 | IRQ via custom controller → INT 2 | hardware-dependent |
| 2 | 287 | IRQ13 → PIC → INT | depends on motherboard |
| 3 | 387 | IRQ13 (PC/AT) or internal #MF | 387 can be wired via IRQ13 |
| 4 | 486DX | **#MF (vector 16)** | internal, always #MF |

> **Gen-gate:** 486 uses #MF (vector 16).  Earlier gens use IRQ13.
> This is config-dependent — document the expected delivery path.

### Exception priority

When multiple exceptions occur simultaneously:
1. #IE (invalid) — highest
2. #DE (denormal)
3. #ZE (zero divide)
4. #OE (overflow)
5. #UE (underflow)
6. #PE (precision) — lowest

Test: construct an operation that triggers both #OE and #PE (overflow always
inexact). With both unmasked, #OE should be delivered.

## Pre/Post State (representative cases)

### #IE — Invalid operation (Inf - Inf)

```
PRE:
  CW = 0x037F  (#IE masked)
  TOP = 7
  ST(0) = +Inf  (7FFF 80000000 00000000)
  ST(1) = -Inf  (FFFF 80000000 00000000)
  SW = 0x3800  (TOP=7, all exception bits clear)

  OP:  FADD ST(0), ST(1)

POST:
  ST(0) = QNaN Indefinite  (FFFF C0000000 00000000)
  SW = 0x3801  (#IE bit set, bit 0)
  TOP = 7 (unchanged)
```

### #ZE — Divide by zero

```
PRE:
  CW = 0x037F  (#ZE masked)
  TOP = 7
  ST(0) = 1.0
  ST(1) = +0.0
  SW = 0x3800

  OP:  FDIV ST(0), ST(1)

POST:
  ST(0) = +Inf  (7FFF 80000000 00000000)
  SW = 0x3804  (#ZE bit set, bit 2)
```

### #OE — Overflow

```
PRE:
  CW = 0x037F  (#OE masked, RC=nearest)
  TOP = 7
  ST(0) = max_normal  (7FFE FFFFFFFFFFFFFFFF)
  ST(1) = max_normal

  OP:  FMUL ST(0), ST(1)

POST:
  ST(0) = +Inf
  SW = 0x3808  (#OE bit set, bit 3)
  #PE may also be set (overflow is always inexact)
```

### #UE — Underflow (387+ requires tiny+inexact)

```
PRE:
  CW = 0x037F  (#UE masked)
  TOP = 7
  ST(0) = min_normal  (0001 80000000 00000000)
  ST(1) = 0.5

  OP:  FMUL ST(0), ST(1)

POST:
  ST(0) = denormal  (precision lost → denormal)
  SW = 0x3810  (#UE bit set, bit 4)
  #PE also set (inexact)

  Note: if result is tiny but exact (no precision loss),
  387+ does NOT set #UE. 8087/287 may set #UE for tiny-only.
```

### #PE — Precision (inexact result)

```
PRE:
  CW = 0x037F  (#PE masked)
  TOP = 7
  ST(0) = 1.0
  ST(1) = 1/3 (extended, non-terminating)

  OP:  FADD ST(0), ST(1)

POST:
  ST(0) = 1.3333... (rounded to 64-bit)
  SW = 0x3820  (#PE bit set, bit 5)
  C1=1 (round-up occurred)
```

### Exception priority — #OE + #PE simultaneously

```
PRE:
  CW = 0x0377  (#OE and #PE unmasked, others masked)
  ST(0) = max_normal,  ST(1) = max_normal

  OP:  FMUL ST(0), ST(1)

POST:
  #OE delivered (higher priority than #PE)
  SW: #OE bit set AND #PE bit set, but #OE handler runs
```

## State Save/Restore

- **Save:** FPU state, original IRQ13/#MF handler, PIC masks
- **Restore:** FRSTOR, restore handler, restore PIC masks

## Known Divergences

| Behavior | 8087/287 | 387 | 486 | Action |
|----------|----------|-----|-----|--------|
| Delivery | IRQ | IRQ13 | #MF (vec 16) | gen+config |
| #UE trigger | tiny only | tiny+inexact | tiny+inexact | golden |

## Pass/Fail Criteria

- **PASS:** SW bits set correctly; masked exceptions produce expected values
- **FAIL:** exception not detected or wrong result
- **SKIP:** FPU not detected; unmasked delivery test skipped if handler unavailable
