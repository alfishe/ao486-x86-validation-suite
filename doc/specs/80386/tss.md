# Spec: 386 TSS Task Switch

## Metadata
- **Source file:** `src/cpu/80386/tss.asm`
- **TIER:** RING0 | VENUE: G | GEN: 80386+ | ORACLE: manual
- **Impl-plan:** Phase 5, area `386-TSS`
- **Coverage:** [§7](../../coverage-matrix.md#7-cpu--80386-pri-1-32-bit--paging--v86)
- **Detail:** [prep-analysis §7](../../prep-analysis.md#7-tss-task-switch-matrix)
- **Prerequisite:** [286-pm-infra.md](../80186-286/286-pm-infra.md)

## Purpose

Verify hardware task switching via JMP/CALL to TSS selector, IRET with NT=1,
TSS busy bit, and register save/restore across the switch.

## 386 TSS Format (104 bytes minimum)

```
Offset  Size  Field
0x00    2     Previous task link (back-link)
0x02    2     (reserved)
0x04    4     ESP0
0x08    4     SS0
0x0C    4     ESP1
0x10    4     SS1
0x14    4     ESP2
0x18    4     SS2
0x1C    4     CR3
0x20    4     EIP
0x24    4     EFLAGS
0x28    4     EAX
0x2C    4     ECX
0x30    4     EDX
0x34    4     EBX
0x38    4     ESP
0x3C    4     EBP
0x40    4     ESI
0x44    4     EDI
0x48    2     ES
0x4A    2     CS
0x4C    2     SS
0x4E    2     DS
0x50    2     FS
0x52    2     GS
0x54    2     LDTR
0x56    2     (debug trap flag, bit 0)
0x58    2     I/O map base
```

## Test Cases

### Task switch via JMP to TSS

| # | Action | Expected | Notes |
|---|--------|----------|-------|
| 1 | JMP TSS_SEL:0 | current state saved to current TSS; target TSS loaded | |
| 2 | Verify registers | target EAX..EDI loaded from target TSS | |
| 3 | Verify CR3 | if target TSS CR3≠0, CR3 is loaded (paging context switch) | |

### Task switch via CALL to TSS

| # | Action | Expected | Notes |
|---|--------|----------|-------|
| 1 | CALL TSS_SEL:0 | NT set in target EFLAGS; back-link set in target TSS | nested task |
| 2 | IRET with NT=1 | returns to previous task via back-link | |

### Register save/restore

| # | What to verify | How | Notes |
|---|---------------|-----|-------|
| 1 | Old task saved | After switch, read old TSS: EAX, EIP match pre-switch values | |
| 2 | New task loaded | After switch, actual EAX, EIP match new TSS values | |
| 3 | EFLAGS saved | Old TSS EFLAGS has correct IF, NT, etc. | |

### Busy bit

| # | State | Action | Expected | Notes |
|---|-------|--------|----------|-------|
| 1 | TSS not busy | JMP to it | TSS becomes busy (A bit + type becomes 0xB) | |
| 2 | TSS already busy | JMP to it again | **#GP** | can't switch to busy task |
| 3 | Task switch away | JMP to another | old TSS busy bit cleared | (if not nesting) |

> TSS descriptor type: 0x9 = available, 0xB = busy.

### NT flag and back-link

| # | NT in target EFLAGS | Back-link | Behavior | Notes |
|---|:-------------------:|-----------|----------|-------|
| 1 | set by CALL task switch | = old TSS selector | IRET returns to old task | |
| 2 | not set by JMP task switch | not used | IRET acts normal | |

### I/O permission bitmap

| # | I/O map base in TSS | Port access | Expected | Notes |
|---|:-------------------:|-------------|----------|-------|
| 1 | ≥ TSS limit | any port | **#GP** at CPL>IOPL | no I/O map → all blocked |
| 2 | valid, bit=0 for port 0x60 | IN 0x60 at CPL=3 | OK | port allowed |
| 3 | valid, bit=1 for port 0x60 | IN 0x60 at CPL=3 | **#GP** | port blocked |

> I/O permission bitmap is at TSS offset `I/O map base`. Each bit = one port.
> 0 = allowed, 1 = blocked (when CPL > IOPL).

## Pre/Post State (representative cases)

### Task switch via JMP to TSS — register save/restore
PRE (Task A running, TSS_A at phys 0x00080000):
  EAX = 0x11111111, ECX = 0x22222222, EDX = 0x33333333, EBX = 0x44444444
  ESP = 0x00090000, EBP = 0x00091000
  ESI = 0x55555555, EDI = 0x66666666
  EIP = 0x00001000, CS = 0x0008
  CR3 = 0x0009F000
  EFLAGS = 0x00000046   (IF=1, ZF=1)
  GDT[TSS_A_SEL] = type 0x9 (available), P=1
  GDT[TSS_B_SEL] = type 0x9 (available), P=1
  TSS_B at phys 0x00081000 contains:
    EIP=0x00002000, CS=0x0008, EAX=0xAAAAAAAA, CR3=0x000A0000, EFLAGS=0x00000002
OP:  JMP TSS_B_SEL:0   (switch to task B)
POST:
  CPU state (now running Task B):
    EAX = 0xAAAAAAAA   ← loaded from TSS_B
    EIP = 0x00002000   ← loaded from TSS_B
    CR3 = 0x000A0000   ← loaded from TSS_B (TLB flushed)
    EFLAGS = 0x00000002
  TSS_A now contains (saved by CPU before switch):
    EAX = 0x11111111   ← Task A state preserved
    EIP = 0x00001000   ← return point in Task A
    CR3 = 0x0009F000
    EFLAGS = 0x00000046
  GDT[TSS_A_SEL] type = 0x1 (available — JMP cleared busy)
  GDT[TSS_B_SEL] type = 0xB (busy — now running)

### Task switch via CALL — NT and back-link
PRE:
  EFLAGS = 0x00000002  (NT=0)
  GDT[TSS_B_SEL] = type 0x9 (available)
OP:  CALL TSS_B_SEL:0
POST:
  EFLAGS = 0x00004002  (NT=1 bit14 set) ← nested task
  TSS_B.prev_link = TSS_A_SEL  ← back-link to caller
  GDT[TSS_B_SEL] = type 0xB (busy)
  GDT[TSS_A_SEL] = type 0xB (busy — still busy because nested)

### IRET with NT=1 — return to previous task
PRE (in Task B, NT=1):
  EFLAGS = 0x00004002  (NT=1)
  TSS_B.prev_link = TSS_A_SEL
OP:  IRETD
POST:
  Task switch back to Task A via back-link
  EFLAGS restored from TSS_A (NT=0 if A wasn't nested)
  GDT[TSS_B_SEL] = type 0x9 (available — returned from)
  GDT[TSS_A_SEL] = type 0xB (busy — resumed)

### JMP to busy TSS → #GP
PRE:
  GDT[TSS_B_SEL] = type 0xB (already busy, task B running or nested)
OP:  JMP TSS_B_SEL:0
POST:
  #GP exception, error code = TSS_B_SEL | TI

### I/O permission bitmap — allowed port
PRE (CPL=3, IOPL=3):
  TSS limit = 0x0068  (I/O map base = 0x68)
  Bitmap at TSS+0x68: byte for port 0x60 (byte index 0x0C) = 0x00  (bit0=0 allowed)
  DX = 0x0060
OP:  IN AL, DX   (at CPL=3)
POST:
  AL = value from port 0x60   ← access allowed

### I/O permission bitmap — blocked port
PRE (CPL=3, IOPL=3):
  Bitmap at TSS+0x68: byte for port 0x60 = 0x01  (bit0=1 blocked)
  DX = 0x0060
OP:  IN AL, DX   (at CPL=3)
POST:
  #GP(0) exception   ← I/O permission denied

## State Save/Restore

- **Save:** both TSS structures; GDT TSS descriptors (busy bits)
- **Restore:** restore TSS data; clear busy bits

## Known Divergences

| Behavior | 286 | 386+ | Action |
|----------|------|------|--------|
| TSS size | 44 bytes | 104 bytes | gen-gate |
| CR3 field | absent | present | 286 doesn't switch CR3 |
| I/O bitmap | absent | present | 286 uses IOPL only |

## Pass/Fail Criteria

- **PASS:** registers saved/restored correctly; busy bit maintained; NT/back-link work
- **FAIL:** wrong register values or missing busy-bit check
- **SKIP:** GEN < 80386
