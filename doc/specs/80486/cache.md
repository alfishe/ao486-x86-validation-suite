# Spec: 486 Cache & WBINVD

## Metadata
- **Source file:** `src/cpu/80486/cache.asm`
- **TIER:** RING0 | VENUE: G | GEN: 80486+ | ORACLE: manual
- **Impl-plan:** Phase 6, area `486-Cache`
- **Coverage:** [§8.2](../../coverage-matrix.md#82-hard-cases--cache-coherence)
- **Divergences:** [prep-analysis §1.2a](../../prep-analysis.md#12a-generation-specific-divergences-286-vs-386-vs-486)

## Purpose

Verify INVD, WBINVD, INVLPG, CR0.CD/CR0.NW cache control, and cache line behavior.

## Test Cases

### INVD (invalidate cache, no writeback)

| # | Action | Expected | Notes |
|---|--------|----------|-------|
| 1 | INVD at CPL=0 | entire cache invalidated | dirty lines NOT written back |
| 2 | INVD at CPL=3 | **#GP** | privileged |

### WBINVD (writeback and invalidate)

| # | Action | Expected | Notes |
|---|--------|----------|-------|
| 1 | WBINVD at CPL=0 | dirty lines written back, then cache invalidated | safe flush |

### INVLPG (invalidate TLB entry)

| # | Action | Expected | Notes |
|---|--------|----------|-------|
| 1 | INVLPG [addr] | TLB entry for addr invalidated | next access re-walks page tables |

### CR0.CD (cache disable)

| # | CD | Access | Expected | Notes |
|---|:--:|--------|----------|-------|
| 1 | 1 | memory read | cache bypassed | goes to memory directly |
| 2 | 0 | memory read | cache used normally | |

### CR0.NW (not write-through)

| # | NW | Notes |
|---|:--:|-------|
| 1 | 1 | write-through disabled (write-back mode) |
| 2 | 0 | write-through enabled |

> NW and CD together: NW=1,CD=1 = cache completely disabled.
> NW=0,CD=0 = normal operation.

### Self-modifying code (SMC) cache coherence

| # | Action | Expected | Notes |
|---|--------|----------|-------|
| 1 | Write new instruction to code page, then execute | CPU sees new instruction | 486 has cache coherence for SMC |

> **486-specific:** the 486 was the first x86 with on-chip cache that required
> SMC awareness. Verify that modifying code in memory invalidates the
> corresponding cache line.

## Pre/Post State (representative cases)

### INVD — invalidate cache without writeback
PRE (PM32, CPL=0):
  CR0 = 0x60000011    (CD=1, NW=1, PE=1, MP=1, ET=1; cache disabled)
  Cache contains dirty line: PA 0x00100000, data=0xDEADBEEF (not yet in memory)
  Memory at PA 0x00100000 = 0x00000000 (stale)
OP:  INVD               (invalidate entire cache, no writeback)
POST:
  Cache invalidated     ← all lines discarded
  Memory at PA 0x00100000 = 0x00000000  ← dirty data LOST (not written back)

### WBINVD — writeback and invalidate
PRE (PM32, CPL=0):
  CR0 = 0x00000011    (CD=0, NW=0, normal caching)
  Cache contains dirty line: PA 0x00100000, data=0xDEADBEEF
  Memory at PA 0x00100000 = 0x00000000 (stale)
OP:  WBINVD             (writeback all dirty lines, then invalidate)
POST:
  Memory at PA 0x00100000 = 0xDEADBEEF  ← dirty line written back
  Cache invalidated

### INVD at CPL=3 → #GP
PRE (PM32, CPL=3):
  CR0 = 0x00000011
OP:  INVD
POST:
  #GP(0) exception    ← privileged instruction

### INVLPG — single TLB entry invalidation
PRE (PM32, CPL=0, paging on):
  TLB cached: VA 0x00103000 → PA 0x00021000 (stale mapping)
  PTE[0x103] updated to frame=0x500000>>12=0x500
  CR0 = 0x80000011    (PG=1)
OP:  INVLPG [0x00103000]
POST:
  TLB entry for VA 0x00103000 invalidated
  Next MOV EAX,[0x00103000] reads from PA 0x0500000  ← re-walks page table

### CR0.CD=1 — cache bypassed on read
PRE (PM32, CPL=0):
  CR0 = 0x60000011    (CD=1, NW=1)
  Memory at PA 0x00100000 = 0x11223344
  Cache has stale line: PA 0x00100000, data=0xDEADBEEF
OP:  MOV EAX, [0x00100000]
POST:
  EAX = 0x11223344    ← cache bypassed, read goes to memory

### SMC — self-modifying code coherence
PRE (PM32, CPL=0):
  Code at VA 0x00001000: 0x90  (NOP)
  Cache line for VA 0x00001000: cached as NOP
  EAX = 0x90C30090    (contains: NOP, RET, ... )
OP:  MOV BYTE [0x00001000], 0xC3   (overwrite NOP with RET)
     JMP 0x00001000               (execute modified code)
POST:
  Execution returns (RET executes)  ← cache line invalidated on write
  ← 486 guarantees SMC coherence; CPU saw the new instruction

## State Save/Restore

- **Save:** CR0 (CD/NW bits)
- **Restore:** restore CD=0, NW=0 (normal caching)

## Pass/Fail Criteria

- **PASS:** INVD/WBINVD privileged; INVLPG works; CD/NW affect cache
- **FAIL:** SMC not detected or cache not invalidated
- **SKIP:** GEN < 80486
