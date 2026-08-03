# Spec: 8086 Stack Operations

## Metadata
- **Source file:** `src/cpu/8086/stack.asm`
- **TIER:** UNIVERSAL | VENUE: G+H | GEN: 8086+ | ORACLE: manual + golden
- **Impl-plan:** Phase 2, area `8086-Stack`
- **Coverage:** [§3](../../coverage-matrix.md#3-cpu--80868088-pri-1-foundation), [§3.1 reserved bits](../../coverage-matrix.md#31-hard-cases--flag-semantics)
- **Divergences:** [prep-analysis §1.2](../../prep-analysis.md#12-behavioral-divergences-same-instruction-different-result) — PUSH SP quirk

## Purpose

Verify PUSH/POP all register forms, PUSHF/POPF, and the critical
**PUSH SP** 8086-vs-286 divergence and **reserved FLAGS bits**.

## Test Cases

### PUSH/POP register round-trip

| # | Instruction | Expected | Notes |
|---|-------------|----------|-------|
| 1 | `PUSH AX; POP BX` | BX == original AX | round-trip |
| 2 | `PUSH CX; POP DX` | DX == original CX | |
| 3 | `PUSH 0x1234; POP AX` | AX == 0x1234 | immediate push (186+; 8086 SKIPs) |

### PUSH SP — KEY DIVERGENCE

| # | SP_before | Instruction | 8086 pushed | 286+ pushed | Notes |
|---|-----------|-------------|-------------|-------------|-------|
| 1 | 0xFFFE | PUSH SP | 0xFFFC (= SP-2) | 0xFFFE (= original SP) | 8086 pushes decremented; 286+ pushes original |
| 2 | 0x0100 | PUSH SP | 0x00FE | 0x0100 | same divergence |

> Verify by: set SP to known value, `PUSH SP`, then `POP AX`, compare AX
> to the expected value for the detected generation.

### PUSHF/POPF reserved bits

| # | Gen | PUSHF bits 12-15 | Notes |
|---|-----|:----------------:|-------|
| 1 | 8086 | always set (0xF) | used for CPU detection |
| 2 | 286+ | cleared (0x0 in real mode) | detection algorithm relies on this |

> Test: `PUSHF; POP AX; AND AX, 0xF000`. 8086 → 0xF000, 286+ → 0x0000.

### PUSHF/POPF round-trip

- `PUSHF; POP AX; PUSH AX; POPF; PUSHF; POP AX` — second AX must equal first
- Verify bit 1 is always 1 (reserved, always set)
- Verify bits 3, 5 are always 0 (reserved)

## Pre/Post State (representative cases)

### PUSH AX / POP BX — round-trip

```
PRE:
  AX = 0x1234
  SP = 0x0FFC
  SS:SP memory:
  [0x0FFC] = ??

  OP:  PUSH AX

POST (after PUSH):
  SP = 0x0FFA          ← SP -= 2
  [SS:0x0FFA] = 0x1234  ← value stored (little-endian: 34 12)
  AX = 0x1234          (unchanged)

  OP:  POP BX

POST (after POP):
  SP = 0x0FFC          ← SP += 2
  BX = 0x1234          ← value loaded from stack
  [SS:0x0FFA] = 0x1234 (memory unchanged, just read)
```

### PUSH SP — 8086 divergence

```
8086 PRE:
  SP = 0xFFFE

  OP:  PUSH SP

8086 POST:
  SP = 0xFFFC          ← SP decremented first (0xFFFE → 0xFFFC)
  [SS:0xFFFC] = 0xFFFC ← pushed value = decremented SP (SP-2)

286+ PRE:
  SP = 0xFFFE

  OP:  PUSH SP

286+ POST:
  SP = 0xFFFC          ← SP decremented
  [SS:0xFFFC] = 0xFFFE ← pushed value = ORIGINAL SP (before decrement)
```

### PUSHF — reserved bits on 8086

```
8086 PRE:
  FLAGS = 0x0002      (bit1 always set, all arithmetic flags clear)
  SP = 0x0FFC

  OP:  PUSHF

8086 POST:
  SP = 0x0FFA
  [SS:0x0FFA] = 0xF002  ← bits 12-15 read as 1s on 8086
  (bit1=1 preserved, bits12-15=0xF forced)

286+ POST:
  [SS:0x0FFA] = 0x0002  ← bits 12-15 read as 0s in real mode
```

### POPF — full FLAGS write

```
PRE:
  AX = 0x0202      (CF=1, bit1=1)
  [SS:SP] = 0x0202

  OP:  POPF

POST:
  FLAGS = 0x0202   (CF set, bit1 always 1)
  SP += 2
```

## State Save/Restore

- **Save:** SP, SS (use a dedicated scratch stack)
- **Critical:** restore SP exactly — stack corruption is fatal

## Known Divergences

| Behavior | 8086 | 286+ | Action |
|----------|------|------|--------|
| PUSH SP | pushes SP-2 | pushes original SP | golden per-gen |
| Reserved bits 12-15 | always 1 | cleared | manual |

## Pass/Fail Criteria

- **PASS:** round-trip preserves values; PUSH SP matches gen-specific expected
- **SKIP:** immediate PUSH if GEN < 80186
