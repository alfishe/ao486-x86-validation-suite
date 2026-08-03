# Spec: 286 System Instructions

## Metadata
- **Source file:** `src/cpu/80286/system.asm`
- **TIER:** RING0 | VENUE: G | GEN: 80286+ | ORACLE: manual
- **Impl-plan:** Phase 4, area `286-Sys`
- **Coverage:** [§6.3](../../coverage-matrix.md#63-hard-cases--system-instructions), [§6.4](../../coverage-matrix.md#64-hard-cases--arpl-and-lsl-lar)
- **Prerequisite:** [286-pm-infra.md](286-pm-infra.md)

## Purpose

Verify SGDT/SIDT/SLDT/SMSW, LGDT/LIDT/LLDT/LMSW, LAR/LSL/ARPL/VERW/VERR,
CLTS, and the privilege enforcement around these.

## Test Cases

### Store system tables (SGDT/SIDT/SLDT/SMSW)

| # | Instruction | CPL | Result | Notes |
|---|-------------|:---:|--------|-------|
| 1 | SGDT [mem] | 0 | 6-byte limit+base | |
| 2 | SGDT [mem] | 3 | OK on 286; **#GP on 386+** | 386+ restricts SGDT at CPL>0 |

> **Divergence:** 286 allows SGDT/SIDT at any CPL.  386+ requires CPL=0.
> See [prep-analysis §1.2a](../../prep-analysis.md#12a-generation-specific-divergences-286-vs-386-vs-486).

### Load system tables (LGDT/LIDT/LLDT/LMSW)

| # | Instruction | CPL | Expected | Notes |
|---|-------------|:---:|----------|-------|
| 1 | LGDT [mem] | 0 | OK | privileged |
| 2 | LGDT [mem] | 3 | **#GP** | ring 3 cannot load GDT |
| 3 | LLDT ax | 0 | OK | privileged |
| 4 | LMSW ax | 0 | OK | privileged |

### SGDT high byte divergence

| # | Gen | SGDT byte 6 (high byte of base) | Notes |
|---|-----|:-------------------------------:|-------|
| 1 | 286 | **garbage** (undefined) | must mask |
| 2 | 386+ | 0x00 (zero-extended) | clean |

> When reading SGDT on a 286, the high byte of the base address is undefined.
> Test must mask it.  On 386+, it reads as 0.

### LAR (Load Access Rights)

| # | Selector | CPL | DPL | Expected ZF | Notes |
|---|----------|:---:|:---:|:-----------:|-------|
| 1 | valid code, DPL=0 | 0 | 0 | ZF=1 (success) | CPL ≥ DPL |
| 2 | valid code, DPL=3 | 0 | 3 | ZF=1 | CPL ≤ DPL for code? No — LAR: CPL ≤ DPL required |
| 3 | valid code, DPL=0 | 3 | 0 | ZF=0 (fail) | CPL > DPL |
| 4 | null selector | — | — | ZF=0 | always fails |
| 5 | system descriptor | — | — | ZF=0 (286); ZF=1 (386+ for some types) | gen diverge |

> LAR loads the access rights byte into the destination register if the
> selector is valid and CPL/DPL checks pass.  ZF indicates success.

### LSL (Load Segment Limit)

| # | Selector | Expected ZF | Notes |
|---|----------|:-----------:|-------|
| 1 | valid data, DPL≥CPL | ZF=1 | loads byte-granular limit |
| 2 | valid data, G=1 | ZF=1 | loads page-granular limit (386+) |
| 3 | null | ZF=0 | |
| 4 | system descriptor | ZF=0 | LSL only works on data/code segments |

### ARPL (Adjust RPL)

| # | Selector RPL | CPL (source) | Expected RPL | ZF | Notes |
|---|:------------:|:------------:|:------------:|:--:|-------|
| 1 | 3 | 0 | 0 | set | RPL adjusted to min(RPL, CPL) |
| 2 | 1 | 3 | 1 | clear | no change needed |

> ARPL sets ZF if RPL was changed. Used to enforce minimum privilege.

### VERR / VERW

| # | Selector | DPL | Type | VERR ZF | VERW ZF | Notes |
|---|----------|:---:|------|:-------:|:-------:|-------|
| 1 | readable data | 0 | data | 1 | 1 | readable+writable |
| 2 | execute-only code | 0 | code | 0 | 0 | not readable |
| 3 | read-only data | 0 | data | 1 | 0 | readable but not writable |

### CLTS (Clear Task Switched)

| # | Action | Expected | Notes |
|---|--------|----------|-------|
| 1 | CLTS at CPL=0 | CR0.TS cleared | privileged |
| 2 | CLTS at CPL=3 | **#GP** | ring 3 can't execute |

## Pre/Post State (representative cases)

### SGDT — store GDT register

```
PRE:
  GDT base = 0x00010000
  GDT limit = 0x00FF
  Buffer at DS:0x2000 = uninitialized

  OP:  SGDT [0x2000]

POST:
  [DS:0x2000] = 0xFF        ← limit low byte
  [DS:0x2001] = 0x00        ← limit high byte
  [DS:0x2002] = 0x00        ← base byte 0 (low)
  [DS:0x2003] = 0x00        ← base byte 1
  [DS:0x2004] = 0x01        ← base byte 2
  [DS:0x2005] = 0x00        ← base byte 3 (high)
  286: byte 5 = garbage (undefined)
  386+: byte 5 = 0x00 (zero-extended)
```

### LAR — load access rights

```
PRE (CPL=0):
  GDT entry at selector 0x08:
    access byte = 0x9A (code, P=1, DPL=0, readable)
  AX = 0x0008  (selector)

  OP:  LAR AX, [selector]

POST:
  AX = 0x9A  (access rights loaded, with high bits from gran byte on 386+)
  ZF = 1  (success — CPL ≥ DPL check passed)
```

```
PRE (CPL=3):
  Same selector 0x08, DPL=0
  AX = 0x0008

  OP:  LAR AX, [selector]

POST:
  AX unchanged  (load failed)
  ZF = 0  (CPL > DPL → access denied)
```

### LSL — load segment limit

```
PRE (CPL=0):
  GDT entry 0x10 (data segment):
    limit = 0xFFFF, G=0
  AX = 0x0010

  OP:  LSL AX, [selector]

POST:
  AX = 0xFFFF  (byte-granular limit loaded)
  ZF = 1

386+ with G=1:
  limit field = 0xFFFFF, G=1
  OP:  LSL EAX, [selector]
POST:
  EAX = 0xFFFFFFFF  (page-granular: 0xFFFFF << 12 | 0xFFF)
```

### ARPL — adjust RPL

```
PRE:
  AX = 0x0003  (selector with RPL=3)
  CX = 0x0000  (CPL=0, the reference)

  OP:  ARPL AX, CX

POST:
  AX = 0x0000  (RPL adjusted down to 0 = min(3, 0))
  ZF = 1  (RPL was changed)
```

### VERR / VERW

```
PRE:
  GDT entry 0x10: data segment, DPL=0, readable+writable
  AX = 0x0010

  OP:  VERR AX
POST:
  ZF = 1  (readable at current CPL)

  OP:  VERW AX
POST:
  ZF = 1  (writable at current CPL)
```

### CLTS — clear task-switched flag

```
PRE:
  CR0 = 0x----0010  (TS bit set = 0x0008, PE=1)

  OP:  CLTS  (at CPL=0)

POST:
  CR0 = 0x----0008  (TS cleared)
  No exception

  OP:  CLTS  (at CPL=3)
POST:
  #GP (0)  — privileged instruction at ring 3
```

## State Save/Restore

- **Save:** GDT/IDT registers, LDTR, CR0
- **Restore:** restore all

## Pass/Fail Criteria

- **PASS:** system instructions respect CPL; LAR/LSL/ARPL/VERR/VERW correct
- **FAIL:** wrong privilege check or ZF value
- **SKIP:** GEN < 80286
