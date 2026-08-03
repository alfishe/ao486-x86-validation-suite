# Spec: 80186 Smoke Test (CPU Detection)

## Metadata
- **Source file:** `src/cpu/80186/smoke.asm`
- **TIER:** UNIVERSAL | VENUE: G | GEN: 80186+ | ORACLE: manual
- **Impl-plan:** Phase 1, Level 0
- **Coverage:** [§5](../../coverage-matrix.md#5-cpu--80186-pri-3-thin-layer)

## Purpose

Detect 80186+ CPU presence before running 186-specific tests. The 80186 added
new instructions (ENTER, LEAVE, BOUND, INS, OUTS, PUSHA, POPA, IMUL imm, SHL/SHR/etc by imm8).
If any of these execute without #UD, CPU is 186+.

## Detection Method

```nasm
; Try PUSH immediate (186+ instruction)
; On 8086, this is an invalid opcode
    push 0x1234      ; 68 34 12 — #UD on 8086, works on 186+
```

Alternative: shift by immediate > 1:
```nasm
    mov al, 0x80
    shl al, 4        ; C0 E0 04 — #UD on 8086, works on 186+
```

## Test Cases

| # | Test | 8086 result | 186+ result | Detection |
|---|------|-------------|-------------|-----------|
| 1 | PUSH imm16 | #UD (INT 6) | executes | 186+ if no fault |
| 2 | SHL r8, imm8 | #UD (INT 6) | executes | 186+ if no fault |
| 3 | PUSHA | #UD (INT 6) | executes | 186+ if no fault |

## Pre/Post State

### PUSH immediate detection
```
PRE (real mode):
  INT 6 handler installed → sets detection flag = 0 (8086)
  Detection flag = 1 (assume 186+)

OP:  PUSH 0x1234

POST (8086):
  INT 6 triggered → handler sets flag = 0
  Detection flag = 0 → CPU is 8086

POST (186+):
  No exception
  SP -= 2, [SS:SP] = 0x1234
  Detection flag = 1 → CPU is 186+
```

## Pass/Fail Criteria

- **PASS:** detection method correctly identifies CPU as 8086 or 186+
- **FAIL:** misdetection (186 instruction faults on 186, or succeeds on 8086)
- **SKIP:** never (this is the gate for all 186+ tests)

## Known Divergences

- **NEC V20/V30:** compatible with 186 instruction set but not identical;
  this smoke test will report them as "186+".
