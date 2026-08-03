# Spec: 286 Real-Mode Extensions

## Metadata
- **Source file:** `src/cpu/80286/real.asm`
- **TIER:** REALMODE | VENUE: G | GEN: 80286+ | ORACLE: manual + golden
- **Impl-plan:** Phase 4, area `286-Real`
- **Coverage:** [§6](../../coverage-matrix.md#6-cpu--80286-pri-1-for-pm-the-first-big-divergence-surface)
- **Divergences:** [prep-analysis §1.2](../../prep-analysis.md#12-behavioral-divergences-same-instruction-different-result), [§1.2a](../../prep-analysis.md#12a-generation-specific-divergences-286-vs-386-vs-486)

## Purpose

Verify 286-specific real-mode behavior: PUSHF reserved bits, SMSW/LMSW,
and the different behavior of some instructions vs 8086.

## Test Cases

### PUSHF reserved bits (12-15)

| # | Gen | Bits 12-15 after PUSHF | Notes |
|---|-----|:----------------------:|-------|
| 1 | 8086 | 0xF (always 1) | |
| 2 | 286+ (real mode) | 0x0 (cleared) | used for CPU detection |

### SMSW (Store Machine Status Word)

| # | Gen | CR0 bits readable | Notes |
|---|-----|-------------------|-------|
| 1 | 286 | PE, MP, EM, TS | 16-bit read |
| 2 | 386+ | PE, MP, EM, TS, ET, NE, PG | 32-bit CR0 available |
| 3 | 486+ | + WP, AM, NW, CD, CE | |

> In real mode, PE=0. SMSW reads CR0 low 16 bits.

### LMSW (Load Machine Status Word)

| # | Action | Expected | Notes |
|---|--------|----------|-------|
| 1 | LMSW with PE bit set | enters PM | **286 can set PE but cannot clear it** |
| 2 | LMSW without PE | stays in RM | |

> **286 limitation:** Once PE is set, it cannot be cleared via LMSW.
> The only way back to real mode on a 286 is a hardware reset.
> 386+ can clear PE via `MOV CR0`.

### Shift count masking (286+)

Already tested in [shift.md](../8086/shift.md) — 286+ masks CL to 5 bits.
This module confirms the masking occurs at GEN 28286+.

### Instruction timing differences

| # | Instruction | 8086 behavior | 286+ behavior | Notes |
|---|-------------|---------------|---------------|-------|
| 1 | MUL/IMUL undefined flags | specific | different | golden per-gen |

## Pre/Post State (representative cases)

### PUSHF — reserved bits divergence

```
8086:
PRE:
  FLAGS = 0x0002  (bit1=1, all others clear)
  SP = 0x0FFC
  OP:  PUSHF
POST:
  SP = 0x0FFA
  [SS:0x0FFA] = 0xF002   ← bits 12-15 read as 1s (0xF)

286+ (real mode):
PRE:
  FLAGS = 0x0002
  SP = 0x0FFC
  OP:  PUSHF
POST:
  SP = 0x0FFA
  [SS:0x0FFA] = 0x0002   ← bits 12-15 read as 0s
  (This is the classic CPU detection method)
```

### SMSW — read CR0 low 16 bits

```
286 PRE:
  CR0 = 0x----0010  (PE=0, MP=1, EM=0, TS=0 in real mode)
  AX = 0x????
  OP:  SMSW AX
POST:
  AX = 0x0010   (low 16 bits of CR0)

386+ PRE:
  CR0 = 0x00000010  (PE=0, MP=1 in RM)
  OP:  SMSW AX
POST:
  AX = 0x0010   (same low 16 bits; use MOV EAX,CR0 for full 32-bit)
```

### LMSW — set PE (enter PM)

```
PRE:
  CR0 = 0x0010  (real mode: PE=0, MP=1)
  AX = 0x0001   (PE bit set)

  OP:  LMSW AX

POST:
  CR0 = 0x0011  (PE=1, now in protected mode)
  Must immediately far-jump to load CS from GDT

  Note: On 286, PE cannot be cleared after this — only reset exits PM.
  On 386+, MOV CR0 can clear PE to return to real mode.
```

### Shift count masking — 286+

```
286+ PRE:
  AL = 0x01
  CL = 0x20  (32)
  OP:  SHL AL, CL
286+ POST:
  AL = 0x01   (CL & 0x1F = 0 → effective count = 0 → no-op)

8086 PRE:
  AL = 0x01
  CL = 0x20  (32)
  OP:  SHL AL, CL
8086 POST:
  AL = 0x00   (32 raw shifts → all bits shifted out)
```

## State Save/Restore

- **Save:** AX, FLAGS, machine status word (SMSW)
- **Restore:** restore AX, FLAGS.  **Do NOT attempt to restore CR0 — PE set is irreversible on 286.**

## Known Divergences

| Behavior | 8086 | 286+ | Action |
|----------|------|------|--------|
| PUSHF bits 12-15 | 1 | 0 | gen-gate |
| Shift count | raw CL | CL & 0x1F | gen-gate |
| LMSW PE clear | n/a | impossible on 286 | documented |

## Pass/Fail Criteria

- **PASS:** reserved bits match gen; SMSW reads correct CR0 bits; LMSW enters PM
- **SKIP:** GEN < 80286
