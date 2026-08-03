# Spec: 8042 KBC (Keyboard Controller)

## Metadata
- **Source file:** `src/peripheral/kbc/kbc.asm`
- **TIER:** HARDWARE | VENUE: G | GEN: 8086+ | ORACLE: manual
- **Impl-plan:** Phase 7, area `KBC`
- **Coverage:** [§9.4](../../coverage-matrix.md#94-8042-kbc)
- **Detail:** [prep-analysis §6.5](../../prep-analysis.md#65-kbc-rtc-serial--abbreviated)
- **Refs:** [references.md](../../references.md) — Intel 8042 datasheet; IBM AT Tech Ref

## Purpose

Verify 8042 keyboard controller: command/data sequencing (IBF/OBF), self-test,
A20 control via output port, controller command byte readback, and the
command/data port protocol at 0x60/0x64.

## Port Map

| Port | Register | Direction | Notes |
|------|----------|-----------|-------|
| 0x60 | Data register (I/O buffer) | R/W | read = output buffer; write = input buffer |
| 0x64 | Status (read) / Command (write) | R/W | read = status; write = command byte |

### Status register (port 0x64 read)

| Bit | Name | Meaning |
|:---:|------|---------|
| 0 | OBF | output buffer full (data available at 0x60) |
| 1 | IBF | input buffer full (cannot write yet) |
| 2 | SYS | system flag (set after power-on reset) |
| 3 | A2 | command/data: 0=last write was to 0x60, 1=to 0x64 |
| 4 | INH | inhibit flag (keyboard inhibited) |
| 5 | A2b | aux output buffer full (mouse data available) |
| 6 | Timeout | set if timeout on transmission |
| 7 | Parity | set on parity error from keyboard |

## Test Cases

### Status register readback

| # | Action | Expected | Notes |
|---|--------|----------|-------|
| 1 | Read 0x64 (status) | bit 2 (SYS) should be 1 | set after POST |
| 2 | Poll bit 1 (IBF) until clear | IBF=0 means write accepted | must timeout |
| 3 | Poll bit 0 (OBF) until set | OBF=1 means data available at 0x60 | must timeout |

### Controller command byte readback

| # | Action | Expected | Notes |
|---|--------|----------|-------|
| 1 | OUT 0x64, 0x20 (read command byte) | wait for OBF, then read 0x60 | command byte returned |
| 2 | Verify command byte bits | bit 0=INT (scan code IRQ1), bit 1=mouse INT12 | check enabled bits |
| 3 | OUT 0x64, 0x60 (write command byte); write new byte to 0x60 | read back via cmd 0x20 | round-trip |

### Self-test (0xAA)

| # | Action | Expected | Notes |
|---|--------|----------|-------|
| 1 | OUT 0x64, 0xAA (self-test) | wait for OBF | |
| 2 | Read 0x60 | 0x55 = passed | 0xFC or 0xFD = failed |

### Output port and A20 control

| # | Action | Expected | Notes |
|---|--------|----------|-------|
| 1 | OUT 0x64, 0xD0 (read output port) | wait OBF, read 0x60 | bit 1 = A20 enable state |
| 2 | OUT 0x64, 0xD1 (write output port); write byte to 0x60 | sets output port incl. A20 bit | |

> **A20 detailed testing:** see [a20.md](../system/a20.md) for KBC-based
> A20 gate toggle and 1MB wrap verification.

### Interface test (0xAB)

| # | Action | Expected | Notes |
|---|--------|----------|-------|
| 1 | OUT 0x64, 0xAB | wait OBF | |
| 2 | Read 0x60 | 0x00 = no error | 0x01–0x03 = various failures |

### Input buffer full (IBF) write synchronization

| # | Action | Expected | Notes |
|---|--------|----------|-------|
| 1 | Write to 0x64 while IBF=1 | must wait (poll IBF until 0) | write may be lost if IBF=1 |

## Pre/Post State (representative cases)

### Status register readback
PRE:
  KBC status (port 0x64) = unknown
OP:  IN AL, 0x64        (read status register)
POST:
  AL = status byte, e.g., 0x1C
    bit 2 (SYS) = 1  ← system flag set after POST
    bit 3 (A2)  = 1  ← last write was to 0x64
    bit 4 (INH) = 1  ← keyboard inhibited
    OBF = 0, IBF = 0  ← no pending data/buffer

### Self-test (0xAA)
PRE:
  KBC status: IBF=0 (ready for command)
OP:  OUT 0x64, 0xAA     (issue self-test command)
     (poll 0x64 bit 0 (OBF) until set, with timeout)
     IN AL, 0x60        (read result)
POST:
  AL = 0x55            ← self-test passed
  (If AL = 0xFC/0xFD → self-test failed)

### Command byte readback via 0x20
PRE:
  KBC command byte = unknown
OP:  OUT 0x64, 0x20     (read command byte)
     (poll OBF)
     IN AL, 0x60        (read command byte)
POST:
  AL = command byte, e.g., 0x45
    bit 0 (INT1)  = 1  ← keyboard IRQ1 enabled
    bit 1 (INT12) = 0  ← mouse IRQ12 disabled
    bit 2 (SYS)   = 1  ← system flag
    bit 6 (XLATE) = 1  ← scan code translation enabled

### Command byte write via 0x60
PRE:
  Current command byte = 0x45 (read above)
  Desired command byte = 0x47  (enable mouse IRQ12)
OP:  OUT 0x64, 0x60     (write command byte)
     (poll IBF until clear)
     OUT 0x60, 0x47     (write new command byte)
     OUT 0x64, 0x20     (read back to verify)
     (poll OBF)
     IN AL, 0x60
POST:
  AL = 0x47            ← command byte updated successfully

### Output port read (A20 bit) via 0xD0
PRE:
  KBC output port = unknown
  A20 gate state = unknown
OP:  OUT 0x64, 0xD0     (read output port)
     (poll OBF)
     IN AL, 0x60        (read output port byte)
POST:
  AL = output port, e.g., 0x5D
    bit 0 = system reset line
    bit 1 = A20 gate    ← 1=A20 enabled, 0=A20 disabled
    bit 2 = mouse data output
    bit 3 = mouse clock
    bit 4 = keyboard IRQ1 output
    bit 5 = keyboard clock output
    bit 6 = keyboard data output
    bit 7 = keyboard clock

### Output port write — enable A20 via 0xD1
PRE:
  Output port = 0x5D (bit 1 = 1, A20 already enabled)
  Desired: disable A20 (bit 1 = 0)
OP:  OUT 0x64, 0xD1     (write output port command)
     (poll IBF until clear)
     OUT 0x60, 0xDD     (bit 1 = 0 → A20 disabled; 0xDD = 11011101b)
POST:
  Output port = 0xDD
  A20 gate = disabled   ← bit 1 cleared
  ← Memory accesses above 1MB now wrap (real-mode 8086 behavior)

## State Save/Restore

- **Save:** command byte (read via 0x20), output port (read via 0xD0)
- **Restore:** write command byte via 0x60, write output port via 0xD1
- **Note:** cannot save/restore keyboard LEDs or scan code state from software easily;
  only restore the controller-level configuration

## Timing Tolerances

| Operation | Expected | Tolerance | Poll timeout |
|-----------|:--------:|:---------:|:------------:|
| IBF clear after write | < 50µs | — | 1ms max |
| OBF set after command | varies | — | 20ms max |
| Self-test (0xAA) response | ~400ms | ±200ms | 1s max |
| A20 gate toggle effect | immediate | — | verify on next access |

> Poll IBF/OBF with timeout; never spin indefinitely. Self-test timeout is generous
> because some KBC implementations are slow.

## Pass/Fail Criteria

- **PASS:** status reads correctly; self-test returns 0x55; command byte round-trips;
  output port read/write works; A20 bit accessible
- **FAIL:** self-test fails; IBF/OBF broken; command byte not returned
- **SKIP:** never (KBC present on all AT-class PC targets)

## Known Divergences

- **OBF timing:** on real hardware, OBF set/clear timing varies. Use timeout-poll.
- **Mouse mux:** bit 5 (aux OBF) behavior depends on AT vs PS/2 controller;
  ao486 may not fully implement the mouse path.
