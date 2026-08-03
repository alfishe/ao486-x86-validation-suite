# Spec: 386 Control Registers

## Metadata
- **Source file:** `src/cpu/80386/cr.asm`
- **TIER:** RING0 | VENUE: G | GEN: 80386+ | ORACLE: manual
- **Impl-plan:** Phase 5, area `386-CR`
- **Coverage:** [§7](../../coverage-matrix.md#7-cpu--80386-pri-1-32-bit--paging--v86)
- **Divergences:** [prep-analysis §1.2a](../../prep-analysis.md#12a-generation-specific-divergences-286-vs-386-vs-486)

## Purpose

Verify CR0 bit definitions, MOV CRn/DRn privilege enforcement, CR3 TLB flush,
and generation-specific CR0 bits.

## CR0 Bit Definitions

| Bit | Name | 386 | 486+ | Meaning |
|:---:|------|:---:|:----:|---------|
| 0 | PE | ✓ | ✓ | Protection Enable |
| 1 | MP | ✓ | ✓ | Monitor coProcessor |
| 2 | EM | ✓ | ✓ | Emulate |
| 3 | TS | ✓ | ✓ | Task Switched |
| 4 | ET | ✓ | ✓ | Extension Type (287=0, 387=1) |
| 5 | NE | ✓ | ✓ | Numeric Error (386+) |
| 16 | WP | — | ✓ | Write Protect (486+) |
| 18 | AM | — | ✓ | Alignment Mask (486+) |
| 29 | NW | — | ✓ | Not Write-through (486+) |
| 30 | CD | — | ✓ | Cache Disable (486+) |
| 31 | PG | ✓ | ✓ | Paging Enable |

## Test Cases

### MOV CR0 read/write

| # | Action | Expected | Notes |
|---|--------|----------|-------|
| 1 | MOV EAX, CR0 at CPL=0 | OK | reads all defined bits |
| 2 | MOV CR0, EAX at CPL=0 | OK | writes defined bits |
| 3 | MOV EAX, CR0 at CPL=3 | **#GP** | privileged |

### ET bit (386)

| # | ET value | Meaning | Notes |
|---|:--------:|---------|-------|
| 0 | 287 present | uses 16-bit protocol | |
| 1 | 387 present | uses 32-bit protocol | set at reset based on FPU type |

### TS bit and WAIT/ESC behavior

| # | TS | MP | Instruction | Expected | Notes |
|---|:--:|:--:|-------------|----------|-------|
| 1 | 1 | 1 | ESC (FPU op) | **#NM** (device not available) | FPU context stale |
| 2 | 1 | 1 | WAIT/FWAIT | **#NM** | |
| 3 | 1 | 0 | WAIT/FWAIT | OK (no #NM) | MP=0 disables WAIT check |
| 4 | 0 | 1 | ESC | OK | FPU context valid |

> CLTS clears TS. Task switch sets TS.

### EM bit

| # | EM | Instruction | Expected | Notes |
|---|:--:|-------------|----------|-------|
| 1 | 1 | ESC (FPU op) | **#NM** | emulation mode — no real FPU used |
| 2 | 0 | ESC | OK | real FPU used |

### CR3 and TLB

| # | Action | Expected | Notes |
|---|--------|----------|-------|
| 1 | MOV CR3, EAX | TLB flushed (non-global entries) | changing page directory |
| 2 | MOV EAX, CR3 | reads page directory base | bits 12-31 = PDBR |

### 486+ new bits

| # | Bit | Action | Expected | Notes |
|---|-----|--------|----------|-------|
| 1 | WP=1 | ring 0 writes to read-only page | **#PF** | write protect enforced |
| 2 | WP=0 | ring 0 writes to read-only page | OK | legacy behavior |
| 3 | CD=1 | cache disabled | — | TIMING/HARDWARE tier |
| 4 | AM=1 + EFLAGS.AC=1 + CPL=3 | misaligned access | **#AC** | alignment check |

## Pre/Post State (representative cases)

### MOV CR0 read at CPL=0
PRE (PM32, CPL=0):
  CR0 = 0x80000011   (PG=1, PE=1, ET=1, MP=1; paging active)
OP:  MOV EAX, CR0
POST:
  EAX = 0x80000011   ← all defined bits readable; undefined bits read as 0

### MOV CR0 write — set TS
PRE (PM32, CPL=0):
  CR0 = 0x00000011   (PE=1, MP=1, ET=1, TS=0)
  EAX = 0x00000019   (TS=1 to be set: bit 3)
OP:  MOV CR0, EAX
POST:
  CR0 = 0x00000019   (PE=1, MP=1, ET=1, TS=1)
  ← next FPU/WAIT instruction will trigger #NM

### MOV CR0 at CPL=3 — #GP
PRE (PM32, CPL=3):
  CR0 = 0x00000011
  EAX = 0x00000011
OP:  MOV CR0, EAX     (ring 3 attempting privileged write)
POST:
  #GP(0) exception
  CR0 = 0x00000011   ← unchanged

### TS+MP → #NM on WAIT
PRE (PM32, CPL=0):
  CR0 = 0x0000001A   (MP=1, ET=1, TS=1 — bit3 set, bit1 set)
OP:  WAIT
POST:
  #NM exception (device not available — FPU context stale)
  ← Task Switched bit forces #NM before WAIT touches FPU

### TS=1, MP=0 → WAIT OK
PRE (PM32, CPL=0):
  CR0 = 0x00000018   (ET=1, TS=1, MP=0)
OP:  WAIT
POST:
  no exception       ← MP=0 disables WAIT/FWAIT check
  CR0 unchanged

### EM=1 → ESC #NM
PRE (PM32, CPL=0):
  CR0 = 0x00000006   (EM=1, PE=1 — emulation mode)
OP:  FADD ST0, ST1    (any FPU instruction)
POST:
  #NM exception       ← EM=1 means FPU absent, must trap for emulation

### CR3 write → TLB flush
PRE (PM32, CPL=0, paging on):
  CR3 = 0x0009F000   (PDBR = page directory at phys 0x9F000)
  TLB has entry: VA 0x00103000 → PA 0x00021000 (cached)
  EAX = 0x000A1000   (new page dir at phys 0xA1000)
OP:  MOV CR3, EAX
POST:
  CR3 = 0x000A1000
  TLB flushed         ← cached VA→PA mappings invalidated
  ← next access to 0x00103000 re-walks page tables

## State Save/Restore

- **Save:** CR0, CR3
- **Restore:** restore original values

## Known Divergences

| Bit | 386 | 486+ | Action |
|-----|-----|------|--------|
| WP | absent | present | gen-gate |
| AM | absent | present | gen-gate |
| NW/CD | absent | present | gen-gate |

## Pass/Fail Criteria

- **PASS:** all CR0 bits readable/writable; privilege enforced; TS/EM behavior correct
- **FAIL:** wrong #NM or privilege violation
- **SKIP:** 486+ bits on 386
