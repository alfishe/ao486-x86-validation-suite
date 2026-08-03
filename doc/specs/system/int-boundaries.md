# Spec: Interrupt Boundaries (MOV SS Shadow, STI Delay, TF Interplay)

## Metadata
- **Source file:** `src/core/intbound.asm`
- **TIER:** RING0 | VENUE: G | GEN: 8086+ | ORACLE: manual
- **Impl-plan:** Phase 8, area `IntBound`
- **Coverage:** [§10, §10.2](../../coverage-matrix.md#102-hard-cases--interrupts--exceptions)
- **Detail:** [prep-analysis §9](../../prep-analysis.md#9-exception-priority-matrix)
- **Refs:** [references.md](../../references.md) — Intel 80386 Programmer's Reference §9.5

## Purpose

Verify the three interrupt-boundary rules that emulators frequently get wrong:

1. **MOV SS / POP SS shadow:** interrupts (and single-step TF) are inhibited for
   exactly one instruction after `MOV SS` or `POP SS`.
2. **STI one-instruction delay:** `STI` enables interrupts starting from the
   *next* instruction, not immediately.
3. **TF interplay:** TF=1 causes #DB after each instruction; but TF is also shadowed
   by the MOV/POP SS rule; POPF/IRET setting TF steps the *next* instruction.

## Test Cases

### MOV SS shadow — interrupt inhibition

| # | Setup | Sequence | Expected | Notes |
|---|-------|----------|----------|-------|
| 1 | Install INT handler; raise IRQ via PIC | `mov ss, ax` / `nop` | IRQ delivered after `nop` | interrupt after MOV SS is delayed |
| 2 | (same) | `mov ss, ax` / `mov sp, bx` | IRQ delivered after `mov sp` | MOV SS + MOV SP atomic |
| 3 | (same) | `pop ss` / `mov ax, bx` | IRQ delivered after `mov ax` | POP SS also shadows |

> The classic use case: `MOV SS` / `MOV SP` must be atomic to prevent an interrupt
> between them from using a stale SP.

### MOV SS shadow — single-step inhibition

| # | Setup | TF | Sequence | Expected | Notes |
|---|-------|:--:|----------|----------|-------|
| 1 | Install #DB handler; TF=1 | 1 | `mov ss, ax` | NO #DB after MOV SS | shadowed |
| 2 | (same) | 1 | `mov ss, ax` / `nop` | #DB fires after `nop` (2nd insn) | TF still set |
| 3 | TF=1; POFF to clear TF | 1→0 | `popf` (clears TF) | #DB does NOT fire after POPF | POPF itself is stepped (if TF was on before) |

### STI one-instruction delay

| # | Setup | IF | Sequence | Expected | Notes |
|---|-------|:--:|----------|----------|-------|
| 1 | IRQ pending; IF=0 | 0 | `sti` / `nop` | IRQ delivered after `nop`, not after `sti` | STI delays 1 instruction |
| 2 | IRQ pending; IF=0 | 0 | `sti` / `cli` | IRQ NOT delivered (CLI ran first) | delay lets CLI block |
| 3 | IRQ pending; IF=0 | 0 | `sti` / `hlt` | IRQ delivered (HLT doesn't block) | STI then HLT |

> **STI delay verification:** raise an IRQ while IF=0, then execute `STI` followed by
> a single instruction. The interrupt must NOT be taken between STI and the following
> instruction.

### TF — single-step delivery

| # | Setup | Sequence | Expected | Notes |
|---|-------|----------|----------|-------|
| 1 | TF=1 via PUSHF/POPF | `popf` / `nop` / `nop` | #DB after 1st `nop` | TF set by POPF steps next insn |
| 2 | TF=1 via IRET | `iret` / `nop` | #DB after `nop` | TF set by IRET steps next insn |
| 3 | In #DB handler, TF still set | return from handler | #DB after next insn | continuous single-stepping |

### TF + MOV SS combined

| # | Setup | TF | Sequence | Expected | Notes |
|---|-------|:--:|----------|----------|-------|
| 1 | TF=1 | 1 | `mov ss, ax` / `nop` | NO #DB after MOV SS; #DB after `nop` | both rules apply |

### Nested IRQ + IF (interrupt vs trap gate)

| # | Gate type | IF after entry | Expected | Notes |
|---|-----------|:--------------:|----------|-------|
| 1 | Interrupt gate (286/386) | IF=0 (auto-cleared) | nested IRQ disabled in handler | |
| 2 | Trap gate (286/386) | IF unchanged | nested IRQ enabled if IF was 1 | |
| 3 | IRET | restores IF from stacked FLAGS | | |

> See [286-exceptions.md](../80186-286/286-exceptions.md) for interrupt vs trap
> gate descriptor formats.

## Pre/Post State (representative cases)

### MOV SS shadow — interrupt inhibition
PRE (real mode, IRQ pending):
  PIC IRQ0 asserted (timer tick pending)
  IF = 1
  AX = 0x0010  (new SS value)
  SS = old SS
  SP = old SP
  EIP = 0x00001000  (address of `MOV SS, AX`)
  Next instruction at 0x00001002: `MOV SP, BX`  (BX = new SP)
OP:  MOV SS, AX          ; SS loaded; interrupts inhibited for 1 instruction
     MOV SP, BX          ; SP loaded; NOW interrupts are re-enabled
POST:
  SS:SP = 0x0010:BX      ← both updated atomically (no IRQ between them)
  IRQ delivered after `MOV SP, BX` completes
  ← Without shadow: IRQ could fire between MOV SS and MOV SP,
    corrupting stack pointer

### MOV SS shadow — TF (single-step) inhibition
PRE (PM32, CPL=0, TF=1):
  EFLAGS = 0x00000102  (TF=1 bit8, IF=1)
  #DB handler installed
  AX = 0x0010
  EIP = 0x00001000: `MOV SS, AX`
  Next: 0x00001002: `NOP`
OP:  MOV SS, AX   ; TF shadowed: NO #DB fires here
POST:  (after MOV SS)
  No #DB exception   ← TF was inhibited by MOV SS shadow
OP:  NOP            ; shadow ends, TF active again
POST:  (after NOP)
  #DB exception fires   ← single-step delivered after NOP

### STI one-instruction delay
PRE (IF=0, IRQ pending on PIC):
  EFLAGS = 0x00000002  (IF=0)
  PIC IRQ0 asserted
  EIP = 0x00001000: `STI`
  Next: 0x00001001: `NOP`
OP:  STI                ; IF set to 1, but delivery delayed
     NOP                ; IRQ NOT taken yet (delay)
POST:  (after NOP)
  EFLAGS = 0x00000202  (IF=1)
  IRQ delivered NOW     ← STI delayed interrupt until after NOP
  ← If instruction after STI is CLI: IRQ is never delivered

### STI then CLI — IRQ blocked
PRE (IF=0, IRQ pending):
  EIP = 0x00001000: `STI`
  Next: 0x00001001: `CLI`
OP:  STI   ; IF=1, but delayed
     CLI   ; IF=0 again before IRQ delivered
POST:
  No IRQ delivered    ← CLI executed before the delayed interrupt window
  EFLAGS = 0x00000002  (IF=0)

### Interrupt gate — IF auto-cleared
PRE (PM32, IRQ via interrupt gate):
  EFLAGS = 0x00000202  (IF=1)
  IDT[0x08] = interrupt gate (type 0x8E), target=handler
  PIC IRQ0 asserted
OP:  (CPU services INT 0x08 via interrupt gate)
POST:
  In handler:
  EFLAGS = 0x00000002  (IF=0 auto-cleared)  ← nested IRQ disabled
  Stacked EFLAGS = 0x00000202  (original IF=1 saved)

### Trap gate — IF preserved
PRE (PM32, IRQ via trap gate):
  EFLAGS = 0x00000202  (IF=1)
  IDT[0x08] = trap gate (type 0x8F), target=handler
  PIC IRQ0 asserted
OP:  (CPU services INT 0x08 via trap gate)
POST:
  In handler:
  EFLAGS = 0x00000202  (IF=1 preserved)  ← nested IRQ still enabled

## State Save/Restore

- **Save:** FLAGS (TF, IF), original IVT entries for INT and #DB handlers
- **Restore:** restore FLAGS; restore IVT entries; restore PIC masks if IRQ was used
- **SS/SP:** must be restored if test modified SS/SP

## Pass/Fail Criteria

- **PASS:** MOV SS shadows interrupts for 1 instruction; STI delays interrupt delivery
  by 1 instruction; TF is shadowed by MOV SS; interrupt gate clears IF, trap gate doesn't
- **FAIL:** interrupt delivered between MOV SS and MOV SP; STI enables immediately;
  TF fires after MOV SS; interrupt gate doesn't clear IF
- **SKIP:** GEN < 80286 for trap/interrupt gate distinction (8086 always clears IF on INT)

## Known Divergences

- **8086 INT and IF:** the 8086 always clears IF on INT (no trap/interrupt gate
  distinction). The distinction is 286+ only.
- **POPF/IRET TF timing:** on some implementations, the exact instruction stepped after
  setting TF via POPF/IRET may differ. Verify on reference hardware.
- **NMI:** NMI is not affected by IF and has its own masking latch (NMI accepted
  until IRET from NMI handler). Hard to test without external NMI trigger.
