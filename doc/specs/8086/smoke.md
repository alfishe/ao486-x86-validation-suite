# Spec: 8086 Smoke Test

## Metadata
- **Source file:** `src/cpu/8086/smoke.asm`
- **TIER:** UNIVERSAL
- **VENUE:** G + H (oracle)
- **GEN:** 8086+
- **ORACLE:** manual
- **Impl-plan:** Phase 2, area `8086-Smoke`
- **Coverage:** [§3](../../coverage-matrix.md#3-cpu--80868088-pri-1-foundation) Wave 0
- **Pattern:** [adding-tests.md](../../adding-tests.md)

## Purpose

Minimum-viability execution: prove the test framework boots, runs a test
function, and returns a status code.  If this fails, nothing else matters.

## Prerequisites

- Framework runner is operational (`runner_init`, `runner_exec_tests`)
- Output shim works (at least console)
- `detect_cpu` returns a valid value in `g_cpu_type`

## Test Cases

### test_nop_execution
- **Setup:** none
- **Action:** execute a single `NOP`
- **Expected:** no exception, IP advances by 1
- **Pass:** STATUS_PASS

### test_register_identity
- **Setup:** none
- **Action:** `mov ax, 0x1234` then `mov bx, ax`
- **Expected:** BX == 0x1234
- **Pass:** STATUS_PASS; **Fail:** STATUS_FAIL + message "register identity failed"

### test_basic_arithmetic
- **Setup:** none
- **Action:** `mov al, 1` / `mov bl, 1` / `add al, bl`
- **Expected:** AL == 2, CF=0, ZF=0
- **Pass:** STATUS_PASS

### test_memory_rw
- **Setup:** none
- **Action:** `mov byte [0x0000], 0xAA` / `mov al, [0x0000]`
- **Expected:** AL == 0xAA
- **Pass:** STATUS_PASS
- **Note:** use a scratch address that doesn't clobber IVT or framework data

### test_flag_set_clear
- **Setup:** none
- **Action:** `stc` / `jc .pass` / `.pass: clc` / `jnc .done`
- **Expected:** CF set then cleared correctly
- **Pass:** STATUS_PASS

### test_cpu_detection
- **Setup:** `g_cpu_type` populated by detect_cpu
- **Action:** read `g_cpu_type`
- **Expected:** value >= CPU_8086 (0)
- **Pass:** STATUS_PASS; **Skip:** STATUS_SKIP if detection returned invalid value

## Pre/Post State (representative cases)

### test_register_identity

```
PRE:
  AX = 0x????, BX = 0x????
  OP:  MOV AX, 0x1234 ; MOV BX, AX
POST:
  AX = 0x1234
  BX = 0x1234
```

### test_basic_arithmetic

```
PRE:
  AL = 0x??, BL = 0x??
  FLAGS = 0x????
  OP:  MOV AL, 1 ; MOV BL, 1 ; ADD AL, BL
POST:
  AL = 0x02, BL = 0x01
  CF=0 PF=0 AF=0 ZF=0 SF=0 OF=0
  (0x02 = 00000010, 1 one → odd → PF=0)
```

### test_memory_rw

```
PRE:
  AL = 0x??
  [DS:0x0100] = 0x??
  OP:  MOV byte [0x0100], 0xAA ; MOV AL, [0x0100]
POST:
  AL = 0xAA
  [DS:0x0100] = 0xAA
```

### test_flag_set_clear

```
PRE:
  FLAGS = 0x0002
  OP:  STC
POST: FLAGS = 0x0003 (CF=1)
  OP:  JC .pass          (jump taken → CF verified set)
  OP:  CLC
POST: FLAGS = 0x0002 (CF=0)
  OP:  JNC .done         (jump taken → CF verified clear)
```

## State Save/Restore

None — this module is read-only and touches no global hardware state.

## Known Divergences

None — all operations are architecturally defined for all generations.

## Pass/Fail Criteria

- **PASS:** all 6 cases return STATUS_PASS
- **FAIL:** any case returns STATUS_FAIL
- **SKIP:** test_cpu_detection returns STATUS_SKIP if `g_cpu_type` is invalid
