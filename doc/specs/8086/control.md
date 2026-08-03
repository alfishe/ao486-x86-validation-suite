# Spec: 8086 Control Flow

## Metadata
- **Source file:** `src/cpu/8086/control.asm`
- **TIER:** UNIVERSAL | VENUE: G+H | GEN: 8086+ | ORACLE: manual
- **Impl-plan:** Phase 2, area `8086-Ctrl`
- **Coverage:** [§3](../../coverage-matrix.md#3-cpu--80868088-pri-1-foundation)

## Purpose

Verify all 16 Jcc conditions, near/short displacements, JMP/CALL/RET
(near and far), and LOOP/LOOPZ/LOOPNZ/JCXZ.

## Test Cases

### All 16 Jcc conditions

| Condition | Flag test | Pass when | Fail when |
|-----------|-----------|-----------|-----------|
| JE/JZ | ZF=1 | ZF=1 → jump | ZF=0 → fall through |
| JNE/JNZ | ZF=0 | ZF=0 → jump | ZF=1 |
| JC/JNAE/JB | CF=1 | | |
| JNC/JAE/JNB | CF=0 | | |
| JBE/JNA | CF=1 OR ZF=1 | | |
| JA/JNBE | CF=0 AND ZF=0 | | |
| JL/JNGE | SF≠OF | | |
| JGE/JNL | SF=OF | | |
| JLE/JNG | ZF=1 OR SF≠OF | | |
| JG/JNLE | ZF=0 AND SF=OF | | |
| JS | SF=1 | | |
| JNS | SF=0 | | |
| JO | OF=1 | | |
| JNO | OF=0 | | |
| JP/JPE | PF=1 | | |
| JNP/JPO | PF=0 | | |

For each: pre-seed the relevant flags with `pushf`/`popf`, execute Jcc,
verify whether the jump was taken (IP changed) or not.

### Near/short displacement

- Test forward short jump (±127 bytes)
- Test backward short jump
- Test near jump (16-bit displacement)

### CALL/RET near

| # | Action | Expected | Notes |
|---|--------|----------|-------|
| 1 | CALL near | SP -= 2, [SP] = return addr | push IP |
| 2 | RET (near) | IP = [SP], SP += 2 | pop IP |
| 3 | RET imm16 (near) | IP = [SP], SP += 2 + imm16 | pop + adjust |

### CALL/RET far

| # | Action | Expected | Notes |
|---|--------|----------|-------|
| 1 | CALL far ptr | SP -= 4, push CS then IP | inter-segment |
| 2 | RETF | pop IP then CS | |

### LOOP/LOOPZ/LOOPNZ/JCXZ

| # | CX_before | ZF_before | Instruction | Action | CX_after | Jump? |
|---|:---------:|:---------:|-------------|--------|:--------:|:-----:|
| 1 | 0 | — | LOOP | CX=0, no loop | 0 | no |
| 2 | 1 | — | LOOP | CX→0, no loop (decremented to 0) | 0 | no |
| 3 | 2 | — | LOOP | CX→1, loop taken | 1 | yes |
| 4 | 2 | 0 | LOOPZ | CX→1, ZF=0 → loop stops | 1 | no |
| 5 | 2 | 1 | LOOPZ | CX→1, ZF=1 → loop continues | 1 | yes |
| 6 | 2 | 0 | LOOPNZ | CX→1, ZF=0 → continues | 1 | yes |
| 7 | 2 | 1 | LOOPNZ | CX→1, ZF=1 → stops | 1 | no |
| 8 | 0 | — | JCXZ | jump (CX=0) | 0 | yes |
| 9 | 1 | — | JCXZ | no jump (CX≠0) | 1 | no |

## Pre/Post State (representative cases)

### CALL near — stack layout

```
PRE:
  SP  = 0x0FFC
  IP  = 0x0100        (call instruction at 0x0100, 3 bytes: E8 ll hh)
  [0x0FFC] = ??       (arbitrary)

  OP:  CALL 0x0200    (near, direct)

POST:
  SP  = 0x0FFA                        ← SP -= 2
  [0x0FFA] = 0x0103                   ← pushed return address = IP after CALL
  IP  = 0x0200                        ← transferred to target
```

### RET near — stack unwinding

```
PRE:
  SP  = 0x0FFA
  [0x0FFA] = 0x0103                   ← return address on stack

  OP:  RET                            (near)

POST:
  SP  = 0x0FFC                        ← SP += 2
  IP  = 0x0103                        ← popped return address
```

### RET imm16 (near) — stack cleanup

```
PRE:
  SP  = 0x0FFA
  [0x0FFA] = 0x0103                   ← return address

  OP:  RET 8                          (near, pop 2 + discard 8)

POST:
  SP  = 0x0FFC + 8 = 0x1004           ← SP += 2 + imm16
  IP  = 0x0103
```

### CALL far — inter-segment stack layout

```
PRE:
  SP  = 0x0FFC
  CS  = 0x1000
  IP  = 0x0100
  [0x0FFC..0x0FFF] = ??

  OP:  CALL FAR 0x2000:0x0050

POST:
  SP  = 0x0FF8                        ← SP -= 4
  [0x0FF8] = 0x0103                   ← pushed IP (return offset)
  [0x0FFA] = 0x1000                   ← pushed CS (return segment)
  CS  = 0x2000                        ← loaded from far pointer
  IP  = 0x0050
```

### LOOP — CX=2, jump taken

```
PRE:
  CX = 0x0002
  IP = 0x0100

  OP:  LOOP 0x0100    (loop back to self)

POST:
  CX = 0x0001        ← decremented
  IP = 0x0100        ← jump taken (CX != 0)
```

### LOOP — CX=1, no jump

```
PRE:
  CX = 0x0001
  IP = 0x0100

  OP:  LOOP 0x0100

POST:
  CX = 0x0000        ← decremented to 0
  IP = 0x0102        ← fall through (CX reached 0)
```

## State Save/Restore

- **Save:** AX, BX, CX, SP, BP, FLAGS, CS (far CALL changes CS)
- Use a dedicated stack region to avoid corrupting the framework stack

## Pass/Fail Criteria

- **PASS:** jump taken/not-taken correctly; SP/IP/CS correct after CALL/RET
- **SKIP:** never
