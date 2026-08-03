# Spec: Memory Map & Aliasing

## Metadata
- **Source file:** `src/core/memory.asm`
- **TIER:** HARDWARE | VENUE: G | GEN: 8086+ | ORACLE: manual
- **Impl-plan:** Phase 8, area `Memory`
- **Coverage:** [§10, §10.1](../../coverage-matrix.md#101-hard-cases--a20--address-space)
- **Refs:** [references.md](../../references.md) — IBM PC/AT Tech Ref

## Purpose

Verify the PC memory map: conventional memory (0–640K), UMA/ROM/video holes (640K–1MB),
HMA (1MB+64K), extended memory. Test video memory aliasing and BIOS data area sanity.

## Memory Map

| Range | Size | Region | Notes |
|-------|------|--------|-------|
| 0x00000–0x9FFFF | 640K | Conventional memory | usable RAM |
| 0xA0000–0xBFFFF | 128K | Video memory (VGA) | A000=graphics, B000=mono, B800=text |
| 0xC0000–0xC7FFF | 32K | Video BIOS ROM | VGA BIOS |
| 0xC8000–0xEFFFF | 160K | Expansion ROM / adapter BIOS | IDE, SCSI, etc. |
| 0xF0000–0xFFFFF | 64K | System BIOS ROM | main BIOS |
| 0x100000–0x10FFEF | ~64K | HMA (High Memory Area) | A20-dependent |
| 0x110000+ | — | Extended memory | XMS |

## Test Cases

### Conventional memory R/W

| # | Address | Write | Read back | Expected | Notes |
|---|---------|:-----:|-----------|----------|-------|
| 1 | 0x00100 | 0xAA55 | 0xAA55 | matches | BDA area |
| 2 | 0x80000 | 0x1234 | 0x1234 | matches | upper conventional |
| 3 | 0x9FFFF | 0xDEAD | 0xDEAD | matches | top of conventional |

### Video memory aliasing

| # | Segment | Physical range | Write test | Expected | Notes |
|---|---------|:--------------:|------------|----------|-------|
| 1 | 0xA000 | 0xA0000–0xAFFFF | write/read | VRAM graphics | mode-dependent |
| 2 | 0xB000 | 0xB0000–0xB7FFF | write/read | VRAM mono text | MDA-compatible |
| 3 | 0xB800 | 0xB8000–0xBFFFF | write/read | VRAM color text | CGA/VGA text |

| # | Test | Expected | Notes |
|---|------|----------|-------|
| 1 | Write to 0xB800:0000, read via physical 0xB8000 | matches | text VRAM alias |
| 2 | Write to 0xA000:0000 in mode 13h | appears on screen (or read back) | chain-4 VRAM |

### BIOS data area (0x00400–0x004FF)

| # | Offset | Content | Test | Expected | Notes |
|---|--------|---------|------|----------|-------|
| 1 | 0x13 (word) | Base memory size (KB) | read | 0x0280 (640K) or 0x0200 (512K) | sanity check |
| 2 | 0x49 (byte) | Video mode | read | mode set by BIOS | check plausible value |
| 3 | 0x4A (word) | Screen columns | read | 80 (text mode) | |
| 4 | 0x4E (word) | Cursor position page 0 | write/read | round-trip | |

### BIOS ROM detection

| # | Address | Expected | Notes |
|---|---------|----------|-------|
| 1 | 0xFFFF0 (reset vector) | `EA 05 E0 00 F0` (far JMP) or `EB` | BIOS entry point |
| 2 | 0xFE000 | ROM readable (not 0xFF fill) | BIOS data |
| 3 | 0xF0000 | signature `_RESET_` or BIOS string | varies by BIOS |

### HMA access (A20 dependent)

| # | A20 | Address | Expected | Notes |
|---|:---:|---------|----------|-------|
| 1 | ON | 0x10FFEF | readable (RAM or ROM) | HMA accessible |
| 2 | OFF | 0x10FFEF | wraps to 0x0FFEF | see [a20.md](a20.md) |

### Shadow RAM detection (chipset-dependent)

| # | Address | Test | Expected | Notes |
|---|---------|------|----------|-------|
| 1 | 0xC0000 | write byte, read back | if writable: shadow RAM present | chipset-specific |
| 2 | 0xF0000 | write byte, read back | if ROM: write ignored (reads 0xFF or original) | |

> **Shadow RAM note:** whether ROM areas are writable (shadow RAM copy) is
> chipset-dependent. This test reports behavior but does not assert a specific result.

### Extended memory (XMS)

| # | Address | Test | Expected | Notes |
|---|---------|------|----------|-------|
| 1 | 0x100000 | write/read (A20 on) | RAM accessible | extended memory |
| 2 | 0x110000 | write/read | RAM accessible | beyond HMA |

> **Requirement:** A20 must be enabled for extended memory access from real mode.
> See [a20.md](a20.md).

## Pre/Post State (representative cases)

### Conventional memory R/W
PRE (real mode):
  DS = 0x0000
  Memory at 0x00000400 = 0x0000  (BDA area)
  EAX = 0xDEADBEEF
OP:  MOV [0x00000400], EAX
POST:
  Memory at 0x00000400 = 0xDEADBEEF  ← R/W works in conventional RAM
  ← 0x00400 is inside BDA; must restore after test

### Video memory aliasing — text mode VRAM
PRE (real mode, text mode 3):
  ES = 0xB800
  Memory at physical 0xB8000 = unknown
  AX = 0x1F41   (white-on-blue 'A')
OP:  MOV ES:[0x0000], AX   ; write to 0xB800:0000
POST:
  Physical 0xB8000 = 0x1F41   ← text VRAM at correct alias
  ← Character 'A' appears at top-left of screen

### BIOS data area sanity
PRE:
  DS = 0x0040   (BDA segment)
OP:  MOV AX, [0x0013]    ; read base memory size
POST:
  AX = 0x0280           ← 640K = 0x0280 (typical)
  (Some systems: 0x0200 = 512K)

OP:  MOV AL, [0x0049]    ; read video mode
POST:
  AL = 0x03             ← text mode 3 (typical)

OP:  MOV AX, [0x004A]    ; read screen columns
POST:
  AX = 0x0050           ← 80 columns

### BIOS ROM detection
PRE:
  CS = 0xF000
  DS = 0x0000
OP:  ; read reset vector at physical 0xFFFF0
     ; segment 0xF000, offset 0xFFF0
     MOV AL, [0xFFF0]   ; CS=0xF000
POST:
  AL = 0xEA             ← first byte of far JMP (typical BIOS reset)
  ← 0xEA = JMP far ptr16:32 opcode

### HMA access — A20 dependent
PRE (real mode, A20 ON):
  DS = 0xFFFF, SI = 0x0010
  Memory at physical 0x100010 = 0x77
OP:  MOV AL, [DS:SI]    ; linear 0x100010
POST:
  AL = 0x77            ← HMA accessible with A20 enabled

PRE (real mode, A20 OFF):
  DS = 0xFFFF, SI = 0x0010
  Memory at physical 0x100010 = 0x77 (but A20 masked)
  Memory at physical 0x000010 = 0xAA
OP:  MOV AL, [DS:SI]
POST:
  AL = 0xAA            ← wraps to 0x000010 (A20 off)

### Shadow RAM detection
PRE:
  Memory at physical 0xC0000 = ROM byte (e.g., 0x55)
  DS = 0x0000
OP:  MOV byte [0xC0000], 0x99   ; try to write to video BIOS ROM area
     MOV AL, [0xC0000]          ; read back
POST:
  If AL = 0x99 → shadow RAM writable (chipset copies ROM to RAM)
  If AL = 0x55 → ROM is read-only (write ignored)
  ← Result is chipset-dependent; report only, don't assert

## State Save/Restore

- **Memory:** save and restore all test locations (conventional, video, BDA bytes used)
- **Video mode:** save and restore video mode if test changed it
- **BDA:** restore any BIOS data area bytes modified

## Pass/Fail Criteria

- **PASS:** conventional memory R/W works; video memory accessible at correct aliases;
  BDA fields have plausible values; ROM readable; HMA accessible with A20 on
- **FAIL:** video memory wrong address; RAM test fails; BIOS ROM missing
- **SKIP:** HMA/XMS tests if A20 cannot be enabled

## Known Divergences

- **Shadow RAM:** chipset-dependent; varies between boards and emulators.
  Report only, do not assert.
- **Video memory size:** VGA has 256K VRAM; only 128K visible at 0xA0000.
  Banking via VGA registers maps different portions.
- **BIOS variations:** reset vector format, BIOS string, BDA layout can vary.
  Use conservative assertions (plausible range, not exact value).
