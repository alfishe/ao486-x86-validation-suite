# Spec: 386 Debug Registers

## Metadata
- **Source file:** `src/cpu/80386/debug.asm`
- **TIER:** RING0 | VENUE: G | GEN: 80386+ | ORACLE: manual
- **Impl-plan:** Phase 5, areas `386-Debug`, `386-CR`
- **Coverage:** [§7](../../coverage-matrix.md#7-cpu--80386-pri-1-32-bit--paging--v86)

## Purpose

Verify DR0-DR3 (breakpoint addresses), DR6 (debug status), DR7 (debug control),
code/data breakpoints, single-step (#DB via TF), and CR0/CR2/CR3 read/write.

## Test Cases

### Code execution breakpoint (DR0)

| # | DR0 | DR7 | Action | Expected | Notes |
|---|-----|-----|--------|----------|-------|
| 1 | addr of target | L0=1, R/W0=00 (exec), LEN0=00 | execute at addr | **#DB** | breakpoint hit |

### Data access breakpoint (DR1)

| # | DR1 | DR7 settings | Action | Expected | Notes |
|---|-----|-------------|--------|----------|-------|
| 1 | addr of variable | L1=1, R/W1=01 (write), LEN1=11 (4 bytes) | write to addr | **#DB** | write breakpoint |
| 2 | addr of variable | R/W1=11 (read/write) | read from addr | **#DB** | access breakpoint |

### DR7 control register

```
DR7 bits:
  0     L0  (local enable breakpoint 0)
  1     G0  (global enable breakpoint 0)
  2     L1
  3     G1
  4     L2
  5     G2
  6     L3
  7     G3
  8     LE  (local exact)
  9     GE  (global exact)
  10-12 (reserved)
  13    GD  (general detect — protects DRs from ring 3)
  14-15 (reserved)
  16-19 R/W0..3 (00=exec, 01=write, 11=r/w, 10=unused/I/O for 486+)
  20-23 (reserved)
  24-31 LEN0..3 (00=1 byte, 01=2 bytes, 11=4 bytes)
```

### DR6 status register

```
DR6 bits:
  0     B0  (breakpoint 0 triggered)
  1     B1
  2     B2
  3     B3
  4     BD  (debug register access — GD set in DR7)
  5     BS  (single step — TF was set)
  6     BT  (task switch — TSS T bit set)
  7-31 (reserved, read as 1 on 386/486)
```

### Single-step (TF in EFLAGS)

| # | TF | Action | Expected | Notes |
|---|:--:|--------|----------|-------|
| 1 | 1 | execute one instruction | **#DB** after each instruction | BS bit set in DR6 |
| 2 | 0 | execute normally | no #DB | |

> Set TF via PUSHFD/OR/POPFD or INT1/ICEBP.

### Breakpoint length encoding

| LEN value | Bytes watched | Notes |
|-----------|:------------:|-------|
| 00 | 1 | single byte |
| 01 | 2 | word (2 bytes) |
| 11 | 4 | dword (4 bytes) |
| 10 | undefined (I/O for 486+) | — |

### General detect (GD)

| # | GD bit in DR7 | Action | Expected | Notes |
|---|:-------------:|--------|----------|-------|
| 1 | 1 | ring 3 reads DR0 | **#DB** with BD set | protects debug registers |

### Control registers (CR0, CR2, CR3)

| # | Register | CPL | Read | Write | Notes |
|---|----------|:---:|------|-------|-------|
| 1 | CR0 | 0 | OK | OK (PE, PG bits) | |
| 2 | CR0 | 3 | **#GP** | **#GP** | privileged |
| 3 | CR2 | 0 | OK (page fault addr) | write ignored | read-only effectively |
| 4 | CR3 | 0 | OK | OK (page dir base) | write flushes TLB |

## Pre/Post State (representative cases)

### Code execution breakpoint (DR0)
PRE (PM32, CPL=0):
  DR0 = 0x00100030  (address of target instruction)
  DR7 = 0x00000001  (L0=1, G0=0; R/W0=00 execute, LEN0=00 byte)
  DR6 = 0x00000000
OP:  execution reaches 0x00100030
POST:
  #DB exception
  DR6 = 0x00000001  (B0=1 — breakpoint 0 triggered)
  ← DR7 L0 auto-clears after #DB (local enable is one-shot on some CPUs)

### Data write breakpoint (DR1)
PRE (PM32, CPL=0):
  var_addr = 0x00120000
  DR1 = 0x00120000
  DR7 = 0x0C040004  (L1=1 bit2; R/W1=01 write bits18-19; LEN1=11 dword bits26-27)
  DR6 = 0x00000000
  EAX = 0xDEADBEEF
OP:  MOV [var_addr], EAX
POST:
  #DB exception fires after write completes
  DR6 = 0x00000002  (B1=1 — breakpoint 1 triggered)
  Memory at 0x00120000 = 0xDEADBEEF  (write completed before trap)

### Single-step via TF
PRE (PM32, CPL=0):
  EFLAGS = 0x00000102  (IF=1, TF=0)
  DR6 = 0x00000000
OP:  PUSHFD
     OR DWORD [ESP], 0x0100   (set TF bit 8)
     POPFD
     NOP                      (this instruction executes normally)
POST:  (after NOP)
  #DB exception  (BS bit set in DR6)
  DR6 = 0x00004000  (BS=1 bit14 — single step triggered)
  ← TF cleared by #DB entry; re-set by IRETD to continue stepping

### General detect (GD) protects DRs from ring 3
PRE (PM32, CPL=3):
  DR7 = 0x00002000  (GD=1 bit13 — debug register access protected)
OP:  MOV EAX, DR0    (ring 3 reads debug register)
POST:
  #DB exception
  DR6 = 0x00008000  (BD=1 bit15 — debug register access detected)
  ← GD bit cleared by #DB to allow handler to access DRs

### CR0 read at CPL=0 — OK
PRE (PM32, CPL=0):
  CR0 = 0x80000011   (PG=1, PE=1, MP=1, ET=1)
OP:  MOV EAX, CR0
POST:
  EAX = 0x80000011

### CR0 read at CPL=3 — #GP
PRE (PM32, CPL=3):
  CR0 = 0x80000011
OP:  MOV EAX, CR0
POST:
  #GP(0) exception
  EAX unchanged

### CR3 write flushes TLB
PRE (PM32, CPL=0):
  CR3 = 0x0009F000
  EAX = 0x000A1000
  TLB has cached entries
OP:  MOV CR3, EAX
POST:
  CR3 = 0x000A1000
  TLB fully flushed (all non-global entries invalidated)

## State Save/Restore

- **Save:** DR0-DR7; CR0; EFLAGS (TF)
- **Restore:** clear all breakpoints; restore TF=0

## Pass/Fail Criteria

- **PASS:** breakpoints fire at correct address; DR6/DR7 bits correct; TF works
- **FAIL:** no #DB or wrong DR6 bits
- **SKIP:** GEN < 80386
