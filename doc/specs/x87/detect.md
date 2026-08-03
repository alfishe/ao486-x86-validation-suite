# Spec: FPU Detection & Capability

## Metadata
- **Source file:** `src/fpu/8087/detect.asm`
- **TIER:** HARDWARE | VENUE: G | GEN: 8086+ | ORACLE: golden
- **Impl-plan:** Phase 3, area `FPU-Detect`
- **Coverage:** [§4](../../coverage-matrix.md#4-fpu--8087--287--387--486-pri-1-a-domain-of-its-own)
- **Divergences:** [prep-analysis §5](../../prep-analysis.md#5-fpu-corner-cases), [§1.2a](../../prep-analysis.md#12a-generation-specific-divergences-286-vs-386-vs-486)

## Purpose

Detect FPU presence and type.  All subsequent FPU modules depend on this.

## Test Cases

### FNINIT + FSTCW (presence check)

| # | Action | Expected (FPU present) | Expected (no FPU) |
|---|--------|----------------------|-------------------|
| 1 | FNINIT | CW = 0x037F | CW unchanged / reads 0xFFFF |
| 2 | FSTCW [mem] | [mem] = 0x037F | [mem] = 0xFFFF or garbage |

> After FNINIT, CW must be exactly 0x037F:
> - Exception masks: all set (1s in bits 0-5)
> - Precision: double extended (bits 8-9 = 11b)
> - Rounding: nearest (bits 10-11 = 00b)

### FWAIT (status check)

| # | Action | Expected | Notes |
|---|--------|----------|-------|
| 1 | FWAIT after FNINIT | no exception | FPU operational |

### FPU type identification

| # | Test | 8087 | 287 | 387 | 486DX |
|---|------|------|-----|-----|-------|
| 1 | FWAIT/FNINIT + FWAIT check | works | works | works | works |
| 2 | Load +inf, compare with max-real | **projective** | affine | affine | affine |
| 3 | FSETPM (set PM) | no-op in RM | works | no-op (always PM) | no-op |
| 4 | DISNI check | present | absent | absent | absent |
| 5 | FNINIT then FLDENV of crafted env | 14-byte format | 14-byte | 28-byte | 28-byte |

### FPU not present (SKIP path)

| # | Action | Expected |
|---|--------|----------|
| 1 | read CW without FPU | 0xFFFF or unchanged |
| 2 | g_fpu_type = FPU_NONE | all FPU modules SKIP |

## Pre/Post State (representative cases)

### FNINIT + FSTCW — FPU presence check

```
PRE:
  CW = unknown (may be 0xFFFF if no FPU)
  g_fpu_type = FPU_UNKNOWN

  OP:  FNINIT
  OP:  FSTCW [0x1000]

POST (FPU present):
  CW = 0x037F
  [0x1000] = 0x037F
  g_fpu_type set to detected type

POST (no FPU):
  CW = 0xFFFF or unchanged
  [0x1000] = 0xFFFF or garbage
  g_fpu_type = FPU_NONE → all FPU modules SKIP
```

### FNINIT default state — full verification

```
PRE:
  FPU state = unknown/arbitrary

  OP:  FNINIT

POST:
  CW  = 0x037F  (IM=1 DM=1 ZM=1 OM=1 UM=1 PM=1 | PC=11 | RC=00)
  SW  = 0x0000  (all exception bits clear, all CCs clear, TOP=0)
  TW  = 0xFFFF  (all 8 registers tagged empty)
  Tag breakdown:
    R0=11(empty) R1=11(empty) R2=11(empty) R3=11(empty)
    R4=11(empty) R5=11(empty) R6=11(empty) R7=11(empty)
  FIP = 0x0000, FCS = 0x0000
  FDP = 0x0000, FDS = 0x0000
```

### FPU type — infinity model test

```
PRE:
  Stack empty, after FNINIT
  g_fpu_type unknown

  OP:  FLD1            ; ST(0) = 1.0
  OP:  FLDZ            ; ST(0) = +0.0, ST(1) = 1.0
  OP:  FLD1            ; ST(0) = 1.0
  OP:  FLD1            ; ST(0) = 1.0, ST(1) = 1.0
  OP:  FDIVP           ; ST(0) = 1.0/1.0 = 1.0, pop → ST(0)=1.0
  OP:  FLD1            ; ST(0) = 1.0
  OP:  FDIV            ; ... construct +Inf
  OP:  FLD1; FDIV ST(0),ST(0)  ; ST(0) = +Inf
  OP:  FLDZ            ; push 0.0
  OP:  FLD1; FDIV ST(0),ST(1)  ; ST(0) = +Inf
  OP:  FCHS            ; ST(0) = -Inf

  OP:  FCOM            ; compare ST(0)=-Inf with ST(1)=+Inf
  OP:  FSTSW AX

POST:
  8087/287 (projective): AX C3=1 → equal (+Inf == -Inf)
  387+   (affine):     AX C3=0 C0=1 → less (-Inf < +Inf)
```

## State Save/Restore

- **Save:** FPU state (108-byte buffer via FSAVE)
- **Restore:** FRSTOR

## Known Divergences

| Behavior | 8087 | 287 | 387 | 486 | Action |
|----------|------|-----|-----|-----|--------|
| Infinity model | projective | projective | affine | affine | FCOM ±Inf golden |
| Env save size | 14B | 14B | 28B | 28B | gen-gate format |
| Exception delivery | INT via IRQ | IRQ13 | IRQ13/#MF | #MF | gen+config |

## Pass/Fail Criteria

- **PASS:** FPU detected, type identified, CW=0x037F after FNINIT
- **SKIP:** no FPU detected → STATUS_SKIP for all FPU modules
