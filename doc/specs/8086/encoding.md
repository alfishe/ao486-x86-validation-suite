# Spec: 8086 Encoding & Undocumented Opcodes

## Metadata
- **Source file:** `src/cpu/8086/encoding.asm`
- **TIER:** UNIVERSAL | VENUE: G | GEN: 8086+ | ORACLE: golden
- **Impl-plan:** Phase 2, area `8086-Enc`
- **Coverage:** [§3.3](../../coverage-matrix.md#33-hard-cases--encoding--decoding)
- **Divergences:** [prep-analysis §1.1](../../prep-analysis.md#11-instruction-availability-divergences)

## Purpose

Verify undocumented opcodes, aliases, redundant prefix behavior, and
encoding-dependent behavior that differs across generations.

## Test Cases

### SALC (D6)

Covered in [misc.md](misc.md).

### 0F opcode (POP CS on 8086)

| # | Gen | Opcode | Expected | Notes |
|---|-----|--------|----------|-------|
| 1 | 8086 | 0F | POP CS | 8086-only alias |
| 2 | 286+ | 0F | 2-byte opcode prefix | becomes first byte of 2-byte opcode |

> **Gen-gate:** test only on 8086/8088.  On 286+, 0F is a prefix, not POP CS.

### 60-6F opcodes (Jcc aliases on 8086)

| # | Gen | Opcode | 8086 meaning | 186+ meaning |
|---|-----|--------|-------------|-------------|
| 1 | 8086 | 60 | alias of 70 (JO) | PUSHA |
| 2 | 8086 | 61 | alias of 71 (JNO) | POPA |
| ... | | 62-6F | aliases of 72-7F | BOUND/ARPL/INS/OUTS/etc |

> **Gen-gate:** on 8086, bytes 60-6F behave as Jcc aliases of 70-7F.
> On 186+, they are defined instructions (PUSHA, POPA, etc.).

### 82 alias

| # | Opcode | Expected | Notes |
|---|--------|----------|-------|
| 1 | 82 (group1 r/m8, imm8) | same as 80 | redundant alias, valid on all gens |

### ICEBP / INT1 (F1)

| # | Opcode | Expected | Notes |
|---|--------|----------|-------|
| 1 | F1 | triggers INT1 (#DB-like) | undocumented single-byte INT1 |

> F1 is like INT1/ICEBP.  Install INT1 handler, execute F1, verify handler ran.

### Redundant prefix behavior

| # | Prefixes | Expected | Notes |
|---|----------|----------|-------|
| 1 | `CS: DS: MOV AL, [BX]` | DS wins (last segment override) | last-one-wins |
| 2 | `REP REP MOVSB` | single REP effect | redundant REP ignored |

### LOCK on invalid target

| # | Gen | Instruction | Expected | Notes |
|---|-----|-------------|----------|-------|
| 1 | 8086 | `LOCK MOV AL, [BX]` | ignored (no #UD) | 8086 doesn't check |
| 2 | 286+ | `LOCK MOV AL, [BX]` | **#UD** | 286+ validates LOCK target |

> **Gen-gate:** #UD on 286+, silently ignored on 8086.

### Long prefix chain (386+)

| # | Gen | Prefixes | Expected | Notes |
|---|-----|----------|----------|-------|
| 1 | 8086 | 15+ segment prefixes | ignored (no limit) | |
| 2 | 386+ | 15+ bytes of prefixes | **#GP** | instruction-length limit |

## Pre/Post State (representative cases)

### Opcode 0F — POP CS on 8086

```
8086 PRE:
  CS = 0x1000
  SP = 0x0FFA
  [SS:0x0FFA] = 0x2000   (pending far value on stack)

  OP:  DB 0x0F            (POP CS on 8086)

8086 POST:
  CS = 0x2000             ← popped from stack
  SP = 0x0FFC             ← SP += 2

286+ PRE:
  Same state

286+ POST:
  0F is a 2-byte opcode prefix — NOT POP CS
  Next byte determines the instruction (e.g., 0F 06 = CLTS)
```

### Opcode F1 — ICEBP / INT1

```
PRE:
  FLAGS = 0x0002
  INT1 handler installed at vector 1
  Handler sets a flag byte at [0x3000] = 0

  OP:  DB 0xF1             (ICEBP)

POST:
  [0x3000] = 0x01          ← handler executed
  CS:IP = handler return address
  (TF is cleared by interrupt entry)
```

### Redundant segment override — last-one-wins

```
PRE:
  CS base = 0x00000
  DS base = 0x10000
  BX = 0x0000
  [CS:0x0000] = 0xAA
  [DS:0x0000] = 0xBB

  OP:  CS: DS: MOV AL, [BX]   (CS overrides, then DS overrides)

POST:
  AL = 0xBB                 ← DS wins (last segment override prefix)
```

### LOCK on invalid target (8086 vs 286+)

```
8086 PRE:
  AL = 0x00, [DS:0x1000] = 0x42
  OP:  LOCK MOV AL, [0x1000]
8086 POST:
  AL = 0x42               ← LOCK silently ignored, MOV executes normally

286+ PRE:
  Same
286+ POST:
  #UD exception (INT 6)    ← LOCK not valid for MOV (non-xchg memory op)
  AL unchanged
```

## State Save/Restore

- **Save:** AX, CS, IP-relative state, FLAGS
- For INT1: install/restore INT1 vector

## Known Divergences

| Behavior | 8086 | 286+ | Action |
|----------|------|------|--------|
| 0F = POP CS | yes | no (prefix) | gen-gate |
| 60-6F = Jcc alias | yes | no (defined insns) | gen-gate |
| LOCK invalid | ignored | #UD | gen-gate |
| Long prefix | no limit | #GP (386+) | gen-gate |

## Pass/Fail Criteria

- **PASS:** opcode behavior matches gen-specific expected
- **FAIL:** wrong interpretation of undocumented/aliased opcode
- **SKIP:** gen-gated tests on unsupported CPU
