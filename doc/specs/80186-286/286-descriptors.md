# Spec: 286 Descriptor Checks

## Metadata
- **Source file:** `src/cpu/80286/descriptors.asm`
- **TIER:** RING0 | VENUE: G | GEN: 80286+ | ORACLE: manual
- **Impl-plan:** Phase 4, area `286-Desc`
- **Coverage:** [§6.1](../../coverage-matrix.md#61-hard-cases--descriptor-loading-checks)
- **Detail:** [prep-analysis §2](../../prep-analysis.md#2-protected-mode--paging--full-check-matrix)
- **Prerequisite:** [286-pm-infra.md](286-pm-infra.md) (PM infrastructure)

## Purpose

Verify all descriptor load checks: type, DPL, Present, limit, and the
Accessed bit writeback.  These checks are the core of PM protection.

## Test Cases

### Segment load: type checks

| # | Descriptor type | Load into CS | Load into DS | Load into SS | Expected |
|---|----------------|:------------:|:------------:|:------------:|----------|
| 1 | Code (0x9A) | OK | **#GP** | **#GP** | code can't go in DS/SS |
| 2 | Data (0x92) | **#GP** | OK | OK | data can't go in CS |
| 3 | Read-only data (0x90) | **#GP** | OK | **#GP** | can't use as SS |
| 4 | Execute-only code (0x98) | OK | **#GP** | **#GP** | can't read from it |

### DPL privilege checks (CPL=0)

| # | Descriptor DPL | Load DS/ES | Load SS | Notes |
|---|:--------------:|:---------:|:-------:|-------|
| 1 | DPL=0 | OK | OK | same privilege |
| 2 | DPL=3 | OK | **#GP** | can read DPL=3 data at CPL=0 |
| 3 | DPL=0 from CPL=3 | **#GP** | **#GP** | ring 3 can't access ring 0 data |

> For data segments: load succeeds if DPL >= CPL OR DPL >= RPL.
> For SS: DPL must equal CPL.

### Present bit

| # | P bit | Load | Expected | Notes |
|---|:-----:|------|----------|-------|
| 1 | P=1 | MOV DS, sel | OK | normal |
| 2 | P=0 | MOV DS, sel | **#NP** (not present) | vector 11 |

> #NP delivers error code = selector with the TI bit and index.

### Accessed bit writeback

| # | Descriptor state | Action | Expected | Notes |
|---|-----------------|--------|----------|-------|
| 1 | Accessed=0 | MOV DS, sel | Accessed becomes 1 | hardware sets A bit |
| 2 | Accessed=0 | JMP far to code sel | Accessed becomes 1 | code segment too |

> **Verify:** after loading any segment descriptor, bit 8 of the access byte
> in the GDT must be set.  This proves the CPU wrote back to the GDT.

### Null selector

| # | Selector | Load | Expected | Notes |
|---|----------|------|----------|-------|
| 1 | 0x0000 | MOV DS, ax | **#GP** | null selector check |
| 2 | 0x0003 | MOV DS, ax | **#GP** | null + RPL=3 |

### LDT selector

| # | Selector | Action | Expected | Notes |
|---|----------|--------|----------|-------|
| 1 | LDT sel (type=0x02) | LLDT | loads LDTR | system descriptor |
| 2 | LDT sel | MOV DS, sel | **#GP** | can't use system desc as data |

### TI bit (LDT vs GDT)

| # | TI | Selector | Source | Notes |
|---|:--:|----------|--------|-------|
| 1 | 0 | 0x08 | GDT | normal |
| 2 | 1 | 0x08 | LDT | select from LDT instead |

> Create a small LDT with a valid data descriptor, then load via TI=1 selector.

### Descriptor limit check (GDT bounds)

| # | Selector index | GDT limit | Expected | Notes |
|---|:--------------:|:---------:|----------|-------|
| 1 | within limit | 0xFF | OK | |
| 2 | beyond limit | 0xFF | **#GP** | selector × 8 + 7 > limit |

## Pre/Post State (representative cases)

### Valid DS load — descriptor cached + Accessed bit set

```
PRE (PM, CPL=0):
  GDT entry at selector 0x10:
    Bytes: [FF FF 00 00 00 92 0F 00]
    limit=0xFFFF, base=0x00000000, access=0x92 (data, P=1, DPL=0, writable)
    Accessed bit (bit 8 of access byte) = 0
  AX = 0x0010
  DS hidden cache: undefined

  OP:  MOV DS, AX

POST:
  DS = 0x0010  (selector loaded)
  DS hidden cache:
    base = 0x00000000, limit = 0xFFFF, access = 0x92
  GDT entry at 0x10:
    Access byte changed: 0x92 → 0x9A  (Accessed bit set: bit 8)
  No exception
```

### Type violation — code selector into DS

```
PRE:
  GDT entry 0x08: code segment (access=0x9A, exec/read)
  AX = 0x0008

  OP:  MOV DS, AX

POST:
  #GP(0x0008) exception
  Error code = selector (0x0008) + Ext bit
  DS unchanged
```

### Not-present segment

```
PRE:
  GDT entry 0x18: P=0 (not present)
    access byte = 0x12 (P=0, DPL=0, data)
  AX = 0x0018

  OP:  MOV DS, AX

POST:
  #NP(0x0018) exception (vector 11)
  Error code = selector 0x0018
```

### Null selector

```
PRE:
  AX = 0x0000  (null selector)

  OP:  MOV DS, AX

POST:
  #GP(0x0000) exception
  (Null selector is always rejected for DS/ES/FS/GS/SS loads)
```

## State Save/Restore

- **Save:** all segment regs; GDT memory (A bit writes modify it)
- **Restore:** restore segment regs; clear A bits in GDT to test again

## Known Divergences

| Behavior | 286 | 386+ | Action |
|----------|------|------|--------|
| Descriptor size | 6 bytes | 8 bytes | 286 lacks G bit and high base byte |
| Limit | 16-bit | 20-bit + G | 286 max 64KB segments |

## Pass/Fail Criteria

- **PASS:** correct exception for each violation; A bit set on valid load
- **FAIL:** no exception or wrong exception
- **SKIP:** GEN < 80286
