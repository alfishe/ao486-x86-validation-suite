# Spec: 8259 PIC (Programmable Interrupt Controller)

## Metadata
- **Source file:** `src/peripheral/pic/pic.asm`
- **TIER:** HARDWARE | VENUE: G | GEN: 8086+ | ORACLE: manual
- **Impl-plan:** Phase 7, area `PIC`
- **Coverage:** [§9.1](../../coverage-matrix.md#91-hard-cases--pic-8259)
- **Detail:** [prep-analysis §6](../../prep-analysis.md#6-peripheral-stateful-behavior)
- **Refs:** [references.md](../../references.md) — Intel 8259A datasheet

## Purpose

Verify PIC ICW/OCW programming, interrupt masking, priority, EOI, spurious IRQ.

## Port Map

| Port | PIC1 (master) | PIC2 (slave) |
|------|:-------------:|:------------:|
| 0x20 | ICW1/OCW2/OCW3 | ICW1/OCW2/OCW3 |
| 0x21 | ICW2/ICW3/ICW4/IMR | ICW2/ICW3/ICW4/IMR |
| 0xA0 | — | ICW1/OCW2/OCW3 |
| 0xA1 | — | ICW2/ICW3/ICW4/IMR |

## Test Cases

### ICW initialization sequence

| # | Port | Value | Purpose | Notes |
|---|:----:|:-----:|---------|-------|
| 1 | 0x20 | 0x11 | ICW1: edge-triggered, cascade, ICW4 needed | |
| 2 | 0x21 | 0x08 | ICW2: base vector = 0x08 (IRQ0) | |
| 3 | 0x21 | 0x04 | ICW3: slave on IRQ2 (bit 2) | |
| 4 | 0x21 | 0x01 | ICW4: 8086 mode, normal EOI | |

### Interrupt masking (OCW1)

| # | IMR value | Effect | Notes |
|---|-----------|--------|-------|
| 1 | 0xFF | all IRQs masked | |
| 2 | 0xFB | IRQ0 unmasked, rest masked | bit 1 clear |

### EOI (End of Interrupt)

| # | Port | Value | Action | Notes |
|---|:----:|:-----:|--------|-------|
| 1 | 0x20 | 0x20 | non-specific EOI | clears highest-priority ISR bit |
| 2 | 0x20 | 0x60 | specific EOI for IRQ0 | clears ISR bit 0 |

### Spurious IRQ7

| # | Condition | Expected | Notes |
|---|-----------|----------|-------|
| 1 | IRQ asserted then deasserted before CPU ACK | spurious IRQ7 delivered | ISR bit 7 NOT set |

> Verify spurious IRQ: trigger IRQ, then deassert before the first INTA cycle.
> The PIC will deliver IRQ7 but the ISR bit won't be set — that's how you
> detect it's spurious.

### Priority rotation

| # | OCW2 value | Priority mode | Notes |
|---|-----------|---------------|-------|
| 1 | 0x20 | fixed priority, IRQ0 highest | default |
| 2 | 0xC0 | rotate, IRQ0 lowest | |
| 3 | 0xA0 | rotate on non-specific EOI | |

### Read IRR / ISR

| # | Port | OCW3 value | Read | Expected |
|---|:----:|:----------:|------|----------|
| 1 | 0x20 | 0x0A | read IRR | interrupt request register |
| 2 | 0x20 | 0x0B | read ISR | in-service register |

## Pre/Post State (representative cases)

### ICW initialization sequence (master PIC1)
PRE:
  PIC1 state: uninitialized (after BIOS POST, may be programmed)
  IMR (port 0x21) = unknown
OP:  OUT 0x20, 0x11   ; ICW1: edge-triggered, cascade, ICW4 needed
     OUT 0x21, 0x08   ; ICW2: base vector = 0x08
     OUT 0x21, 0x04   ; ICW3: slave attached to IRQ2
     OUT 0x21, 0x01   ; ICW4: 8086 mode, normal EOI
POST:
  PIC1 vector offset = 0x08  (IRQ0 → INT 0x08, IRQ7 → INT 0x0F)
  Cascade config: slave on IRQ2
  EOI mode: normal (non-auto)
  IMR = 0x00           (all IRQs unmasked after init)

### Interrupt masking (OCW1)
PRE:
  IMR (port 0x21) = 0x00   (all unmasked)
OP:  OUT 0x21, 0xFB         (mask all except IRQ1 — keyboard)
POST:
  IMR = 0xFB = 11111011b
  IRQ0 masked, IRQ1 unmasked, IRQ2-7 masked

### Non-specific EOI (OCW2)
PRE:
  ISR (read via OCW3) = 0x04   (IRQ2 in-service, highest priority)
OP:  OUT 0x20, 0x20            (non-specific EOI)
POST:
  ISR = 0x00                   (bit 2 cleared — highest ISR bit reset)
  ← PIC knows which IRQ was being serviced and clears only that bit

### Specific EOI for IRQ0
PRE:
  ISR = 0x01   (IRQ0 in-service)
OP:  OUT 0x20, 0x60            (specific EOI for IRQ0: 0x60 = 01100000b)
POST:
  ISR = 0x00                   (bit 0 explicitly cleared)

### Read IRR / ISR via OCW3
PRE:
  IRR = 0x82   (IRQ7 + IRQ1 requesting)
  ISR = 0x00   (none in-service)
OP:  OUT 0x20, 0x0A   (OCW3: read IRR)
     IN  AL, 0x20     (read IRR)
POST:
  AL = 0x82         ← IRR value returned
OP:  OUT 0x20, 0x0B   (OCW3: read ISR)
     IN  AL, 0x20     (read ISR)
POST:
  AL = 0x00         ← ISR value returned

### Spurious IRQ7 detection
PRE:
  IRQ7 line asserted briefly then deasserted before INTA
  ISR after interrupt = 0x00   (bit 7 NOT set — spurious)
OP:  Handler reads ISR via OCW3
POST:
  If ISR bit 7 = 0 → spurious IRQ7 (ignore, no EOI needed)
  If ISR bit 7 = 1 → real IRQ7 (service it, send EOI)

## State Save/Restore

- **Save:** all IMR registers; ICW state; OCW3 poll bit
- **Restore:** reinitialize PIC with original ICW sequence; restore masks

## Timing Tolerances

| Operation | Expected | Tolerance | Notes |
|-----------|:--------:|:---------:|-------|
| ICW sequence completion | immediate | — | no delay needed between ICWs |
| IRQ to INT delivery | < 100 clocks | ±50 | depends on instruction boundary |
| EOI to ISR clear | immediate | — | ISR readable as 0 on next read |
| Spurious IRQ7 window | ~3 PCLK cycles | — | glitch < 3 cycles may cause spurious |

> Timing is venue G (guest-observable). Precise cycle counts are venue T (bench).

## Pass/Fail Criteria

- **PASS:** ICW accepted; masking works; EOI clears ISR; spurious detected
- **FAIL:** wrong IRQ delivery or ISR state
- **SKIP:** never (PIC present on all PC targets)
