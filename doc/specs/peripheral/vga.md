# Spec: VGA (Video Graphics Array)

## Metadata
- **Source file:** `src/peripheral/vga/vga.asm`
- **TIER:** HARDWARE | VENUE: G | GEN: 8086+ | ORACLE: manual
- **Impl-plan:** Phase 7, area `VGA`
- **Coverage:** [§9.7](../../coverage-matrix.md#97-vga)
- **Detail:** [prep-analysis §6.4](../../prep-analysis.md#64-vga--stateful-traps)
- **Refs:** [references.md](../../references.md) — VGA reference (Ferraro); IBM VGA Tech Ref

## Purpose

Verify VGA register behavior, focusing on the many flip-flops, index/data pairs, and
stateful paths that emulators get wrong: AC flip-flop, sequencer/graphics index/data
round-trip, write modes 0–3, read modes 0–1, map/bit mask, set/reset, CRTC protect,
DAC auto-increment and 3-write RGB sequence, chain-4 (mode 13h).

## Port Map

### General registers

| Port | Register | Notes |
|------|----------|-------|
| 0x3C0 | Attribute controller (AC) index/data | shared port, **flip-flop** toggles index↔data |
| 0x3C1 | AC data read | read the indexed AC register |
| 0x3C2 | Miscellaneous output (W) / Input status 0 (R) | |
| 0x3C4 | Sequencer address (index) | |
| 0x3C5 | Sequencer data | indexed by 0x3C4 |
| 0x3C6 | DAC mask | |
| 0x3C7 | DAC read index (W) / DAC state (R) | |
| 0x3C8 | DAC write index | auto-increments after 3 writes |
| 0x3C9 | DAC data | 3 writes per color: R, G, B (6-bit each) |
| 0x3CA | Feature control (R) | |
| 0x3CC | Miscellaneous output (R) | read-back of 0x3C2 write |
| 0x3CE | Graphics controller address (index) | |
| 0x3CF | Graphics controller data | indexed by 0x3CE |
| 0x3D4 | CRTC address (index) | (color mode; mono uses 0x3B4) |
| 0x3D5 | CRTC data | indexed by 0x3D4 |
| 0x3DA | Input status 1 (R) | **resets AC flip-flop** to index mode |

## Test Cases

### AC flip-flop (0x3C0) — **signature test**

| # | Action | Expected | Notes |
|---|--------|----------|-------|
| 1 | IN 0x3DA (reset flip-flop) | flip-flop = index mode | |
| 2 | OUT 0x3C0, 0x10 (index) | flip-flop now = data mode | |
| 3 | OUT 0x3C0, 0x01 (data) | AC reg 0x10 = 0x01 | |
| 4 | OUT 0x3C0, 0x11 (index) | toggles back to index | |
| 5 | OUT 0x3C0, 0x02 (data) | AC reg 0x11 = 0x02 | |
| 6 | IN 0x3DA, then IN 0x3C1 | reads AC reg 0x10 = 0x01 | verify read-back |

> **The AC flip-flop is the most common VGA bug.** If the core doesn't toggle it
> correctly, every other AC register write lands in the wrong slot.

### Sequencer index/data (0x3C4/0x3C5)

| # | Action | Expected | Notes |
|---|--------|----------|-------|
| 1 | OUT 0x3C4, 0x02 (map mask index) | select map mask register | |
| 2 | OUT 0x3C5, 0x0F | enable all 4 planes | |
| 3 | IN 0x3C5 | reads 0x0F | round-trip |

### Graphics controller index/data (0x3CE/0x3CF)

| # | Action | Expected | Notes |
|---|--------|----------|-------|
| 1 | OUT 0x3CE, 0x05 (graphics mode select) | | |
| 2 | OUT 0x3CF, 0x00 (write mode 0, read mode 0) | | |
| 3 | IN 0x3CF | reads 0x00 | round-trip |

### CRTC protect (index 0x11 bit 7)

| # | Action | Expected | Notes |
|---|--------|----------|-------|
| 1 | Read CRTC index 0x11 via 0x3D4/0x3D5 | bit 7 = protect bit | |
| 2 | If bit 7=1, writes to CRTC 0x00–0x07 are protected | vertical timing regs locked | |
| 3 | Clear bit 7, write CRTC 0x00 | write accepted | protect removed |

### DAC (0x3C8/0x3C9)

| # | Action | Expected | Notes |
|---|--------|----------|-------|
| 1 | OUT 0x3C8, 0x00 (write index) | start at color 0 | |
| 2 | OUT 0x3C9, 0x3F (R), 0x00 (G), 0x00 (B) | color 0 = bright red | 6-bit values |
| 3 | Auto-increment: next write to 0x3C9 | writes color 1 | index auto-incremented |
| 4 | OUT 0x3C7, 0x00; IN 0x3C9 x3 | reads R=0x3F, G=0x00, B=0x00 | read-back |

### Write mode 0–3 (graphics controller)

| # | Write mode | Behavior | Test | Notes |
|---|:----------:|----------|------|-------|
| 1 | 0 | direct CPU data, rotated, AND'd with bit mask | write byte, read back | default mode |
| 2 | 1 | CPU data not used; plane latches → VRAM | load latch via read, write | |
| 3 | 2 | CPU byte fills plane i with bit i value | fill with set/reset color | |
| 4 | 3 | set/reset + bit mask | combined set/reset + bitmask | |

### Read mode 0–1

| # | Read mode | Behavior | Test | Notes |
|---|:---------:|----------|------|-------|
| 1 | 0 | returns plane selected by read map select (GC reg 4) | select plane 0, read VRAM | |
| 2 | 1 | compares VRAM against color compare (GC reg 2) | set compare, read, bitmask | |

### Chain-4 (mode 13h)

| # | Action | Expected | Notes |
|---|--------|----------|-------|
| 1 | Set sequencer reg 4 bit 3 (chain-4 enable) | VRAM addressing changes | mode 13h |
| 2 | Write to VRAM at offset N | byte goes to plane (N&3) at offset (N>>2) | |

## Pre/Post State (representative cases)

### AC flip-flop — index/data toggle (signature test)
PRE:
  AC flip-flop = unknown
  AC register 0x10 = unknown
  AC register 0x11 = unknown
OP:  IN  AL, 0x3DA     ; reset flip-flop to index mode
     OUT 0x3C0, 0x10   ; write index 0x10 → flip-flop switches to data mode
     OUT 0x3C0, 0x01   ; write data → AC reg 0x10 = 0x01; flips back to index
     OUT 0x3C0, 0x11   ; write index 0x11 → flips to data
     OUT 0x3C0, 0x02   ; write data → AC reg 0x11 = 0x02; flips to index
     ; verify read-back:
     IN  AL, 0x3DA     ; reset flip-flop
     OUT 0x3C0, 0x10   ; select reg 0x10
     IN  AL, 0x3C1     ; read AC data
POST:
  AL = 0x01            ← AC reg 0x10 verified
  ← Each write to 0x3C0 toggles between index and data mode
  ← IN 0x3DA always resets to index mode

### Sequencer index/data round-trip
PRE:
  Sequencer index (0x3C4) = unknown
  Sequencer map mask (reg 2, 0x3C5) = unknown
OP:  OUT 0x3C4, 0x02   ; select map mask register
     OUT 0x3C5, 0x0F   ; enable all 4 planes
     IN  AL, 0x3C5     ; read back
POST:
  AL = 0x0F            ← all 4 bit planes enabled for writes

### DAC auto-increment write sequence
PRE:
  DAC write index = unknown
  DAC color 0 = unknown
OP:  OUT 0x3C8, 0x00   ; set write index to color 0
     OUT 0x3C9, 0x3F   ; R = 63 (max red)
     OUT 0x3C9, 0x00   ; G = 0
     OUT 0x3C9, 0x00   ; B = 0  → color 0 = bright red
     ; index auto-incremented to 1
     OUT 0x3C9, 0x00   ; R for color 1
     OUT 0x3C9, 0x3F   ; G for color 1
     OUT 0x3C9, 0x00   ; B for color 1 → color 1 = bright green
POST:
  DAC color 0 = (0x3F, 0x00, 0x00) = red
  DAC color 1 = (0x00, 0x3F, 0x00) = green
  ← After every 3rd write to 0x3C9, index increments

### DAC read-back
PRE:
  DAC color 0 = (0x3F, 0x00, 0x00) (from above)
OP:  OUT 0x3C7, 0x00   ; set read index to 0
     IN  AL, 0x3C9     ; read R
     IN  AH, 0x3C9     ; read G (auto-increment within color)
     IN  BL, 0x3C9     ; read B
POST:
  AL = 0x3F            ← R component
  AH = 0x00            ← G component
  BL = 0x00            ← B component
  ← Values are 6-bit (0-63); DAC masks to 0x3F

### CRTC protect bit (index 0x11 bit 7)
PRE:
  CRTC index 0x11 (read via 0x3D4/0x3D5) bit 7 = 1 (protected)
OP:  OUT 0x3D4, 0x00
     OUT 0x3D5, 0x7F   ; try to write CRTC reg 0 (horizontal total)
     IN  AL, 0x3D5     ; read back reg 0
POST:
  AL = original value  ← write was BLOCKED by protect bit

OP:  OUT 0x3D4, 0x11
     IN  AL, 0x3D5     ; read reg 0x11
     AND AL, 0x7F      ; clear protect bit 7
     OUT 0x3D5, AL     ; write back with protect cleared
     OUT 0x3D4, 0x00
     OUT 0x3D5, 0x7F   ; now try again
     IN  AL, 0x3D5
POST:
  AL = 0x7F            ← write succeeded (protect removed)

### Write mode 0 — direct CPU write with rotation
PRE:
  Graphics mode (GC reg 5) = 0x00 (write mode 0, read mode 0)
  Bit mask (GC reg 8) = 0xFF (all bits)
  VRAM at offset 0x0000 = 0x00 (all planes)
OP:  MOV byte [VRAM_SEG:0x0000], 0xFF
POST:
  VRAM at offset 0x0000 = 0xFF (all 4 planes get 0xFF)

### Chain-4 (mode 13h) memory layout
PRE:
  Sequencer reg 4 bit 3 = 1 (chain-4 enabled)
  VRAM cleared
OP:  MOV byte [VRAM_SEG:0x0000], 0x01  ; pixel 0
     MOV byte [VRAM_SEG:0x0001], 0x02  ; pixel 1
     MOV byte [VRAM_SEG:0x0002], 0x03  ; pixel 2
     MOV byte [VRAM_SEG:0x0003], 0x04  ; pixel 3
POST:
  Plane 0 offset 0x0000 = 0x01  ← pixel 0 (offset & 3 = 0)
  Plane 1 offset 0x0000 = 0x02  ← pixel 1 (offset & 3 = 1)
  Plane 2 offset 0x0000 = 0x03  ← pixel 2 (offset & 3 = 2)
  Plane 3 offset 0x0000 = 0x04  ← pixel 3 (offset & 3 = 3)
  ← In chain-4, CPU offset N → plane (N&3), VRAM offset (N>>2)

## State Save/Restore

- **Save:** all indexed registers (sequencer, graphics, CRTC, AC, DAC indices+data);
  AC flip-flop state; current video mode
- **Restore:** reprogram all registers; note that restoring the AC flip-flop requires
  an IN 0x3DA to reset it

## Pass/Fail Criteria

- **PASS:** AC flip-flop toggles; all index/data pairs round-trip; DAC auto-increment works;
  write/read modes behave correctly; CRTC protect works
- **FAIL:** flip-flop not tracked; index ignored; DAC wrong 6-bit truncation
- **SKIP:** never (VGA present on all PC targets)

## Known Divergences

- **Mono vs color ports:** mono uses 0x3B4/0x3B5/0x3BA for CRTC and input status;
  color uses 0x3D4/0x3D5/0x3DA. Test the color set (default).
- **Mode-X:** unchained planar mode (clear chain-4) allows interleaved plane access;
  separate test case.
- **DAC width:** standard VGA uses 6-bit DAC; some SVGA cards use 8-bit.
  VGA should always be 6-bit.
