# Spec: 386 Paging

## Metadata
- **Source file:** `src/cpu/80386/paging.asm`
- **TIER:** RING0 | VENUE: G | GEN: 80386+ | ORACLE: manual
- **Impl-plan:** Phase 5, area `386-Page`
- **Coverage:** [§7](../../coverage-matrix.md#7-cpu--80386-pri-1-32-bit--paging--v86), [§7.1](../../coverage-matrix.md#71-hard-cases--paging)
- **Prerequisite:** [286-pm-infra.md](../80186-286/286-pm-infra.md)

## Purpose

Verify page directory/table translation, PTE flags (P/RW/U/S/A/D/PS),
#PF with CR2 error address, TLB behavior, and supervisor/user page access.

## Paging Activation

```nasm
; 1. Build page directory + page tables in memory
; 2. Load CR3 with page directory physical address
    mov eax, page_dir_phys
    mov cr3, eax
; 3. Set PG bit in CR0 (must already be in PM)
    mov eax, cr0
    or eax, CR0_PG
    mov cr0, eax
; 4. Far jump to flush prefetch
    jmp dword CODE_SEL0:paging_on
```

## Page Table Entry (PTE) Format

```
Bit  Field
0    P (present)
1    R/W (1=read/write, 0=read-only)
2    U/S (1=user, 0=supervisor)
3    A (accessed — set by CPU)
4    D (dirty — set by CPU on write)
5    (reserved, 0)
6    (reserved, 0)
7    PS (page size: 0=4KB, 1=4MB in PDE — 386 doesn't have PS)
8    G (global — 386 doesn't have G)
9-11 (available for OS)
12-31 page frame address (physical address >> 12)
```

## Test Cases

### Identity mapping

| # | VA | PTE | Expected PA | Notes |
|---|----|-----|-------------|-------|
| 1 | 0x00100000 | frame=0x00100, P=1 | 0x00100000 | identity |
| 2 | 0x00101000 | frame=0x00101, P=1 | 0x00101000 | next page |

### Non-identity mapping

| # | VA | PTE | Expected PA | Notes |
|---|----|-----|-------------|-------|
| 1 | 0xC0001000 | frame=0x00010 | 0x00010000 | remap to low memory |

### Page not present (#PF)

| # | PTE P bit | Access | Expected | CR2 | Error code | Notes |
|---|:---------:|--------|----------|:---:|:----------:|-------|
| 1 | 0 | read | **#PF** | VA | P=0, W/R, U/S | |
| 2 | 0 | write | **#PF** | VA | P=0, W=1, ... | write flag set |

> CR2 holds the faulting linear address. Error code: bit 0=P (0=not present),
> bit 1=W/R (1=write), bit 2=U/S (1=user).

### Supervisor vs user pages

| # | PTE U/S | CPL | Access | Expected | Notes |
|---|:-------:|:---:|--------|----------|-------|
| 1 | 0 (supervisor) | 0 | read/write | OK | ring 0 can access |
| 2 | 0 (supervisor) | 3 | read/write | **#PF** | ring 3 blocked |
| 3 | 1 (user) | 3 | read | OK | |
| 4 | 1 (user) | 3 | write | OK if R/W=1 | |

### Read-only pages

| # | PTE R/W | CPL | Write access | Expected | Notes |
|---|:-------:|:---:|-------------|----------|-------|
| 1 | 0 (read-only) | 0 | write | OK (ring 0 bypasses) | 386 allows ring 0 write |
| 2 | 0 (read-only) | 3 | write | **#PF** | ring 3 blocked |
| 3 | 1 (read-write) | 3 | write | OK | |

> **Note:** 386 ring 0 can write to read-only pages.
> 486+ with CR0.WP=1 enforces read-only at ring 0 too. See [wp.md](../80486/wp.md).

### Accessed / Dirty bits

| # | Initial A/D | Access | Expected A/D after | Notes |
|---|:-----------:|--------|:-----------------:|-------|
| 1 | A=0, D=0 | read | A=1, D=0 | CPU sets A on access |
| 2 | A=0, D=0 | write | A=1, D=1 | CPU sets both on write |

> Verify by reading the PTE after access and checking bits 5 (A) and 6 (D).

### TLB invalidation (INVLPG)

| # | Action | Expected | Notes |
|---|--------|----------|-------|
| 1 | INVLPG [addr] | TLB entry for addr invalidated | next access re-walks tables |
| 2 | MOV CR3, eax | full TLB flush (non-global) | |

### 4MB pages (PS bit in PDE)

| # | PS bit | Page size | Notes |
|---|:------:|:---------:|-------|
| 1 | 0 | 4KB | normal |
| 2 | 1 | 4MB | **486+ only** (PSE), SKIP on 386 |

## Page Directory/Table Setup

```
Page Directory (4KB, 1024 entries):
  Entry 0 → Page Table 0 (maps VA 0x00000000 - 0x003FFFFF)
  ...

Page Table (4KB, 1024 entries):
  Entry 0 → physical page 0x00000 (VA 0x00000000)
  Entry 1 → physical page 0x01000 (VA 0x00001000)
  ...
```

## Pre/Post State (representative cases)

### Identity mapping — VA == PA
PRE (PM32, CPL=0, paging on):
  CR3 = 0x0009F000 → page dir
  PDE[0] = 0x0009E007  (P=1, RW=1, US=1, frame=0x9E000 → page table 0)
  PTE[0x100] = 0x001007  (P=1, RW=1, US=1, frame=0x00100000>>12=0x100)
  VA  = 0x00100000
OP:  MOV EAX, [0x00100000]
POST:
  EAX = value at physical 0x00100000  ← identity: VA 0x00100000 == PA 0x00100000
  PTE[0x100] A bit = 1  (Accessed set by CPU)

### Non-identity mapping — VA != PA
PRE:
  PDE[0xC00] = 0x0009A007  (P=1, frame for VA 0xC0000000+)
  PTE[0x001] = 0x00001007  (P=1, frame=0x10000>>12=0x10 → PA 0x00010000)
  VA  = 0xC0001000
OP:  MOV EAX, [0xC0001000]
POST:
  EAX = value at physical 0x00010000  ← VA 0xC0001000 remapped to PA 0x00010000

### Page not present → #PF
PRE (PM32, CPL=0):
  PTE for VA 0x00400000 = 0x00000000  (P=0, not present)
  CR2 = 0x00000000  (stale)
  ESP0 stack available
OP:  MOV EAX, [0x00400000]   (read from not-present page)
POST:
  #PF exception
  CR2 = 0x00400000  ← faulting linear address captured
  Error code on stack: 0x0000  (bit0=0 not-present, bit1=0 read, bit2=0 supervisor)

### Write to read-only page at CPL=3 → #PF
PRE (PM32, CPL=3):
  PTE for VA 0x08001000 = 0x00100005  (P=1, RW=0 read-only, US=1 user)
  VA = 0x08001000
OP:  MOV [0x08001000], EAX   (ring 3 write to read-only page)
POST:
  #PF exception
  CR2 = 0x08001000
  Error code: 0x0003  (bit0=1 present, bit1=1 write, bit2=1 user)

### Ring 0 writes read-only page — OK (386 behavior)
PRE (PM32, CPL=0, CR0.WP=0 or absent on 386):
  PTE for VA 0x08001000 = 0x00100005  (RW=0 read-only)
  EAX = 0xDEADBEEF
OP:  MOV [0x08001000], EAX   (ring 0 bypasses R/W)
POST:
  Memory at VA 0x08001000 = 0xDEADBEEF  ← write succeeds
  ← Note: 486+ with WP=1 would #PF here; 386 always allows ring 0

### Accessed/Dirty bit set by CPU
PRE:
  PTE for VA 0x00200000 = 0x0020000C  (P=1,RW=1,US=0, A=0, D=0)
  bits: bit3=A=0, bit4=D=0
OP:  MOV EAX, [0x00200000]   (read access)
POST:
  PTE = 0x0020001C  (A=1 bit3 set, D=0 bit4 still clear) ← read sets Accessed only

OP:  MOV [0x00200000], EAX  (write access after A already set)
POST:
  PTE = 0x0020003C  (A=1, D=1 bit4 set) ← write sets Dirty

### INVLPG — invalidate single TLB entry
PRE:
  TLB cached: VA 0x00103000 → PA 0x00021000 (from old PTE)
  New PTE[0x103] = 0x00050007  (frame changed to 0x500000>>12)
OP:  INVLPG [0x00103000]
POST:
  TLB entry for 0x00103000 invalidated
  MOV EAX, [0x00103000] now reads from PA 0x000500000  ← re-walks page table

## State Save/Restore

- **Save:** CR0, CR3, all page table memory
- **Restore:** disable paging, restore CR3, restore tables

## Pass/Fail Criteria

- **PASS:** translation correct; #PF with right CR2 and error code; A/D bits set
- **FAIL:** wrong translation, wrong CR2, or missing #PF
- **SKIP:** GEN < 80386
