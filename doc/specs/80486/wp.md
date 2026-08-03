# Spec: 486 Write Protect (CR0.WP)

## Metadata
- **Source file:** `src/cpu/80486/wp.asm`
- **TIER:** RING0 | VENUE: G | GEN: 80486+ | ORACLE: manual
- **Impl-plan:** Phase 6, area `486-WP`
- **Coverage:** [§7.1](../../coverage-matrix.md#71-hard-cases--paging)
- **Divergences:** [prep-analysis §1.2a](../../prep-analysis.md#12a-generation-specific-divergences-286-vs-386-vs-486)
- **Prerequisite:** [paging.md](../80386/paging.md)

## Purpose

Verify CR0.WP: when set, ring 0 cannot write to read-only pages.
When clear (386 behavior), ring 0 bypasses the R/W bit.

## Test Cases

### WP=0 (386-compatible, default on 386)

| # | PTE R/W | CPL | Write | Expected | Notes |
|---|:-------:|:---:|:-----:|----------|-------|
| 1 | 0 (read-only) | 0 | write | OK | ring 0 bypasses |
| 2 | 0 (read-only) | 3 | write | **#PF** | ring 3 blocked |

### WP=1 (486+ write protect)

| # | PTE R/W | CPL | Write | Expected | Notes |
|---|:-------:|:---:|:-----:|----------|-------|
| 1 | 0 (read-only) | 0 | write | **#PF** | ring 0 blocked too |
| 2 | 0 (read-only) | 3 | write | **#PF** | ring 3 blocked |

### WP=1 does not affect reads

| # | PTE R/W | CPL | Read | Expected | Notes |
|---|:-------:|:---:|:----:|----------|-------|
| 1 | 0 (read-only) | 0 | read | OK | reads always work |
| 2 | 0 (read-only) | 3 | read | OK | |

## Pre/Post State (representative cases)

### WP=0 — ring 0 writes to read-only page (386 behavior)
PRE (PM32, CPL=0, paging on):
  CR0 = 0x80000011    (PG=1, PE=1, MP=1, ET=1; WP=0 bit16 clear)
  PTE for VA 0x08001000 = 0x00100005  (P=1, R/W=0 read-only, US=1 user)
  EAX = 0xDEADBEEF
OP:  MOV [0x08001000], EAX   (ring 0 write to read-only page)
POST:
  Memory at VA 0x08001000 = 0xDEADBEEF  ← write succeeds
  ← 386 behavior: ring 0 bypasses R/W bit when WP=0

### WP=1 — ring 0 write to read-only page → #PF
PRE (PM32, CPL=0, paging on):
  CR0 = 0x80010011    (PG=1, WP=1 bit16, PE=1, MP=1, ET=1)
  PTE for VA 0x08001000 = 0x00100005  (P=1, R/W=0 read-only, US=1 user)
  EAX = 0xDEADBEEF
OP:  MOV [0x08001000], EAX   (ring 0 write to read-only page with WP=1)
POST:
  #PF exception
  CR2 = 0x08001000
  Error code: 0x0002  (bit0=1 present, bit1=1 write, bit2=0 supervisor)
  Memory unchanged    ← write blocked

### WP=1 — ring 0 read from read-only page still OK
PRE (PM32, CPL=0, paging on):
  CR0 = 0x80010011    (WP=1)
  PTE for VA 0x08001000 = 0x00100005  (R/W=0 read-only)
  Memory at VA 0x08001000 = 0xCAFEBABE
OP:  MOV EAX, [0x08001000]   (ring 0 read from read-only page)
POST:
  EAX = 0xCAFEBABE    ← read succeeds; WP does not affect reads

### WP=1 — ring 0 write to read-write page OK
PRE (PM32, CPL=0, paging on):
  CR0 = 0x80010011    (WP=1)
  PTE for VA 0x08001000 = 0x00100007  (R/W=1 read-write)
  EAX = 0x12345678
OP:  MOV [0x08001000], EAX   (ring 0 write to read-write page)
POST:
  Memory at VA 0x08001000 = 0x12345678  ← write succeeds (R/W=1)

### WP=1 — ring 3 write to read-only page → #PF
PRE (PM32, CPL=3, paging on):
  CR0 = 0x80010011    (WP=1)
  PTE for VA 0x08001000 = 0x00100005  (R/W=0 read-only, US=1 user)
  EAX = 0xDEADBEEF
OP:  MOV [0x08001000], EAX
POST:
  #PF exception      ← ring 3 always blocked from writing read-only pages
  Error code: 0x0003  (present, write, user)

## State Save/Restore

- **Save:** CR0 (WP bit), page table entries
- **Restore:** CR0.WP=0; restore PTEs

## Pass/Fail Criteria

- **PASS:** with WP=1, ring 0 write to read-only page → #PF; reads still work
- **FAIL:** ring 0 writes through read-only page when WP=1
- **SKIP:** GEN < 80486 (WP bit absent on 386)
