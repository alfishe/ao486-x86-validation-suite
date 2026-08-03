# Spec: 8250/16550 UART (Serial Port)

## Metadata
- **Source file:** `src/peripheral/serial/serial.asm`
- **TIER:** HARDWARE | VENUE: G | GEN: 8086+ | ORACLE: manual
- **Impl-plan:** Phase 7, area `UART`
- **Coverage:** [§9.8](../../coverage-matrix.md#98-uart-825016550)
- **Detail:** [prep-analysis §6.5](../../prep-analysis.md#65-kbc-rtc-serial--abbreviated)
- **Refs:** [references.md](../../references.md) — NS PC16550D datasheet

## Purpose

Verify UART: DLAB-gated register access, loopback self-test (no external wiring needed),
FIFO enable/disable and IIR status, scratch register chip-ID (8250 lacks it), and
modem-status delta bits.

## Port Map (COM1: 0x3F8)

| Port | DLAB | Register | Notes |
|------|:----:|----------|-------|
| 0x3F8 | 0 | THR (W) / RBR (R) | transmit/receive holding register |
| 0x3F8 | 1 | DLL | divisor latch low byte |
| 0x3F9 | 0 | IER | interrupt enable register |
| 0x3F9 | 1 | DLH | divisor latch high byte |
| 0x3FA | — | IIR (R) | interrupt identification register |
| 0x3FB | — | LCR | line control register (bit 7 = DLAB) |
| 0x3FC | — | MCR | modem control register (bit 4 = loopback) |
| 0x3FD | — | LSR | line status register |
| 0x3FE | — | MSR | modem status register |
| 0x3FF | — | SCR | scratch register (8250 lacks this) |

## Test Cases

### DLAB gating

| # | LCR DLAB | Port 0x3F8 | Port 0x3F9 | Notes |
|---|:--------:|------------|------------|-------|
| 1 | 0 | THR/RBR (data) | IER (interrupt enable) | |
| 2 | 1 | DLL (divisor low) | DLH (divisor high) | set via LCR bit 7 |

| # | Action | Expected | Notes |
|---|--------|----------|-------|
| 1 | Set DLAB=1 (LCR ← 0x80) | 0x3F8 now maps to DLL | |
| 2 | Write 0x60 to 0x3F8 (DLL=0x60) | divisor low = 96 | |
| 3 | Write 0x00 to 0x3F9 (DLH=0x00) | divisor high = 0 | baud = 115200/96 = 1200 |
| 4 | Set DLAB=0 (LCR ← 0x03) | 0x3F8 now maps to THR/RBR | 8N1, DLAB=0 |

### Loopback self-test (MCR bit 4)

| # | Action | Expected | Notes |
|---|--------|----------|-------|
| 1 | Set MCR bit 4=1 (loopback) | THR output loops to RBR input | no external wiring |
| 2 | Write byte 0x55 to THR (0x3F8) | transmitted internally | |
| 3 | Poll LSR bit 0 (DR=data ready) | bit 0=1 within timeout | |
| 4 | Read RBR (0x3F8) | reads 0x55 | round-trip |
| 5 | Write byte 0xAA, read back | reads 0xAA | second round-trip |

> **Loopback mode** is the primary UART self-test. No external loop cable needed.
> The THR→RBR loopback path also echoes MCR output pins to MSR input pins.

### FIFO enable (16550/16550A)

| # | Action | Expected | Notes |
|---|--------|----------|-------|
| 1 | Write FCR 0x07 (FIFO enable + clear RX+TX) | FIFOs enabled | bit 0=enable, bits 1-2=clear |
| 2 | Read IIR (0x3FA) | bit 6+7 set = FIFO enabled | 16550A: both bits set |
| 3 | Write FCR 0x00 | FIFO disabled | |

### FIFO bug detection (16550 vs 16550A)

| # | Read IIR bits 7:6 | Chip type | Notes |
|---|:-----------------:|-----------|-------|
| 1 | 00 | 8250/16450 (no FIFO) | |
| 2 | 10 | 16550 (FIFO bug, unusable) | original 16550 |
| 3 | 11 | 16550A (FIFO works) | most common |

### Scratch register chip-ID

| # | Action | Expected | Notes |
|---|--------|----------|-------|
| 1 | Write 0xAA to SCR (0x3FF) | | |
| 2 | Read SCR | 0xAA (16550: present; 8250: absent/wrong) | |

### Modem status delta bits

| # | Setup (loopback) | Action | MSR bits | Notes |
|---|------------------|--------|----------|-------|
| 1 | Loopback on; set MCR DTR (bit 0) | read MSR | bit 0 (DCTS delta if RTS) | in loopback, RTS→CTS |
| 2 | Toggle MCR RTS (bit 1) | read MSR | bit 0 (DCTS) set | delta flag latches |
| 3 | Read MSR again | delta bits cleared | read-clear behavior |

### Line status

| # | Bit | Meaning | Test |
|---|:---:|---------|------|
| 1 | 0 | DR (data ready) | loopback write → read |
| 2 | 5 | THRE (transmit holding empty) | write THR → poll |
| 3 | 6 | TEMT (transmit shift empty) | wait longer |

## Pre/Post State (representative cases)

### DLAB gating — set baud rate divisor
PRE:
  LCR (0x3FB) = 0x03   (8N1, DLAB=0)
  DLL/DLH = unknown
OP:  OUT 0x3FB, 0x80   ; set DLAB=1 (bit 7)
     OUT 0x3F8, 0x60   ; DLL = 0x60 (LSB of divisor)
     OUT 0x3F9, 0x00   ; DLH = 0x00 (MSB of divisor)
     OUT 0x3FB, 0x03   ; DLAB=0, 8N1 restored
POST:
  Divisor = 0x0060 = 96
  Baud rate = 115200 / 96 = 1200 baud
  Port 0x3F8 now maps to THR/RBR (data), not DLL

### Loopback self-test — write/read byte
PRE:
  MCR (0x3FC) = 0x00   (loopback off)
  LSR (0x3FD) = 0x60   (THRE=1, TEMT=1, DR=0)
  RBR = empty
OP:  OUT 0x3FC, 0x10   ; set MCR bit 4 = loopback enable
     OUT 0x3F8, 0x55   ; write byte to THR
     ; poll LSR bit 0 (DR) until set
     IN  AL, 0x3F8     ; read RBR
POST:
  AL = 0x55            ← loopback round-trip successful
  LSR bit 0 (DR) = 0 after read (data consumed)
  ← THR output connected to RBR input internally

### Loopback — MCR to MSR pin echo
PRE:
  MCR = 0x10  (loopback on, all outputs low)
  MSR (0x3FE) = unknown
OP:  OUT 0x3FC, 0x1F   ; loopback + DTR + RTS + OUT1 + OUT2
     IN  AL, 0x3FE     ; read MSR
POST:
  AL = MSR byte with delta flags:
    bit 0 (DCTS) = 1   ← CTS changed (RTS toggled)
    bit 1 (CTS)  = 1   ← CTS follows RTS in loopback
    bit 2 (DDSR) = 1   ← DSR changed (DTR toggled)
    bit 3 (DSR)  = 1   ← DSR follows DTR
    bit 4-7 = reflected outputs
  ← Delta bits latch until MSR is read (read-clear)

OP:  IN AL, 0x3FE      ; read MSR again
POST:
  Delta bits (0,2,4,6) = 0   ← cleared by first read

### FIFO enable/disable (16550A)
PRE:
  FCR not yet written
  IIR (0x3FA) = unknown
OP:  OUT 0x3FA, 0x07   ; FCR: enable + clear RX + clear TX
     IN  AL, 0x3FA     ; read IIR
POST:
  AL bits 7:6 = 11     ← FIFO enabled (16550A)
  AL bit 0 = 1         ← no pending interrupt (after FIFO clear)
  ← If bits 7:6 = 00 → no FIFO (8250/16450)
  ← If bits 7:6 = 10 → 16550 with FIFO bug (unusable)

### Scratch register chip-ID
PRE:
  SCR (0x3FF) = unknown
OP:  OUT 0x3FF, 0xAA   ; write to scratch register
     IN  AL, 0x3FF     ; read back
POST:
  AL = 0xAA            ← scratch present (16450/16550+)
  ← If AL = 0x00 or garbage → 8250 (no scratch register)

## State Save/Restore

- **Save:** LCR, IER, MCR, FCR, SCR, DLL/DLH (if accessible)
- **Restore:** write back LCR (restore DLAB), MCR (clear loopback), IER, FCR, SCR
- **Drain:** before restore, read RBR until DR=0 (flush receive buffer)

## Pass/Fail Criteria

- **PASS:** DLAB gating works; loopback round-trip succeeds; FIFO enable/disable works;
  IIR correctly reports chip type; scratch register present
- **FAIL:** loopback data lost; DLAB not gating; IIR wrong; no scratch register
- **SKIP:** if no serial port at 0x3F8 (detect via scratch register or IIR)

## Known Divergences

- **8250 vs 16450:** 8250 lacks scratch register; 16450 has it. Both lack FIFO.
  16550 has FIFO bug (unusable). 16550A is the first usable FIFO UART.
- **COM2 (0x2F8):** secondary serial port; test only if present.
- **THRE interrupt:** if testing interrupt-driven mode, enable IER bit 1 and verify
  THRE interrupt fires. Requires PIC integration.
