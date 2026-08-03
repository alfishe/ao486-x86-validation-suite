# Spec: Sound (PC Speaker / OPL2 / Sound Blaster)

## Metadata
- **Source file:** `src/peripheral/sound/sound.asm`
- **TIER:** HARDWARE | VENUE: G | GEN: 8086+ | ORACLE: manual
- **Impl-plan:** Phase 7, area `Sound`
- **Coverage:** [§9](../../coverage-matrix.md#9-peripherals-pri-12--the-projects-least-duplicated-coverage)
- **Detail:** [prep-analysis §6](../../prep-analysis.md#6-peripheral-stateful-behavior)
- **Refs:** [references.md](../../references.md) — AdLib/OPL2 datasheet; SB16 HW Ref

## Purpose

Verify the three sound subsystems present on ao486: PC speaker gate, AdLib/OPL2 FM
synthesis register R/W + timer status, and Sound Blaster DSP reset handshake / version.

**Scope note:** GUS, MPU-401, and LPT are **not confirmed** as ao486 peripherals
and are deferred (see coverage-matrix peripheral scope note).

## Subsystems

### 1. PC Speaker (port 0x61)

| Port | Bits | Purpose |
|------|------|---------|
| 0x61 | bit 0 | timer 2 gate enable (speaker on/off) |
| 0x61 | bit 1 | speaker enable (gate output to speaker) |

| # | Action | Expected | Notes |
|---|--------|----------|-------|
| 1 | Read 0x61 | bits 0–1 = current speaker config | save for restore |
| 2 | OR 0x03 to 0x61 | speaker on (timer 2 gated to output) | |
| 3 | AND ~0x03 to 0x61 | speaker off | |

> **Prerequisite:** PIT channel 2 must be programmed with a mode + count for
> tone generation. See [pit.md](pit.md).

### 2. AdLib / OPL2 (ports 0x388/0x389)

| Port | Register | Notes |
|------|----------|-------|
| 0x388 | Address (index) | selects OPL2 register |
| 0x389 | Data | writes to selected register |

| # | Action | Expected | Notes |
|---|--------|----------|-------|
| 1 | OUT 0x388, 0x01 (test register) | wait 3.3µs | OPL2 requires address settle |
| 2 | OUT 0x389, 0x60 | write test value | wait 23µs after data write |
| 3 | OUT 0x388, 0x04 (timer 1 control) | select timer 1 | |
| 4 | OUT 0x389, 0x80 | start timer 1 (bit 2 = mask, bit 0 = start) | |
| 5 | Wait ~80µs | timer 1 overflows | |
| 6 | OUT 0x388, 0x04; IN 0x389 | bit 6 = timer 1 overflow flag set | status read |
| 7 | OUT 0x389, 0x60 (reset timers) | flags cleared | |

> **OPL2 detection pattern:** the classic AdLib detection writes 0x60 to register
> 0x01 (waveform select enable), starts timer 1, waits, reads status to verify
> bit 6 toggles. If it doesn't, no OPL2 present → SKIP.

### 3. Sound Blaster DSP (ports 0x220–0x22F)

| Port | Register | Notes |
|------|----------|-------|
| 0x226 | Reset (W) | write 1 then 0 with delay |
| 0x22E | Read data (R) | read DSP response |
| 0x22C | Write command/data (W) | poll bit 7 first |
| 0x22E | Read-buffer status (R) | bit 7 = data available |

#### DSP reset handshake

| # | Action | Expected | Notes |
|---|--------|----------|-------|
| 1 | OUT 0x226, 0x01 | assert reset | |
| 2 | Wait ~3µs | | |
| 3 | OUT 0x226, 0x00 | deassert reset | |
| 4 | Poll 0x22E bit 7 until 1 | data ready | timeout ≤ 100µs |
| 5 | IN 0x22A | 0xAA = reset success | DSP ready |

#### DSP version

| # | Action | Expected | Notes |
|---|--------|----------|-------|
| 1 | OUT 0x22C, 0xE1 (get version) | DSP responds | |
| 2 | Poll + read 0x22A | major version byte | e.g. 0x04 for SB 4.x |
| 3 | Poll + read 0x22A | minor version byte | e.g. 0x05 for SB 4.5 |

## Pre/Post State (representative cases)

### PC Speaker gate toggle (port 0x61)
PRE:
  Port 0x61 = 0x00   (speaker off, timer 2 gate off)
  PIT CH2 programmed: mode 3, count = 0x533 (≈ 1kHz tone)
OP:  IN  AL, 0x61     ; save current value
     OR  AL, 0x03     ; set bit 0 (timer 2 gate) + bit 1 (speaker enable)
     OUT 0x61, AL
POST:
  Port 0x61 = 0x03   (bits 0+1 set)
  Timer 2 output gated to speaker → audible tone
  ← PIT CH2 must be programmed first or no tone generated

OP:  IN  AL, 0x61
     AND AL, 0xFC     ; clear bits 0+1
     OUT 0x61, AL
POST:
  Port 0x61 = 0x00   (speaker off)

### OPL2 timer 1 overflow detection
PRE:
  OPL2 status (port 0x389 after 0x388=0x04) = 0x00
  OPL2 register 0x01 (test) = unknown
OP:  OUT 0x388, 0x01   ; select test register
     OUT 0x389, 0x60   ; write test register
     OUT 0x388, 0x04   ; select timer 1 control
     OUT 0x389, 0x80   ; mask timer 1 (bit 2=1), start (bit 0=1... wait)
     ; Actually: bit 2 = mask timer 1 IRQ, bit 1 = mask timer 2, bit 0 = start T1
     OUT 0x389, 0x81   ; start timer 1, mask IRQ (bit 0=1 start, bit 2=1 mask)
     ; wait ~80µs for timer overflow
     OUT 0x388, 0x04   ; select timer control for status read
     IN  AL, 0x389     ; read status
POST:
  AL bit 6 = 1        ← timer 1 overflow flag set
  AL = 0x40 or 0xC0   (bit 6 set; bit 7 may be RST# status)
  ← If bit 6 never sets → OPL2 not present → SKIP

OP:  OUT 0x388, 0x04
     OUT 0x389, 0x60   ; reset timers
     OUT 0x388, 0x04
     IN  AL, 0x389
POST:
  AL = 0x00           ← timer flags cleared

### Sound Blaster DSP reset handshake
PRE:
  DSP state = unknown (cold)
  Port 0x22E bit 7 = unknown
OP:  OUT 0x226, 0x01   ; assert reset
     ; wait ~3µs
     OUT 0x226, 0x00   ; deassert reset
     ; poll 0x22E bit 7 until 1 (with ~100µs timeout)
     IN  AL, 0x22A     ; read DSP response
POST:
  AL = 0xAA           ← DSP reset successful
  ← If timeout or AL != 0xAA → no Sound Blaster → SKIP

### DSP version read
PRE:
  DSP reset complete (0xAA received)
  AL = unknown
OP:  OUT 0x22C, 0xE1   ; get DSP version command
     ; poll 0x22E bit 7 until 1
     IN  AL, 0x22A     ; read major version
     ; poll 0x22E bit 7 until 1
     IN  AH, 0x22A     ; read minor version
POST:
  AX = version word, e.g., 0x0405 = SB 4.5
  ← Version determines feature set (DSP 4.x = SB16 capabilities)

## State Save/Restore

- **Speaker:** save/restore port 0x61 bits 0–1
- **OPL2:** save/restore all relevant OPL2 registers (or just skip if not critical);
  always reset timers on exit
- **SB DSP:** no persistent state to save beyond reset; ensure DSP is in idle state

## Pass/Fail Criteria

- **PASS:** speaker gate toggles; OPL2 timer status read-back works; SB DSP reset
  returns 0xAA; version read works
- **FAIL:** OPL2 not detected; DSP reset fails; timer overflow flag missing
- **SKIP:** if hardware not present (OPL2 detect fails; SB reset timeout)

## Known Divergences

- **OPL2 vs OPL3:** OPL3 detection via the 4-op enable register. OPL3 is present
  on SB16 and later. Reduced-priority test.
- **SB base address:** typically 0x220, but some systems use 0x240. Detect via reset.
- **Delay timing:** OPL2 register settle (3.3µs addr / 23µs data) and DSP reset
  (3µs) must be respected; use PIT or calibrated delay loop.
