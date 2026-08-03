# Spec: 486 Alignment Check (#AC)

## Metadata
- **Source file:** `src/cpu/80486/ac.asm`
- **TIER:** RING0 | VENUE: G | GEN: 80486+ | ORACLE: manual
- **Impl-plan:** Phase 6, area `486-AC`
- **Coverage:** [§8.3](../../coverage-matrix.md#83-hard-cases--alignment-check)
- **Divergences:** [prep-analysis §1.2a](../../prep-analysis.md#12a-generation-specific-divergences-286-vs-386-vs-486)

## Purpose

Verify the alignment check exception (#AC, vector 17) on the 486.
Requires CR0.AM=1, EFLAGS.AC=1, and CPL=3.

## Test Cases

### Alignment check disabled (default)

| # | CR0.AM | EFLAGS.AC | CPL | Misaligned access | Expected | Notes |
|---|:------:|:---------:|:---:|:-----------------:|----------|-------|
| 1 | 0 | 0 | 3 | yes | OK | no #AC |
| 2 | 1 | 0 | 3 | yes | OK | AC flag not set |
| 3 | 1 | 1 | 0 | yes | OK | ring 0 never triggers #AC |

### Alignment check enabled

| # | CR0.AM | EFLAGS.AC | CPL | Misaligned access | Expected | Notes |
|---|:------:|:---------:|:---:|:-----------------:|----------|-------|
| 1 | 1 | 1 | 3 | word at odd address | **#AC** | alignment fault |

### What triggers #AC

| # | Access type | Address | Aligned? | Notes |
|---|------------|---------|:--------:|-------|
| 1 | word (2B) | even | yes | OK |
| 2 | word (2B) | odd | no | **#AC** |
| 3 | dword (4B) | multiple of 4 | yes | OK |
| 4 | dword (4B) | not multiple of 4 | no | **#AC** |
| 5 | byte (1B) | any | always aligned | OK |

### #AC error code

| # | Exception | Error code | Notes |
|---|-----------|:----------:|-------|
| 1 | #AC | 0 | always 0 (no selector involved) |

## Pre/Post State (representative cases)

### Misaligned dword at CPL=3 with AM+AC → #AC
PRE (PM32, CPL=3, paging on):
  CR0 = 0x40000011    (AM=1 bit18, PE=1, MP=1, ET=1)
  EFLAGS = 0x00040202  (AC=1 bit18, IF=1 bit9, bit1=1 always set)
  ESI = 0x00100001   (not aligned to 4 — dword at odd offset)
  mem at [ESI] = 0x00000000
  EAX = 0xDEADBEEF
OP:  MOV [ESI], EAX    (dword store at non-4-aligned address)
POST:
  #AC exception (vector 17)
  Error code on stack: 0x0000  (always zero)
  ESI = 0x00100001  ← unchanged
  Memory unchanged (write did not complete)

### Same misaligned access with AM=0 → OK
PRE (PM32, CPL=3):
  CR0 = 0x00000011   (AM=0, PE=1, MP=1, ET=1)
  EFLAGS = 0x00040202  (AC=1 but AM=0 → ignored)
  ESI = 0x00100001   (misaligned)
  EAX = 0xDEADBEEF
OP:  MOV [ESI], EAX
POST:
  no exception       ← AM=0 disables alignment check entirely
  Memory at 0x00100001 = 0xDEADBEEF

### Misaligned word at CPL=0 with AM+AC → OK
PRE (PM32, CPL=0):
  CR0 = 0x40000011   (AM=1)
  EFLAGS = 0x00040202  (AC=1)
  ESI = 0x00100001   (odd address — misaligned for word)
OP:  MOV [ESI], AX
POST:
  no exception       ← ring 0 never triggers #AC regardless of AM/AC
  Memory updated

### Aligned dword at CPL=3 with AM+AC → OK
PRE (PM32, CPL=3):
  CR0 = 0x40000011   (AM=1)
  EFLAGS = 0x00040202  (AC=1)
  ESI = 0x00100000   (aligned to 4)
  EAX = 0xDEADBEEF
OP:  MOV [ESI], EAX    (dword store at 4-aligned address)
POST:
  no exception       ← aligned access never triggers #AC
  Memory at 0x00100000 = 0xDEADBEEF

## State Save/Restore

- **Save:** CR0 (AM bit), EFLAGS (AC bit), IDT entry 17
- **Restore:** CR0.AM=0, AC=0; restore IDT

## Pass/Fail Criteria

- **PASS:** #AC triggers only when AM+AC+CPL3 all set; correct vector and error code
- **FAIL:** #AC at ring 0 or when AM/AC not set
- **SKIP:** GEN < 80486
