# Spec: 286 Exceptions & Interrupts

## Metadata
- **Source file:** `src/cpu/80286/exceptions.asm`
- **TIER:** RING0 | VENUE: G | GEN: 80286+ | ORACLE: manual
- **Impl-plan:** Phase 4, area `286-Exc`
- **Coverage:** [§6](../../coverage-matrix.md#6-cpu--80286-pri-1-for-pm-the-first-big-divergence-surface)
- **Prerequisite:** [286-pm-infra.md](286-pm-infra.md)
- **Pattern:** [adding-tests.md "Exception Handler"](../../adding-tests.md#exception-handler-pattern)

## Purpose

Verify exception delivery in PM: error codes, interrupt gates vs trap gates,
interrupt flag (IF) auto-clear, and Nested Task (NT) flag.

## Test Cases

### Error code delivery

| # | Exception | Error code? | Error format | Notes |
|---|-----------|:-----------:|-------------|-------|
| 1 | #GP | yes | selector + EXT + IDT bits | |
| 2 | #UD | no | — | no error code pushed |
| 3 | #TS | yes | selector | |
| 4 | #NP | yes | selector | |
| 5 | #SS | yes | selector | |
| 6 | #PF (386+) | yes | page fault address (CR2) | 386+ |

> Verify: exceptions WITH error codes push 4 bytes (error + nothing for 286,
> or error word for 386).  Exceptions WITHOUT push 0 bytes.

### Interrupt gate vs trap gate

| # | Gate type | IF after entry | Notes |
|---|-----------|:--------------:|-------|
| 1 | Interrupt gate (type 0x8E) | IF=0 (cleared) | interrupts disabled on entry |
| 2 | Trap gate (type 0x8F) | IF unchanged | preserves IF state |

> **Key:** interrupt gates clear IF; trap gates don't.  Verify by reading
> FLAGS on the stack inside the handler.

### INT instruction in PM

| # | DPL of gate | CPL | Expected | Notes |
|---|:-----------:|:----:|----------|-------|
| 1 | DPL=3 | CPL=0 | OK (CPL ≤ DPL for software INT) | |
| 2 | DPL=0 | CPL=3 | **#GP** | ring 3 can't use DPL=0 gate via INT |
| 3 | DPL=3 | CPL=3 | OK | ring 3 CAN use DPL=3 gate |

> **Software INT** (INT n): requires CPL ≤ gate DPL.
> **Hardware interrupt/exception**: DPL check is bypassed.

### IRET behavior in PM

| # | NT flag | IRET behavior | Notes |
|---|:-------:|---------------|-------|
| 1 | NT=0 | pops IP, CS, FLAGS (intra-task) | normal return |
| 2 | NT=1 | performs task switch to previous task | nested task return |

> NT=1 IRET does a task switch (reads back-link from TSS).
> Verify: stack frame is restored from the target TSS, not from the stack.

### Exception priority (simultaneous faults)

| # | Conditions | Exception | Notes |
|---|-----------|-----------|-------|
| 1 | #GP + #UD | #GP wins | higher priority |
| 2 | #SS + #GP | #SS wins | stack fault > GP |

> Full priority ordering: see [prep-analysis §9](../../prep-analysis.md#9-exception-priority-matrix)

## Pre/Post State (representative cases)

### Interrupt gate — IF auto-cleared

```
PRE (PM32, CPL=0):
  FLAGS = 0x0202  (IF=1, interrupts enabled)
  ESP = 0x00008000
  IDT entry 13: interrupt gate (type=0x8E), DPL=0
    target: CS=0x08, EIP=gp_handler

  OP:  trigger #GP (e.g., load null selector into DS)

POST (inside handler):
  Stack (SS0:ESP0 from TSS):
  [ESP0-4]  = old EFLAGS  (0x0202 — IF was 1 before entry)
  [ESP0-8]  = old CS      (0x08)
  [ESP0-12] = old EIP      (faulting instruction address)
  [ESP0-16] = error code   (selector + Ext bit)
  ESP = ESP0 - 16
  FLAGS = 0x0002  (IF=0 — interrupt gate clears IF)
  CS = 0x08, EIP = gp_handler
```

### Trap gate — IF preserved

```
PRE (PM32, CPL=0):
  FLAGS = 0x0202  (IF=1)
  IDT entry 3: trap gate (type=0x8F), DPL=3

  OP:  INT3 (software breakpoint)

POST (inside handler):
  FLAGS = 0x0202  (IF=1 — trap gate does NOT clear IF)
  Stack:
  [ESP-4]  = old EFLAGS  (0x0202)
  [ESP-8]  = old CS
  [ESP-12] = old EIP
  (no error code for INT3)
```

### #GP with error code

```
PRE:
  Attempt: MOV DS, 0x0000 (null selector)
  ESP = 0x7F00

  OP:  (triggers #GP)

POST:
  Stack frame pushed:
  [SS:0x7EFC] = return EIP
  [SS:0x7EF8] = return CS
  [SS:0x7EF4] = EFLAGS
  [SS:0x7EF0] = error code = 0x0000 (null selector, no Ext for software trigger)
  ESP = 0x7EF0
```

### IRET — normal return (NT=0)

```
PRE (inside handler, PM32):
  Stack:
  [ESP]    = return EIP = 0x1000
  [ESP+4]  = return CS = 0x08
  [ESP+8]  = return EFLAGS = 0x0202
  NT = 0

  OP:  IRETD

POST:
  EIP = 0x1000
  CS = 0x08
  EFLAGS = 0x0202  (IF restored)
  ESP += 12
```

## State Save/Restore

- **Save:** IDT entries for test vectors; IF; NT flag
- **Restore:** restore IDT entries; restore IF/NT

## Pass/Fail Criteria

- **PASS:** error codes correct; IF handling matches gate type; IRET works
- **FAIL:** wrong error code or IF not cleared by interrupt gate
- **SKIP:** GEN < 80286
