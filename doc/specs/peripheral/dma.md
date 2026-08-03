# Spec: 8237 DMA (Direct Memory Access Controller)

## Metadata
- **Source file:** `src/peripheral/dma/dma.asm`
- **TIER:** HARDWARE | VENUE: G | GEN: 8086+ | ORACLE: manual
- **Impl-plan:** Phase 7, area `DMA`
- **Coverage:** [§9.3](../../coverage-matrix.md#93-8237-dma)
- **Detail:** [prep-analysis §6.3](../../prep-analysis.md#63-dma-8237--stateful-traps)
- **Refs:** [references.md](../../references.md) — Intel 8237A datasheet

## Purpose

Verify DMA controller programming: address/count registers, auto-init, terminal count,
mask register, mode (single/block/demand/cascade), address increment/decrement,
byte-pointer flip-flop, and page register address composition.

**Constraint:** scratch buffers only — no destructive real DMA transfers.

## Port Map

### DMA1 (8-bit, channels 0–3)

| Port | Register | Notes |
|------|----------|-------|
| 0x00–0x07 | CH0–3 base/current address | 16-bit (low byte / high byte via flip-flop) |
| 0x08 | Command register | |
| 0x09 | Request register | |
| 0x0A | Mask register (single bit) | |
| 0x0B | Mode register | |
| 0x0C | Flip-flop reset (byte pointer) | clear before address/count writes |
| 0x0D | Master clear / temp register | |
| 0x0E | Clear mask register | |
| 0x0F | Mask register (all 4 bits) | |
| 0x81–0x83 | Page register CH1–3 | high byte of 20-bit address |
| 0x87 | Page register CH0 | (AT mapping) |

### DMA2 (16-bit, channels 4–7, slave on master CH0 via cascade)

| Port | Register | Notes |
|------|----------|-------|
| 0xC0–0xC7 | CH4–7 base/current address | word-shifted: address << 1 |
| 0xD0 | Command register | |
| 0xD2 | Mode register | |
| 0xD4 | Flip-flop reset | |
| 0xD6 | Master clear | |
| 0xD8–0xDF | Page register CH5–7 | |

## Test Cases

### Flip-flop (byte pointer) reset

| # | Action | Expected | Notes |
|---|--------|----------|-------|
| 1 | OUT 0x0C, 0 (reset flip-flop) | next write to CH addr = LSB | |
| 2 | Write 0xFF to CH0 addr port (0x00) | flip-flop now points to MSB | |
| 3 | Write 0x3F to CH0 addr port (0x00) | full address = 0x3FFF | |
| 4 | OUT 0x0C again, then read CH0 addr | reads 0xFF (LSB first) | |

### Address/count write/read

| # | Channel | Write address | Write count | Read back | Notes |
|---|---------|:------------:|:-----------:|-----------|-------|
| 1 | CH1 | 0x0000 | 0x00FF | addr=0, count=0xFF | |
| 2 | CH2 | 0x3FFF | 0x0100 | addr=0x3FFF, count=0x100 | |

### Mask register

| # | Port | Value | Effect | Notes |
|---|------|:-----:|--------|-------|
| 1 | 0x0A | 0x05 | mask CH0 and CH2 (bits 0+2) | |
| 2 | 0x0A | 0x01 | mask CH0 only | |
| 3 | 0x0F | 0x0F | mask all channels (write-all) | |
| 4 | 0x0E | 0x00 | unmask all channels (clear-all) | |

### Mode register

| # | Channel | Mode value | Transfer mode | Auto-init | Increment | Notes |
|---|---------|:----------:|:------------:|:---------:|:---------:|-------|
| 1 | CH1 | 0x49 | single transfer | yes | increment | bit 4=auto-init, bit 5=0=incr |
| 2 | CH2 | 0x56 | block transfer | no | decrement | |
| 3 | CH3 | 0x07 | cascade mode | no | increment | |

### Terminal count (TC) and status

| # | Action | Expected | Notes |
|---|--------|----------|-------|
| 1 | Program CH1 count=0x0001, trigger DREQ1 | after 1 transfer, TC reached | EOP asserted |
| 2 | Read status register (port 0x08 on DMA1) | bit 1 set (TC for CH1) | |
| 3 | Read status again | TC bit may be cleared by read | TC status is read-clear on some impls |

### Auto-init reload

| # | Setup | Action | Expected | Notes |
|---|-------|--------|----------|-------|
| 1 | CH2, auto-init=1, base addr=0x1000, count=0x0010 | trigger DREQ2 x16 | after TC, reloads to 0x1000/count 0x10 | |
| 2 | CH2, auto-init=0 | trigger DREQ2 x16 | after TC, channel masked, no reload | |

### Page register

| # | Channel | Page port | Value | Composed address | Notes |
|---|---------|:---------:|:-----:|:----------------:|-------|
| 1 | CH1 | 0x83 | 0x01 | 0x10000 + offset | page << 16 |
| 2 | CH2 | 0x81 | 0x0F | 0xF0000 + offset | |

### 64K boundary

| # | Setup | Expected | Notes |
|---|-------|----------|-------|
| 1 | CH1 addr=0xFFF0, count=0x0020 | DMA cannot cross 64K page boundary | address wraps within page |

## Pre/Post State (representative cases)

### Flip-flop reset + address write — CH1
PRE:
  Byte-pointer flip-flop = unknown
  CH1 address = unknown
OP:  OUT 0x0C, 0x00    ; reset flip-flop → next write = LSB
     OUT 0x02, 0xFF    ; write CH1 address LSB
     OUT 0x02, 0x3F    ; write CH1 address MSB
POST:
  CH1 base address = 0x3FFF
  Flip-flop now = MSB (pointed to MSB after last write)

### Address read-back after flip-flop reset
PRE:
  CH1 address = 0x3FFF (from above)
  Flip-flop = MSB
OP:  OUT 0x0C, 0x00    ; reset flip-flop → next read = LSB
     IN  AL, 0x02      ; read CH1 address LSB
     IN  AL, 0x02      ; read CH1 address MSB
POST:
  AL (first read) = 0xFF   ← LSB
  AL (second read) = 0x3F  ← MSB
  Composed address = 0x3FFF

### Count write/read — CH2
PRE:
  CH2 count = unknown
  Flip-flop = unknown
OP:  OUT 0x0C, 0x00    ; reset flip-flop
     OUT 0x03, 0x00    ; CH2 count LSB
     OUT 0x03, 0x01    ; CH2 count MSB
POST:
  CH2 base count = 0x0100  (256 bytes to transfer)

### Mask register — mask CH0 and CH2
PRE:
  Mask register = 0x00   (all unmasked)
OP:  OUT 0x0A, 0x05     ; single-mask: bits 0+2 → CH0 and CH2 masked
POST:
  Mask register = 0x05  (CH0=masked, CH2=masked, CH1/3=unmasked)

### Mode register — CH1 single transfer, auto-init, increment
PRE:
  CH1 mode = unknown
OP:  OUT 0x0B, 0x49     ; mode: CH1, single xfer, auto-init, increment
POST:
  CH1: transfer = single, auto-init=1 (bit4), direction=increment (bit5=0)
  ← After terminal count, CH1 auto-reloads base address/count

### Page register — compose 20-bit address
PRE:
  CH1 address = 0x3FFF (16-bit DMA address)
  CH1 page register = unknown
OP:  OUT 0x83, 0x01     ; set page register for CH1
POST:
  CH1 page = 0x01
  Composed 20-bit physical address = (0x01 << 16) | 0x3FFF = 0x013FFF

### Terminal count (TC) detection
PRE:
  CH1: count=0x0001, auto-init=0, address=0x0000
  Status register (port 0x08) = 0x00
OP:  (trigger DREQ1 → DMA transfers 1 byte → count reaches 0)
POST:
  Status register = 0x02   (bit 1 set = TC reached for CH1)
  CH1 masked automatically (auto-init=0)
  ← Subsequent reads of status may clear TC bit (implementation-dependent)

## State Save/Restore

- **Save:** command register, mode registers (all channels), mask register, page registers,
  flip-flop state, base/current address+count for all channels
- **Restore:** master clear (0x0D), then reprogram all channels with saved values

## Timing Tolerances

| Operation | Expected | Tolerance | Notes |
|-----------|:--------:|:---------:|-------|
| Register write to read-back | immediate | — | no latency |
| DREQ assert to transfer start | 1-2 bus cycles | ±1 | depends on bus arbitration |
| TC flag set after last byte | immediate | — | visible on next status read |
| Auto-init reload | before next transfer | — | within same TC cycle |

> DMA cycle-steal timing is venue T (bench). Guest tests verify state, not cycles.

## Pass/Fail Criteria

- **PASS:** address/count round-trip; flip-flop toggles correctly; mask works;
  auto-init reloads; TC detected; page register composition correct
- **FAIL:** wrong address composition, no TC, auto-init broken, mask ignored
- **SKIP:** never (DMA present on all PC targets)

## Known Divergences

- **Status TC read-clear:** some implementations clear TC bits on status read, others
  require explicit reset. Test both and document.
- **16-bit DMA2 word shift:** DMA2 addresses are shifted left by 1 (word-addressed);
  the page register still maps to physical address bits 16–23.
