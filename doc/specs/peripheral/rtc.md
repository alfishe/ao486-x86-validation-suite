# Spec: MC146818 RTC/CMOS

## Metadata
- **Source file:** `src/peripheral/rtc/rtc.asm`
- **TIER:** HARDWARE | VENUE: G | GEN: 8086+ | ORACLE: manual
- **Impl-plan:** Phase 7, area `RTC`
- **Coverage:** [§9.5](../../coverage-matrix.md#95-mc146818-rtc)
- **Detail:** [prep-analysis §6.5](../../prep-analysis.md#65-kbc-rtc-serial--abbreviated)
- **Refs:** [references.md](../../references.md) — Motorola MC146818A datasheet

## Purpose

Verify RTC/CMOS: register read/write, BCD vs binary mode, UIP (update-in-progress),
alarm with don't-care bytes, periodic/alarm/update interrupt flags in Status C
(read-clear), and NMI gating via port 0x70 bit 7.

**Constraint:** non-destructive — save/restore all registers touched.

## Port Map

| Port | Register | Direction | Notes |
|------|----------|-----------|-------|
| 0x70 | Address register + NMI gate | W | bit 7 = NMI disable; bits 0–6 = index |
| 0x71 | Data register | R/W | read/write the indexed register |

### Register Map

| Index | Register | Notes |
|:-----:|----------|-------|
| 0x00 | Seconds (BCD: 0x00–0x59) | |
| 0x01 | Seconds alarm | 0xC0 = don't-care |
| 0x02 | Minutes (BCD: 0x00–0x59) | |
| 0x03 | Minutes alarm | 0xC0 = don't-care |
| 0x04 | Hours (BCD: 0x00–0x23 or 0x01–0x12 + PM) | |
| 0x05 | Hours alarm | 0xC0 = don't-care |
| 0x06 | Day of week (1=Sunday) | |
| 0x07 | Day of month (BCD) | |
| 0x08 | Month (BCD) | |
| 0x09 | Year (BCD: 0x00–0x99) | |
| 0x0A | Status A | UIP, divider, rate |
| 0x0B | Status B | DM (binary/BCD), 24h, PIE/AIE/UIE |
| 0x0C | Status C | IRQF, PF, AF, UF (read-clear) |
| 0x0D | Status D | VRT (valid RAM/time) |
| 0x0E–0x3F | Extended/century/storage | 0x32 = century byte (AT) |

## Test Cases

### Register read/write

| # | Index | Write | Read back | Notes |
|---|:-----:|:-----:|-----------|-------|
| 1 | 0x07 (day) | 0x15 | 0x15 | BCD day of month |
| 2 | 0x32 (century) | 0x19 | 0x19 | century byte (if present) |
| 3 | 0x0F (shutdown byte) | 0xAA | 0xAA | scratch RAM byte |

### NMI gating (port 0x70 bit 7)

| # | Action | Expected | Notes |
|---|--------|----------|-------|
| 1 | OUT 0x70, 0x8F (bit 7=1, index 0x0F) | NMI disabled | |
| 2 | OUT 0x70, 0x0F (bit 7=0, index 0x0F) | NMI enabled | |

### UIP (update-in-progress)

| # | Action | Expected | Notes |
|---|--------|----------|-------|
| 1 | Read Status A (0x0A) bit 7 | UIP bit: 1=update cycle in progress | |
| 2 | Loop reading UIP until 0, then read time | time registers stable | don't read during update |
| 3 | Read UIP; if 1, wait; re-read; loop ≤ 3 times | eventually UIP=0 | must not hang |

### BCD vs binary mode (Status B bit 2)

| # | Status B DM | Time format | Example: hour 17 | Notes |
|---|:-----------:|:-----------:|:----------------:|-------|
| 1 | 0 | BCD | 0x17 | default |
| 2 | 1 | binary | 0x11 (17 decimal) | |

> Toggle DM, write a time value, read back, verify format matches DM setting.
> **Always restore DM to original value** to avoid corrupting BIOS expectations.

### 12/24-hour mode (Status B bit 1)

| # | Status B 24h | Hour format | Example: 3 PM | Notes |
|---|:------------:|:-----------:|:-------------:|-------|
| 1 | 1 | 24-hour | 0x15 (BCD) | default |
| 2 | 0 | 12-hour | 0x83 (BCD + bit 7 PM) | bit 7 = PM flag |

### Alarm don't-care bytes

| # | Setup | Expected | Notes |
|---|-------|----------|-------|
| 1 | Write 0xC0 to seconds alarm (0x01) | seconds alarm = don't-care | triggers every second |
| 2 | Write 0xC0 to all 3 alarm regs | alarm fires every second | |

### Status C read-clear

| # | Action | Expected | Notes |
|---|--------|----------|-------|
| 1 | Enable PIE (Status B bit 6=1) | periodic interrupt flag set | |
| 2 | Read Status C (0x0C) | bits reflect PF/AF/UF | |
| 3 | Read Status C again | bits cleared (read-clear) | second read = 0x00 |

## Pre/Post State (representative cases)

### Register read/write — day of month
PRE:
  RTC index 0x07 (day) = unknown
  NMI gate = unknown
OP:  OUT 0x70, 0x07    ; select index 0x07 (day), bit7=0 (NMI enabled)
     OUT 0x71, 0x15    ; write BCD day = 15
     OUT 0x70, 0x07    ; re-select for read
     IN  AL, 0x71      ; read back
POST:
  AL = 0x15            ← BCD day = 15th
  RTC register 0x07 = 0x15

### NMI gating — disable via port 0x70 bit 7
PRE:
  NMI enabled (port 0x70 writes with bit7=0)
OP:  OUT 0x70, 0x8F    ; bit7=1 → NMI disabled, index=0x0F
POST:
  NMI = disabled
  RTC index selected = 0x0F (shutdown/scratch byte)
  ← NMI stays disabled until a write with bit7=0

### BCD vs binary mode — Status B bit 2 (DM)
PRE:
  Status B (index 0x0B) = 0x02   (DM=0 BCD, 24h=1)
  Hours register (index 0x04) = 0x17 (BCD: 17 = 5 PM)
OP:  (save Status B first)
     OUT 0x70, 0x0B
     IN  AL, 0x71       ; read Status B = 0x02
     OUT 0x70, 0x0B
     OUT 0x71, 0x06     ; set DM=1 (binary), 24h=1
     OUT 0x70, 0x04
     IN  AL, 0x71       ; read hours
POST:
  AL = 0x11            ← binary mode: 17 decimal = 0x11
  ← In BCD mode same time would read as 0x17
  ← MUST restore Status B DM bit afterward!

### Status C read-clear
PRE:
  Status B = 0x40   (PIE=1 bit6 → periodic interrupt enabled)
  Status C (index 0x0C) = PF flag set (bit 6) after periodic tick
OP:  OUT 0x70, 0x0C
     IN  AL, 0x71      ; first read
POST:
  AL = 0x40            ← PF bit set (periodic interrupt flag)
OP:  OUT 0x70, 0x0C
     IN  AL, 0x71      ; second read
POST:
  AL = 0x00            ← all flags cleared by first read

### Alarm don't-care byte
PRE:
  Seconds alarm (index 0x01) = 0x00
OP:  OUT 0x70, 0x01
     OUT 0x71, 0xC0     ; 0xC0 = don't-care for seconds
POST:
  Seconds alarm = don't-care (match any second)
  ← If all 3 alarm bytes = 0xC0, alarm fires every second

### VRT bit — Status D
PRE:
  Status D (index 0x0D) = unknown
OP:  OUT 0x70, 0x0D
     IN  AL, 0x71
POST:
  AL bit 7 = 1         ← VRT set = battery good, CMOS valid
  (If bit 7 = 0 → battery dead, CMOS contents unreliable)

## State Save/Restore

- **Save:** Status B (control), all alarm bytes, Status A divider/rate, any scratch bytes used
- **Restore:** write back Status B (including DM, 24h, PIE/AIE/UIE), restore alarm bytes,
  restore scratch bytes
- **NMI:** restore original NMI gate state (port 0x70 bit 7)

## Pass/Fail Criteria

- **PASS:** registers round-trip; UIP readable; BCD/binary mode toggles correctly;
  Status C read-clear works; NMI gate toggles
- **FAIL:** write doesn't persist; UIP never set; Status C doesn't clear
- **SKIP:** never (RTC present on all AT-class PC targets)

## Corner Cases — UIP Timing

### Update cycle duration

| # | Test | Expected | Notes |
|---|------|----------|-------|
| 1 | Measure UIP=1 duration | ~2ms typical | varies by implementation |
| 2 | UIP=1 to UIP=0 transition | within 1 second | poll with timeout |
| 3 | Time between updates | 1 second | one update per second |

### Safe read window

| # | Action | Expected | Notes |
|---|--------|----------|-------|
| 1 | Read UIP, wait if 1, then read time within 244µs | time stable | valid after UIP→0 |
| 2 | Read time while UIP=1 | may get partial update | undefined mid-update |

### UIP polling algorithm

```nasm
read_time_safe:
    mov al, 0x0A
    out 0x70, al
.wait_uip:
    in al, 0x71
    test al, 0x80       ; UIP bit
    jnz .wait_uip       ; wait if UIP=1
    
    ; Now read time registers quickly (within 244µs)
    mov al, 0x00        ; seconds
    out 0x70, al
    in al, 0x71
    ; ... continue reading
```

## Corner Cases — BCD/Binary Conversion

### BCD format values

| Register | BCD range | Binary range |
|----------|:---------:|:------------:|
| Seconds | 0x00-0x59 | 0x00-0x3B |
| Minutes | 0x00-0x59 | 0x00-0x3B |
| Hours (24h) | 0x00-0x23 | 0x00-0x17 |
| Day | 0x01-0x31 | 0x01-0x1F |
| Month | 0x01-0x12 | 0x01-0x0C |
| Year | 0x00-0x99 | 0x00-0x63 |

### Mode switch during operation

| # | Test | Expected | Notes |
|---|------|----------|-------|
| 1 | Change DM bit while running | time continues | value interpretation changes |
| 2 | Read time, change DM, read again | different representation | same actual time |

## Corner Cases — Alarm System

### Alarm match conditions

| # | Seconds alarm | Minutes alarm | Hours alarm | Match frequency |
|---|:-------------:|:-------------:|:-----------:|:---------------:|
| 1 | 0x30 | 0x15 | 0x10 | once per day at 10:15:30 |
| 2 | 0xC0 | 0x15 | 0x10 | every second while 10:15 |
| 3 | 0xC0 | 0xC0 | 0x10 | every second while hour 10 |
| 4 | 0xC0 | 0xC0 | 0xC0 | every second (always match) |

### Alarm interrupt generation

| # | Action | Status B | Status C | IRQ8 |
|---|--------|:--------:|:--------:|:----:|
| 1 | Time matches alarm | AIE=1 | AF=1, IRQF=1 | yes |
| 2 | Time matches alarm | AIE=0 | AF=1, IRQF=0 | no |
| 3 | Read Status C | — | all flags cleared | — |

## Corner Cases — Periodic Interrupt

### Rate selection (Status A bits 3-0)

| RS value | Rate (Hz) | Period (ms) | Notes |
|:--------:|:---------:|:-----------:|-------|
| 0x00 | none | — | disabled |
| 0x01 | 256 | 3.906 | |
| 0x02 | 128 | 7.813 | |
| 0x03 | 8192 | 0.122 | fastest |
| 0x06 | 1024 | 0.977 | default |
| 0x0F | 2 | 500 | slowest |

### Periodic interrupt timing

| # | Test | Expected | Notes |
|---|------|----------|-------|
| 1 | Enable PIE, measure PF intervals | matches RS rate | |
| 2 | Change RS while running | new rate takes effect | may glitch |
| 3 | Read Status C clears PF | next interval sets PF again | |

## Corner Cases — Divider Chain

### Status A divider bits (6-4)

| DV value | Behavior | Notes |
|:--------:|----------|-------|
| 010 | normal operation | 32.768kHz crystal |
| 11x | reset divider | time stops updating |
| 0xx | unused | |

### Divider reset sequence

```
1. Set DV=11x to reset divider
2. Time registers frozen
3. Set DV=010 to resume
4. Update cycle resumes from reset state
```

## Pre/Post State — Additional Cases

### UIP polling

```
PRE:
  RTC updating (UIP may be set)
OP:  Loop:
       OUT 0x70, 0x0A
       IN  AL, 0x71
       TEST AL, 0x80
       JNZ Loop           ; wait while UIP=1
     OUT 0x70, 0x00       ; read seconds
     IN  AL, 0x71
POST:
  AL = valid seconds value (not mid-update)
  Timeout: if loop exceeds ~2s, fail
```

### Alarm with don't-care

```
PRE:
  Time = 10:15:30
  Alarm bytes = 0xC0, 0xC0, 0xC0 (all don't-care)
  Status B = AIE=1 (alarm interrupt enabled)
OP:  Wait for next second boundary
POST:
  Status C = AF=1 (alarm flag set)
  ← Alarm fires every second with all don't-care
```

### Periodic interrupt rate change

```
PRE:
  Status A = 0x26 (RS=0110 → 1024 Hz)
  PIE = 1
OP:  OUT 0x70, 0x0A
     OUT 0x71, 0x2F       ; RS=1111 → 2 Hz
POST:
  Periodic interrupt now fires at 2 Hz
  ← Change takes effect on next tick
```

## Known Divergences

- **Century byte location:** 0x32 on most AT boards; some use 0x37 or 0x3A.
  Read at test time and report, do not assume.
- **UIP timing:** update cycle period varies by implementation; poll, don't assume.
- **VRT bit (Status D bit 7):** should be 1 (battery good); a 0 means dead battery.
- **Rate accuracy:** depends on crystal; may drift from nominal.
- **CMOS extended RAM:** 0x0E-0x3F layout varies by BIOS vendor.

## NOT TESTED (deferred)

- Exact crystal frequency accuracy (→T)
- Battery backup during power loss (→ physical test)
- Century rollover (1999→2000) logic (→ date-specific test)
