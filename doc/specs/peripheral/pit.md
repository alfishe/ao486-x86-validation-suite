# Spec: 8254 PIT (Programmable Interval Timer)

## Metadata
- **Source file:** `src/peripheral/pit/pit.asm`
- **TIER:** HARDWARE | VENUE: G | GEN: 8086+ | ORACLE: manual
- **Impl-plan:** Phase 7, area `PIT`
- **Coverage:** [§9.2](../../coverage-matrix.md#92-hard-cases--pit-8254)
- **Detail:** [prep-analysis §6](../../prep-analysis.md#6-peripheral-stateful-behavior), [§6.2a](../../prep-analysis.md#62a-pit-mode-specific-behavior-matrix)

## Purpose

Verify PIT mode programming, counter read/write, read-back command, BCD mode,
and mode-specific behavior (mode 0-5).

## Port Map

| Port | Channel | Notes |
|------|:-------:|-------|
| 0x40 | 0 | system timer (IRQ0) |
| 0x41 | 1 | refresh / DRAM |
| 0x42 | 2 | speaker |
| 0x43 | control word | mode programming |

## Test Cases

### Mode programming

| # | Port 0x43 value | Channel | Mode | Format | Notes |
|---|:---------------:|:-------:|:----:|:------:|-------|
| 1 | 0x36 | 0 | 3 (square wave) | lo/hi binary | typical IRQ0 setup |
| 2 | 0xB6 | 2 | 3 | lo/hi binary | speaker |

### Counter write/read

| # | Action | Expected | Notes |
|---|--------|----------|-------|
| 1 | Write 0x3FFF to channel 0 (lo/hi) | counter = 0x3FFF | |
| 2 | Read channel 0 (latch first) | reads back 0x3FFF (or less if counting) | |

### Read-back command

| # | Port 0x43 | Action | Notes |
|---|-----------|--------|-------|
| 1 | 0xE2 | latch status of channel 0 | |
| 2 | 0xD2 | latch count of channel 0 | |
| 3 | Read port 0x40 | returns latched value | |

### Mode-specific behavior

| # | Mode | Behavior | Test | Notes |
|---|------|----------|------|-------|
| 0 | Interrupt on terminal count | output goes high when count reaches 0 | |
| 1 | Hardware retriggerable one-shot | — | needs GATE trigger |
| 2 | Rate generator | output pulses at interval | N-1 counts high, 1 count low |
| 3 | Square wave | output toggles every N/2 | period = N |
| 4 | Software triggered strobe | output high, goes low for 1 count at terminal | |
| 5 | Hardware triggered strobe | — | needs GATE |

> See [prep-analysis §6.2a](../../prep-analysis.md#62a-pit-mode-specific-behavior-matrix)
> for mode-specific divergence details.

### BCD mode

| # | Control word bit 0 | Counting | Notes |
|---|:------------------:|----------|-------|
| 1 | 0 | binary (0-65535) | |
| 2 | 1 | BCD (0-9999) | |

## Pre/Post State (representative cases)

### Counter write/read — channel 0, mode 3 (square wave)
PRE:
  CH0 mode = unknown
  CH0 count = unknown
  Flip-flop state = unknown
OP:  OUT 0x43, 0x36   ; control: CH0, lo/hi, mode 3, binary
     OUT 0x40, 0xFF   ; LSB first
     OUT 0x40, 0x3F   ; MSB → count = 0x3FFF
POST:
  CH0 mode = 3 (square wave)
  CH0 format = binary
  CH0 count = 0x3FFF
  ← IRQ0 fires at rate = 1193182 / 0x3FFF ≈ 18.2 Hz

### Read-back — latch count and status
PRE:
  CH0 counting (mode 3, count = 0x3FFF, counting down)
  CH0 current value = unknown (in-flight)
OP:  OUT 0x43, 0xE2   ; read-back: latch status of CH0
     OUT 0x43, 0xD2   ; read-back: latch count of CH0
     IN  AL, 0x40     ; read latched count LSB
     IN  AL, 0x40     ; read latched count MSB
POST:
  AL (first read) = count LSB  (frozen at latch moment)
  AL (second read) = count MSB
  ← Count is snapshot of counter value at latch time, not current

### Mode 0 — interrupt on terminal count
PRE:
  CH1 mode = 0, count = 0x0005
  CH1 output pin = LOW
OP:  (wait 5 PIT clocks)
POST:
  CH1 count = 0x0000  (reached terminal count)
  CH1 output pin = HIGH  ← set on count=0
  ← Output stays HIGH until reprogrammed

### Mode 2 — rate generator
PRE:
  CH2 mode = 2, count = 0x0004
  CH2 output = HIGH
OP:  (after 3 counts)
  CH2 output = HIGH (still counting down: 4→3→2→1)
OP:  (after 1 more count — count reached 1)
  CH2 output = LOW for 1 count
POST:
  CH2 count reloaded to 0x0004  (period = N=4)
  CH2 output = HIGH again
  ← Mode 2 outputs LOW for 1 count out of every N

### BCD vs binary mode
PRE:
  CH0 mode word = 0x36 (binary, bit0=0)
OP:  OUT 0x43, 0x37   ; same but bit0=1 → BCD mode
     OUT 0x40, 0x99   ; write count
     OUT 0x40, 0x00   ; MSB
POST:
  CH0 count = BCD 99 (0x0099)  ← treated as 4-digit BCD, max 9999
  ← In binary mode, 0x0099 = 153 decimal

## Corner Cases — Count Latching While Counting

### Latch mid-count

| # | Action | Expected | Notes |
|---|--------|----------|-------|
| 1 | Latch while counting | frozen value returned | multiple reads return same value |
| 2 | Second latch before reading | new value latched | overwrites previous |
| 3 | Read without latch (mode 3) | first = LSB, second = MSB | may be inconsistent |

### Flip-flop state preservation

| # | Sequence | Expected | Notes |
|---|----------|----------|-------|
| 1 | Write LSB, write MSB | count loaded | normal |
| 2 | Write LSB, read MSB | undefined | flip-flop out of sync |
| 3 | Latch, read LSB, latch again | new LSB latched | flip-flop reset |

### Read during reload

| # | Condition | Expected | Notes |
|---|-----------|----------|-------|
| 1 | Read immediately after write | may get old count | reload delay |
| 2 | Latch during reload | captures correct value | atomic snapshot |

## Corner Cases — Mode-Specific

### Mode 0 — count values

| # | Count value | Effective count | Notes |
|---|:-----------:|:---------------:|-------|
| 1 | 0x0001 | 1 | minimum |
| 2 | 0x0000 | 65536 (0x10000) | 0 means 65536 |
| 3 | 0xFFFF | 65535 | maximum explicit |

### Mode 2 — rate generator edge cases

| # | Test | Expected | Notes |
|---|------|----------|-------|
| 1 | Count = 1 | undefined | minimum is 2 |
| 2 | Count = 2 | output LOW 1, HIGH 1 | 50% duty |
| 3 | Reprogram during count | glitch possible | |

### Mode 3 — square wave duty cycle

| # | Count | High cycles | Low cycles | Notes |
|---|:-----:|:-----------:|:----------:|-------|
| 1 | 10 | 5 | 5 | even count |
| 2 | 11 | 6 | 5 | odd: extra high cycle |
| 3 | 2 | 1 | 1 | minimum |

### Gate input effects (channels 1 and 2)

| Mode | Gate LOW | Gate rising edge | Notes |
|:----:|----------|------------------|-------|
| 0 | pause count | — | |
| 1 | — | restart count | hardware one-shot |
| 2 | output HIGH, stop | reload and continue | |
| 3 | output HIGH, stop | reload and continue | |
| 4 | pause | — | |
| 5 | — | start count | hardware strobe |

## Corner Cases — Status Byte

### Read-back status format

```
Bit 7: output pin state (1=high, 0=low)
Bit 6: null count (1=count not yet loaded)
Bits 4-5: read/write mode (00=latch, 01=LSB, 10=MSB, 11=LSB/MSB)
Bits 1-3: mode (0-5)
Bit 0: BCD (0=binary, 1=BCD)
```

| # | Test | Verify | Notes |
|---|------|--------|-------|
| 1 | Status bit 7 | matches output pin | gate-dependent |
| 2 | Status bit 6 | 1 after control, 0 after count write | null count flag |
| 3 | Status bits 1-3 | match programmed mode | |

## Corner Cases — BCD Mode

| # | BCD count | Decimal | Binary equiv | Notes |
|---|:---------:|:-------:|:------------:|-------|
| 1 | 0x0000 | 10000 | (wraps to 9999) | 0 = 10000 in BCD |
| 2 | 0x0001 | 1 | 1 | |
| 3 | 0x9999 | 9999 | 9999 | max BCD |
| 4 | 0x1234 | 1234 | 1234 | |

### Invalid BCD digits

| # | Value | Expected | Notes |
|---|:-----:|----------|-------|
| 1 | 0x000A | undefined | A not valid BCD |
| 2 | 0x00F0 | undefined | F not valid BCD |

## Pre/Post State — Additional Cases

### Latch then multiple reads

```
PRE:
  CH0 counting, current = 0x1234
OP:  OUT 0x43, 0x00   ; latch CH0 (control: SC=00, RW=00)
     IN  AL, 0x40     ; read LSB
     IN  AH, 0x40     ; read MSB
     IN  BL, 0x40     ; read again → new unlatched value (if counting)
POST:
  AL = 0x34           ; latched LSB
  AH = 0x12           ; latched MSB
  BL = (new value)    ; latch cleared, live read
```

### Read-back both status and count

```
PRE:
  CH0 mode 3, count = 0x5678, output HIGH
OP:  OUT 0x43, 0xC2   ; read-back: latch status AND count
     IN  AL, 0x40     ; first read = status
     IN  AH, 0x40     ; second = count LSB
     IN  BL, 0x40     ; third = count MSB
POST:
  AL bit 7 = 1        ; output HIGH
  AL bits 1-3 = 3     ; mode 3
  AH = 0x78           ; count LSB
  BL = 0x56           ; count MSB
```

### Mode change while counting

```
PRE:
  CH0 mode 2, count = 0x1000, actively counting
OP:  OUT 0x43, 0x36   ; switch to mode 3
     OUT 0x40, 0xFF
     OUT 0x40, 0xFF   ; new count
POST:
  CH0 mode = 3        ; immediately changed
  CH0 count = 0xFFFF  ; new count loaded
  Output may glitch during transition
```

## State Save/Restore

- **Save:** all 3 channel mode words + counts + flip-flop states
- **Restore:** reprogram all channels with saved config; restore GATE states if possible

## Known Divergences

| Behavior | Real 8254 | Emulators |
|----------|-----------|-----------|
| Read without latch | may be inconsistent | often stable |
| Gate timing | precise | may be approximated |
| BCD invalid digits | undefined | may treat as binary |

## Pass/Fail Criteria

- **PASS:** counter accepts value; read-back works; modes behave correctly; latch freezes value
- **FAIL:** wrong read-back, mode output, or latch behavior
- **SKIP:** never (PIT always present)

## NOT TESTED (deferred)

- Exact cycle timing of count transitions (→T)
- GATE input timing with external trigger (→T)
- ISA bus timing during port access (→T)
