# Spec: FPU Compare

## Metadata
- **Source file:** `src/fpu/8087/compare.asm`
- **TIER:** UNIVERSAL | VENUE: G+H | GEN: 8086+ | ORACLE: manual + golden
- **Impl-plan:** Phase 3, area `FPU-Compare`
- **Coverage:** [§4](../../coverage-matrix.md#4-fpu--8087--287--387--486-pri-1-a-domain-of-its-own), [§4.4](../../coverage-matrix.md#44-hard-cases--comparison-and-condition-codes)
- **Divergences:** [prep-analysis §1.2a](../../prep-analysis.md#12a-generation-specific-divergences-286-vs-386-vs-486)

## Purpose

Verify FCOM/FCOMP/FCOMPP/FCOMI/FCOMIP/FUCOM/FUCOMP/FUCOMPP/FUCOMI/FUCOMIP.
Test condition code encoding (C3:C2:C0) and the projective-vs-affine
infinity comparison divergence.

## Condition Code Encoding

| Condition | C3 | C2 | C0 |
|-----------|:--:|:--:|:--:|
| ST(0) > op2 | 0 | 0 | 0 |
| ST(0) < op2 | 0 | 0 | 1 |
| ST(0) == op2 | 1 | 0 | 0 |
| Unordered | 1 | 1 | 1 |

## Test Cases

### Normal comparisons

| # | ST(0) | op2 | Expected C3:C2:C0 | Notes |
|---|-------|-----|:-----------------:|-------|
| 1 | 3.0 | 2.0 | 0:0:0 (greater) | |
| 2 | 2.0 | 3.0 | 0:0:1 (less) | |
| 3 | 3.0 | 3.0 | 1:0:0 (equal) | |

### Unordered (NaN operand)

| # | ST(0) | op2 | Expected C3:C2:C0 | #IA? | Notes |
|---|-------|-----|:-----------------:|:----:|-------|
| 1 | NaN | 1.0 | 1:1:1 (unordered) | yes (FCOM) | FCOM raises #IA |
| 2 | NaN | 1.0 | 1:1:1 (unordered) | no (FUCOM) | FUCOM does NOT raise #IA |

> **Key:** FCOM raises #IA when operand is NaN.  FUCOM does NOT.
> Both return C3:C2:C0 = 1:1:1 (unordered).

### Infinity comparison — projective vs affine

| # | ST(0) | op2 | 8087/287 (projective) | 387+ (affine) | Notes |
|---|-------|-----|:---------------------:|:-------------:|-------|
| 1 | +Inf | -Inf | **C3=1 (equal)** | C3=0,C0=0 (greater) | KEY DIVERGENCE |
| 2 | -Inf | +Inf | **C3=1 (equal)** | C3=0,C0=1 (less) | |
| 3 | +Inf | +Inf | C3=1 (equal) | C3=1 (equal) | same |

### Signed zero comparison

| # | ST(0) | op2 | Expected | Notes |
|---|-------|-----|----------|-------|
| 1 | +0 | -0 | C3=1 (equal) | signed zeros compare equal |
| 2 | -0 | +0 | C3=1 (equal) | |

### FCOMI/FCOMIP (writes to EFLAGS, 387+ only)

| # | Comparison | ZF | PF | CF | Notes |
|---|-----------|:--:|:--:|:--:|-------|
| 1 | ST(0) > op2 | 0 | 0 | 0 | |
| 2 | ST(0) < op2 | 0 | 0 | 1 | |
| 3 | ST(0) == op2 | 1 | 0 | 0 | |
| 4 | unordered | 1 | 1 | 1 | |

> FCOMI writes condition codes directly to ZF/PF/CF in EFLAGS.
> **Gen-gate:** FCOMI/FCOMIP are 387+ only. SKIP on 8087/287.

### Transferring C3:C2:C0 to AX

After FCOM: `FSTSW AX; SAHF` — then Jcc can test:
- C0 → CF (JB/JAE)
- C2 → PF (JP/JNP)
- C3 → ZF (JE/JNE)

## Pre/Post State (representative cases)

### FCOM — condition codes in SW

```
PRE:
  CW = 0x037F (#IE masked, default)
  TOP = 7
  ST(0) = 3.0
  ST(1) = 2.0
  SW CC bits: C3:C2:C1:C0 = 0:0:0:0 (arbitrary pre-state)

  OP:  FCOM ST(1)

POST:
  SW CC bits: C3=0 C2=0 C0=0  (ST(0) > ST(1))
  TOP = 7 (FCOM does not pop)
```

```
PRE:
  TOP = 7
  ST(0) = 2.0,  ST(1) = 3.0

  OP:  FCOM ST(1)

POST:
  SW: C3=0 C2=0 C0=1  (ST(0) < ST(1))
```

```
PRE:
  TOP = 7
  ST(0) = 3.0,  ST(1) = 3.0

  OP:  FCOM ST(1)

POST:
  SW: C3=1 C2=0 C0=0  (ST(0) == ST(1))
```

### FCOMP — pop after compare

```
PRE:
  TOP = 7
  ST(0) = 3.0,  ST(1) = 2.0

  OP:  FCOMP ST(1)

POST:
  SW: C3=0 C2=0 C0=0  (greater)
  TOP = 6  (popped: old ST(1) is now ST(0))
```

### FCOMPP — pop both

```
PRE:
  TOP = 7
  ST(0) = 3.0,  ST(1) = 2.0

  OP:  FCOMPP

POST:
  SW: C3=0 C2=0 C0=0
  TOP = 5  (popped both: old ST(2) is now ST(0))
```

### FCOM with NaN — unordered + #IA

```
PRE:
  CW = 0x037F (#IE masked)
  TOP = 7
  ST(0) = QNaN
  ST(1) = 1.0
  SW = 0x3800 (TOP=7, no exceptions)

  OP:  FCOM ST(1)

POST:
  SW: C3=1 C2=1 C0=1  (unordered)
  SW: #IE bit set (bit 0)
```

### FUCOM — unordered without #IA

```
PRE:
  CW = 0x037F
  TOP = 7
  ST(0) = QNaN (quiet)
  ST(1) = 1.0

  OP:  FUCOM ST(1)

POST:
  SW: C3=1 C2=1 C0=1  (unordered)
  SW: #IE NOT set  (FUCOM skips #IA for QNaN)
```

### Infinity comparison — projective vs affine divergence

```
8087/287 (projective):
PRE:
  ST(0) = +Inf,  ST(1) = -Inf
  OP:  FCOM ST(1)
POST:
  SW: C3=1 C2=0 C0=0  (EQUAL — +Inf == -Inf in projective model)

387+ (affine):
PRE:
  ST(0) = +Inf,  ST(1) = -Inf
  OP:  FCOM ST(1)
POST:
  SW: C3=0 C2=0 C0=0  (ST(0) > ST(1) — +Inf > -Inf in affine model)
```

### FCOMI — direct to EFLAGS (387+)

```
PRE:
  TOP = 7
  ST(0) = 3.0,  ST(1) = 2.0
  EFLAGS = 0x0000 (ZF=0, PF=0, CF=0)

  OP:  FCOMI ST(1)

POST:
  EFLAGS: ZF=0 PF=0 CF=0  (ST(0) > ST(1))
  (SW condition codes are NOT set by FCOMI)
  TOP = 7 (FCOMI does not pop)
```

## State Save/Restore

- Full FPU state save/restore

## Pass/Fail Criteria

- **PASS:** condition codes match expected for each comparison
- **FAIL:** wrong C3:C2:C0 or EFLAGS after FCOMI
- **SKIP:** FCOMI on pre-387
