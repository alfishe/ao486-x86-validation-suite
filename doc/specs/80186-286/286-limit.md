# Spec: 286 Limit Enforcement

## Metadata
- **Source file:** `src/cpu/80286/limit.asm`
- **TIER:** RING0 | VENUE: G | GEN: 80286+ | ORACLE: manual
- **Impl-plan:** Phase 4, area `286-Limit`
- **Coverage:** [§6.2](../../coverage-matrix.md#62-hard-cases--limit-enforcement)
- **Prerequisite:** [286-pm-infra.md](286-pm-infra.md)

## Purpose

Verify segment limit checks: byte-granular and page-granular limits,
expand-down stacks, and limit violations generating #GP/#SS.

## Test Cases

### Byte-granular (G=0) limit

| # | Limit | Offset accessed | Expected | Notes |
|---|-------|----------------|----------|-------|
| 1 | 0x00FF | 0x00FE (word) | OK | last valid word |
| 2 | 0x00FF | 0x0100 | **#GP** | one past limit |
| 3 | 0x00FF | 0x00FF (byte) | OK | last valid byte |
| 4 | 0x00FF | 0x0100 (word) | **#GP** | word crosses limit |

### Page-granular (G=1) — 386+ only

| # | Limit field | G | Effective limit | Notes |
|---|------------|:--:|----------------|-------|
| 1 | 0x00000 | 1 | 0x00000FFF | one page (4KB) |
| 2 | 0xFFFFF | 1 | 0xFFFFFFFF | full 4GB |
| 3 | 0x00001 | 1 | 0x00001FFF | two pages |

> With G=1: effective_limit = (limit_field << 12) | 0xFFF

### Expand-down data segment (E=1)

| # | Type | Limit | Offset | Expected | Notes |
|---|------|-------|--------|----------|-------|
| 1 | expand-up (E=0) | 0xFF | 0x100 | **#GP** | above limit |
| 2 | expand-down (E=1) | 0xFF | 0x100 | OK | above limit is VALID |
| 3 | expand-down (E=1) | 0xFF | 0x50 | **#GP** | below limit+1 is INVALID |

> Expand-down segments: valid offsets are limit+1 through FFFFFFFFh.
> Used for stacks that grow downward.

### Stack segment (#SS vs #GP)

| # | Segment | Violation | Exception | Notes |
|---|---------|-----------|-----------|-------|
| 1 | SS | limit exceeded | **#SS** (not #GP) | stack fault |
| 2 | DS | limit exceeded | **#GP** | general protection |

### Code segment limit (fetch)

| # | CS limit | Instruction fetch at | Expected | Notes |
|---|----------|---------------------|----------|-------|
| 1 | 0x1000 | 0x0FFE | OK | 2-byte fetch within limit |
| 2 | 0x1000 | 0x1000 | **#GP** | fetch at limit |

## Pre/Post State (representative cases)

### Byte-granular limit — valid access

```
PRE (PM, CPL=0):
  DS descriptor: base=0x00000000, limit=0x00FF, G=0
  DS hidden cache: base=0, limit=0xFF
  ESI = 0x00FE

  OP:  MOV AX, [DS:ESI]    (word access at offset 0xFE)

POST:
  AX = [0x00FE..0x00FF]    (within limit: 0xFE + 2 - 1 = 0xFF ≤ 0xFF)
  No exception
```

### Byte-granular limit — violation (#GP)

```
PRE:
  DS descriptor: limit=0x00FF, G=0
  ESI = 0x0100

  OP:  MOV AX, [DS:ESI]    (word access at offset 0x100)

POST:
  #GP(0) exception
  (0x100 + 2 - 1 = 0x101 > limit 0xFF)
```

### Expand-down segment — inverted valid range

```
PRE:
  SS descriptor: limit=0x00FF, E=1 (expand-down), G=0
  Valid offsets for expand-down: 0x0100..0xFFFF
  ESP = 0x0100

  OP:  PUSH AX    (writes at ESP-2 = 0x00FE)

POST:
  SP = 0x00FE    (0x00FE ≥ limit+1=0x0100? No → 0x00FE < 0x0100)
  #SS(0) exception!  (0x00FE is below the valid range for expand-down)

  Correct usage: ESP must start high (e.g., 0xFFFF) and decrement
  Valid range: 0x0100 through 0xFFFF
```

### Page-granular limit (386+ only)

```
386+ PRE:
  DS descriptor: limit_field=0x00000, G=1
  Effective limit = (0x00000 << 12) | 0xFFF = 0x00000FFF
  ESI = 0x0FFC

  OP:  MOV EAX, [DS:ESI]    (dword access at 0xFFC)

POST:
  EAX = [0xFFC..0xFFF]    (0xFFC + 4 - 1 = 0xFFF ≤ 0xFFF)
  No exception

  ESI = 0x1000
  OP:  MOV EAX, [DS:ESI]
POST:
  #GP(0)  (0x1000 > effective limit 0xFFF)
```

## State Save/Restore

- **Save:** DS, ES, SS; GDT descriptors for test segments
- **Restore:** restore segment regs; restore GDT descriptors

## Known Divergences

| Behavior | 286 | 386+ | Action |
|----------|------|------|--------|
| G bit | absent | present | 286 always G=0 |
| Max limit | 0xFFFF (64KB) | 0xFFFFFFFF (4GB) | |

## Pass/Fail Criteria

- **PASS:** correct exception type (#GP for DS, #SS for SS); correct boundary
- **FAIL:** no exception or wrong exception vector
- **SKIP:** G=1 tests on 286
