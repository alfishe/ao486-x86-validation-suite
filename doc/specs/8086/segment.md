# Spec: 8086 Segment Operations

## Metadata
- **Source file:** `src/cpu/8086/segment.asm`
- **TIER:** REALMODE | VENUE: G | GEN: 8086+ | ORACLE: manual
- **Impl-plan:** Phase 2, area `8086-Seg`
- **Coverage:** [§3](../../coverage-matrix.md#3-cpu--80868088-pri-1-foundation)

## Purpose

Verify MOV to/from segment registers and LES/LDS pointer loads in real mode.

## Test Cases

### MOV to/from segment registers

| # | Instruction | Expected | Notes |
|---|-------------|----------|-------|
| 1 | `MOV AX, CS; MOV DS, AX` | DS base = CS base | |
| 2 | `MOV AX, 0x1000; MOV ES, AX` | ES base = 0x10000 | real-mode: base = sel × 16 |
| 3 | `MOV AX, ES; MOV DS, AX` | DS = ES | |

### Segment base recomputation

| # | Selector loaded | Expected base | Notes |
|---|----------------|---------------|-------|
| 1 | 0x0000 | 0x00000 | |
| 2 | 0x1000 | 0x10000 | |
| 3 | 0xFFFF | 0xFFFF0 | highest base, +0xFFF0 = HMA |
| 4 | 0xF000 | 0xF0000 | BIOS area |

### LES/LDS

| # | mem layout | Instruction | Expected | Notes |
|---|-----------|-------------|----------|-------|
| 1 | off=0x1234, seg=0x5678 | `LDS SI, [mem]` | SI=0x1234, DS=0x5678 | |
| 2 | off=0xABCD, seg=0x0000 | `LES DI, [mem]` | DI=0xABCD, ES=0x0000 | |

### Segment/offset wrap (0xFFFF word access)

| # | Gen | Segment | Offset | Expected | Notes |
|---|-----|---------|--------|----------|-------|
| 1 | 8086 | 0xFFFF | 0x0010 | wraps to 0x00000 | real-mode wrap on 8086 |
| 2 | 286+ PM | 0xFFFF | 0x0010 | #GP | 286+ in PM faults |

## Pre/Post State (representative cases)

### MOV to segment register — base recomputation

```
PRE:
  AX  = 0x1000
  ES  = 0x0000  (base = 0x00000)

  OP:  MOV ES, AX

POST:
  ES  = 0x1000  (internal base = 0x1000 << 4 = 0x10000)
  AX  = 0x1000  (unchanged)
```

### Segment base — selector 0xFFFF

```
PRE:
  ES = 0x0000

  OP:  MOV ES, 0xFFFF ; then access [ES:0x0010]

POST:
  ES base = 0xFFFF0
  Effective linear address = 0xFFFF0 + 0x0010 = 0x100000
  On 8086: wraps to 0x00000 (20-bit address bus, no A20 gate)
  On 286+ RM: wraps if A20 disabled; non-wraps if A20 enabled
  On 286+ PM: #GP (limit exceeded)
```

### LDS — load full pointer

```
PRE:
  SI = 0x0000
  DS = 0x0000
  Memory at DS:0x1000 = [34 12 78 56]
                    (offset=0x1234, segment=0x5678)

  OP:  LDS SI, [0x1000]

POST:
  SI = 0x1234    ← loaded from [mem+0]
  DS = 0x5678    ← loaded from [mem+2]
  DS internal base = 0x56780
```

### LES — load full pointer

```
PRE:
  DI = 0x0000
  ES = 0x0000
  Memory at DS:0x2000 = [CD AB 00 00]
                    (offset=0xABCD, segment=0x0000)

  OP:  LES DI, [0x2000]

POST:
  DI = 0xABCD    ← loaded from [mem+0]
  ES = 0x0000    ← loaded from [mem+2]
```

## State Save/Restore

- **Save:** DS, ES, SS (segment regs are modified)
- **Restore:** restore original values

## Pass/Fail Criteria

- **PASS:** segment base correct; pointer load correct
- **SKIP:** segment wrap test on 286+ (gen-gated)
