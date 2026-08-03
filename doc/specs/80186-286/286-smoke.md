# Spec: 80286 Smoke Test (CPU Detection)

## Metadata
- **Source file:** `src/cpu/80286/smoke.asm`
- **TIER:** UNIVERSAL | VENUE: G | GEN: 80286+ | ORACLE: manual
- **Impl-plan:** Phase 1, Level 0
- **Coverage:** [§6](../../coverage-matrix.md#6-cpu--80286-pri-1-for-pm-the-first-big-divergence-surface)

## Purpose

Detect 80286+ CPU presence. The 286 differs from 186 in FLAGS bits 12-15 behavior:
- 8086/186: bits 12-15 are always 1
- 286+ (real mode): bits 12-15 are always 0 (IOPL/NT cleared)

## Detection Method

```nasm
; Push FLAGS, check bits 12-15
    pushf
    pop ax
    and ax, 0xF000      ; isolate bits 12-15
    ; If AX == 0xF000 → 8086/186
    ; If AX == 0x0000 → 286+
```

## Test Cases

| # | Test | 8086/186 result | 286+ result | Detection |
|---|------|-----------------|-------------|-----------|
| 1 | PUSHF; check bits 12-15 | 0xF000 | 0x0000 | 286+ if bits clear |
| 2 | Try to set bits 12-15 | stays 0xF000 | stays 0x0000 | confirms |

## Pre/Post State

### FLAGS bits 12-15 detection
```
PRE (real mode):
  FLAGS = unknown

OP:  PUSHF
     POP AX
     AND AX, 0xF000

POST (8086/186):
  AX = 0xF000   ← bits 12-15 hardwired to 1

POST (286+):
  AX = 0x0000   ← bits 12-15 cleared in real mode
```

### Confirm by trying to set bits
```
PRE (real mode, 286+):
  FLAGS bits 12-15 = 0

OP:  PUSHF
     POP AX
     OR AX, 0xF000
     PUSH AX
     POPF
     PUSHF
     POP BX
     AND BX, 0xF000

POST (286+):
  BX = 0x0000   ← bits 12-15 cannot be set in real mode
```

## Pass/Fail Criteria

- **PASS:** detection method correctly identifies CPU as 186-or-below vs 286+
- **FAIL:** misdetection
- **SKIP:** never (this is the gate for all 286+ tests)

## Known Divergences

- **286 vs 386 in real mode:** both show bits 12-15 = 0; further tests needed
  to distinguish (see 386-smoke.md).
