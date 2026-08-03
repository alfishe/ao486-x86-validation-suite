# Spec: Exception Taxonomy (Fault/Trap/Abort, Error Codes, Double Fault)

## Metadata
- **Source file:** `src/core/except.asm`
- **TIER:** RING0 | VENUE: G | GEN: 80286+ | ORACLE: manual
- **Impl-plan:** Phase 8, area `Except`
- **Coverage:** [§10, §10.2](../../coverage-matrix.md#102-hard-cases--interrupts--exceptions)
- **Detail:** [prep-analysis §9](../../prep-analysis.md#9-exception-priority-matrix)
- **Refs:** [references.md](../../references.md) — Intel 80386 Programmer's Reference §9

## Purpose

Verify exception classification: faults (restart, saved CS:EIP = faulting instruction),
traps (saved CS:EIP = next instruction), error-code-push behavior, and double fault
triggering.

## Exception Classification

### Faults (restartable: saved IP = faulting instruction)

| # | Exception | Vector | Trigger | Saved IP | Error code? | Notes |
|---|-----------|:------:|---------|:--------:|:-----------:|-------|
| 1 | #DE (divide error) | 0 | DIV/IDIV by 0 | faulting insn | no | |
| 2 | #UD (undefined opcode) | 6 | illegal instruction | faulting insn | no | |
| 3 | #NM (device not available) | 7 | FPU insn with CR0.EM=1 or TS=1 | faulting insn | no | |
| 4 | #SS (stack fault) | 12 | SS limit violation | faulting insn | yes | |
| 5 | #GP (general protection) | 13 | segment/limit/privilege | faulting insn | yes | |
| 6 | #PF (page fault) | 14 | page not present / protection | faulting insn | yes | CR2 = faulting addr |
| 7 | #AC (alignment check) | 17 | unaligned access with AC=1 | faulting insn | yes | 486+ |

### Traps (saved IP = next instruction)

| # | Exception | Vector | Trigger | Saved IP | Error code? | Notes |
|---|-----------|:------:|---------|:--------:|:-----------:|-------|
| 1 | #DB (debug) | 1 | TF=1 or DR match | next insn (TF) / faulting (DR exec) | no | split: TF trap, DR-exec fault |
| 2 | #BP (breakpoint) | 3 | INT 3 | next insn | no | |
| 3 | #OF (overflow) | 4 | INTO with OF=1 | next insn | no | |
| 4 | INT n (software interrupt) | n | INT n | next insn | no | |

### Error code push behavior

| # | Exception | Error code pushed? | Format | Notes |
|---|-----------|:------------------:|--------|-------|
| 1 | #DE, #UD, #NM, #DB, #BP, #OF | no | — | no error code |
| 2 | #SS, #GP, #PF, #AC | yes | 32-bit (386+) or 16-bit (286) | see format below |
| 3 | #DF (double fault) | yes (386+ only) | 0x00000000 always | 286 pushes garbage |

### Error code format

```
Bit  0   External (EXT) — set if exception was during INT handling
Bit  1   IDT — set if source is IDT entry (interrupt gate)
Bit  2   TI — set if source is LDT (0=GDT)
Bits 3-15  Selector index (for segment-related faults)
```

## Test Cases

### Fault vs trap classification

| # | Setup | Instruction | Saved IP location | Expected | Notes |
|---|-------|-------------|:-----------------:|----------|-------|
| 1 | DIV by zero | `div cx` (cx=0) | points to DIV insn | #DE, IP = faulting | fault |
| 2 | INT 3 | `int3` | points after INT3 | #BP, IP = next | trap |
| 3 | INTO with OF=1 | `into` | points after INTO | #OF, IP = next | trap |
| 4 | Illegal opcode | `db 0x0F, 0x0F` | points to illegal byte | #UD, IP = faulting | fault |

### Error code verification

| # | Exception | Error code | Expected value | Notes |
|---|-----------|:----------:|----------------|-------|
| 1 | #GP from null selector load | pushed | 0x0000 | selector index 0, no TI/IDT/EXT |
| 2 | #GP from segment limit | pushed | selector index | index of the bad selector |
| 3 | #SS from stack limit | pushed | 0x0000 | usually null selector or stack-related |
| 4 | #PF | pushed | U/S bit, W/R bit, P bit | reflects access type |
| 5 | #DF | pushed (386+) | 0x0000 | always zero |

### #PF error code bits

| Bit | Name | Meaning |
|:---:|------|---------|
| 0 | P | 0 = non-present page, 1 = protection violation |
| 1 | W/R | 0 = read, 1 = write |
| 2 | U/S | 0 = supervisor, 1 = user |
| 3 | RSVD | reserved bit set in PTE (PSE) |

| # | Setup | Access | Expected error code | Notes |
|---|-------|--------|:-------------------:|-------|
| 1 | P=0 page, CPL=0, read | supervisor read | 0x0 (P=0, R, S) | |
| 2 | P=0 page, CPL=3, read | user read | 0x4 (P=0, R, U) | |
| 3 | R/W=0 page, CPL=3, write | user write to RO | 0x7 (P=1, W, U) | protection violation |

### Double fault (#DF, vector 8)

| # | Setup | First fault | Second fault | Expected | Notes |
|---|-------|-------------|--------------|----------|-------|
| 1 | #DF handler installed; #GP handler faults (bad IDT) | #GP | #GP in handler | #DF | contributory double fault |
| 2 | #DF handler installed; #DE with bad stack (SS limit) | #DE | #SS in handler | #DF | contributory |
| 3 | #DE then benign fault | #DE | no second fault | just #DE | no double |

> **Double fault rules (386+):**
> - Two contributory faults (class 1: #DE, #UD, #NM, #SS, #GP, #PF) → #DF
> - Contributory fault + benign fault → first fault only
> - #DF itself → triple fault → system reset

### Triple fault

| # | Setup | Expected | Notes |
|---|-------|----------|-------|
| 1 | #DF handler faults; no valid #DF handler | system reset | observable as reboot; hard to test in guest |

> Triple fault is mostly observable only in simulation. On real hardware it causes
> a reset. See coverage-matrix note: "triple → reset is venue C."

## Pre/Post State (representative cases)

### #DE (divide by zero) — fault, saved IP = faulting instruction
PRE (PM32, CPL=0):
  EIP = 0x00001000  (address of `DIV CX` instruction)
  AX = 0x0010, CX = 0x0000
  ESP0 stack available
  IDT[0] → #DE handler at 0x00002000
OP:  DIV CX              ; divide by zero
POST:
  Exception frame on stack:
    [ESP+0x00] = EFLAGS
    [ESP+0x04] = CS = current CS
    [ESP+0x08] = EIP = 0x00001000  ← faulting instruction (restartable)
    (no error code for #DE)
  Handler runs at 0x00002000
  AX = 0x0010 (unchanged — DIV did not complete)

### INT 3 — trap, saved IP = next instruction
PRE:
  EIP = 0x00001000  (address of INT3)
  IDT[3] → #BP handler at 0x00003000
OP:  INT3                ; breakpoint trap
POST:
  Exception frame on stack:
    [ESP+0x00] = EFLAGS
    [ESP+0x04] = CS
    [ESP+0x08] = EIP = 0x00001001  ← NEXT instruction after INT3
    (no error code for #BP)

### #GP from null selector load — error code
PRE (PM32, CPL=0):
  EIP = 0x00001000  (address of `MOV DS, AX` where AX=0)
  AX = 0x0000   (null selector)
  DS = valid selector
  IDT[13] → #GP handler at 0x00004000
OP:  MOV DS, AX          ; load null selector into DS
POST:
  Exception frame on stack:
    [ESP+0x00] = EFLAGS
    [ESP+0x04] = CS
    [ESP+0x08] = EIP = 0x00001000  ← faulting instruction
    [ESP+0x0C] = 0x00000000        ← error code: index 0, no TI, no IDT, no EXT
  #GP triggered

### #PF error code — user write to read-only page
PRE (PM32, CPL=3, paging on):
  PTE for VA 0x08001000 = 0x00100005  (P=1, R/W=0 read-only, US=1 user)
  EIP = 0x00001000  (address of MOV [0x08001000], EAX)
  EAX = 0xDEADBEEF
  CR2 = stale
OP:  MOV [0x08001000], EAX   ; ring 3 write to RO page
POST:
  Exception frame on stack:
    [ESP+0x00] = EFLAGS
    [ESP+0x04] = CS
    [ESP+0x08] = EIP = 0x00001000  ← faulting instruction
    [ESP+0x0C] = 0x00000007        ← error code: P=1, W=1, U=1
  CR2 = 0x08001000  ← faulting linear address

### Double fault (#DF, vector 8)
PRE (PM32, CPL=0):
  #GP handler in IDT[13] points to not-present segment → #GP in handler
  IDT[8] → #DF handler at 0x00005000
OP:  (trigger #GP → handler faults with another #GP)
POST:
  #DF exception (vector 8)
  Exception frame on stack:
    [ESP+0x00] = EFLAGS
    [ESP+0x04] = CS
    [ESP+0x08] = EIP
    [ESP+0x0C] = 0x00000000  ← error code always zero for #DF (386+)
  ← If #DF handler itself faults → triple fault → system reset

### Error code format breakdown
```
Example: 0x00000007 (from #PF user write to present page)
  bit 0 (P)   = 1  ← page was present (protection violation)
  bit 1 (W/R) = 1  ← write access caused fault
  bit 2 (U/S) = 1  ← user mode (CPL=3)
  bits 3-31    = 0  ← no reserved bits set

Example: 0x00000000 (from null selector #GP)
  bit 0 (EXT) = 0  ← not external
  bit 1 (IDT) = 0  ← not from IDT
  bit 2 (TI)  = 0  ← GDT selector
  bits 3-15   = 0  ← selector index 0
```

## State Save/Restore

- **Save:** IDT entries for tested vectors; original IVT entries (real mode);
  GDT/LDT if modified
- **Restore:** restore IDT/IVT; restore any modified descriptors
- **CR2/CR3:** save/restore if page fault tests modified page tables

## Pass/Fail Criteria

- **PASS:** faults save faulting IP; traps save next IP; error codes pushed correctly;
  #PF error code bits match access type; double fault triggered correctly
- **FAIL:** wrong saved IP; missing/wrong error code; double fault not triggered
- **SKIP:** GEN < 80286 (exceptions less structured on 8086)

## Real Mode INT/Exception Return Address

### INT instruction (real mode)

| # | Instruction | Return CS:IP points to | Notes |
|---|-------------|:----------------------:|-------|
| 1 | INT n | next instruction | software INT is a trap |
| 2 | INT 3 | next instruction | breakpoint trap |
| 3 | INTO (OF=1) | next instruction | overflow trap |

### Hardware exceptions (real mode)

| # | Exception | Return CS:IP points to | Notes |
|---|-----------|:----------------------:|-------|
| 1 | DIV/IDIV #DE (8086) | **next instruction** | 8086 bug: not restartable |
| 2 | DIV/IDIV #DE (286+) | faulting instruction | 286+ corrected: restartable |
| 3 | Invalid opcode | faulting instruction | if detected (8086 had few) |

### 8086 #DE return address discrepancy

| CPU | #DE return IP | Consequence |
|-----|:-------------:|-------------|
| 8086/8088 | next instruction | cannot restart DIV |
| 80186+ | faulting DIV | restartable |
| 80286+ | faulting DIV | restartable |

### Test cases for return address

| # | CPU | Exception | Return IP | Action |
|---|-----|-----------|:---------:|--------|
| 1 | 8086 | #DE | verify = next insn | skip restart |
| 2 | 286+ | #DE | verify = DIV insn | restart possible |
| 3 | any | INT 3 | verify = next insn | trap |
| 4 | any | INT n | verify = next insn | trap |

### Pre/Post State — 8086 #DE return address

```
PRE (8086 real mode):
  CS:IP = 0x1000:0x0100  (DIV CX at this address)
  [0x1000:0x0100] = F7 F1   (DIV CX, 2 bytes)
  [0x1000:0x0102] = 90      (NOP, next instruction)
  AX = 0x0001, CX = 0x0000

  OP:  DIV CX   ; divide by zero

POST:
  INT 0 handler entered
  [SS:SP]   = FLAGS
  [SS:SP+2] = 0x1000   ; return CS
  [SS:SP+4] = 0x0102   ; return IP = NEXT insn (8086 bug)
  ← Cannot restart the DIV; must fail or skip
```

### Pre/Post State — 286+ #DE return address

```
PRE (286+ real mode):
  CS:IP = 0x1000:0x0100  (DIV CX at this address)
  [0x1000:0x0100] = F7 F1   (DIV CX, 2 bytes)
  [0x1000:0x0102] = 90      (NOP, next instruction)
  AX = 0x0001, CX = 0x0000

  OP:  DIV CX   ; divide by zero

POST:
  INT 0 handler entered
  [SS:SP]   = FLAGS
  [SS:SP+2] = 0x1000   ; return CS
  [SS:SP+4] = 0x0100   ; return IP = faulting DIV (286+ fix)
  ← Can fix the problem and restart
```

### Handler verification code

```nasm
; Verify return address in real mode INT handler
int0_handler:
    push bp
    mov bp, sp
    ; [BP+2] = return IP
    ; [BP+4] = return CS
    ; [BP+6] = saved FLAGS
    
    mov ax, [bp+2]       ; return IP
    cmp ax, div_insn_addr
    je .is_fault_ip      ; 286+: restartable fault
    cmp ax, after_div_addr
    je .is_trap_ip       ; 8086: non-restartable (trap-like)
    ; else: unexpected value
    
.is_fault_ip:
    ; Handler can skip the DIV by adding 2 to return IP
    add word [bp+2], 2
    pop bp
    iret

.is_trap_ip:
    ; Already past DIV, nothing to skip
    pop bp
    iret
```

## Known Divergences

- **286 error codes:** 286 pushes 16-bit error codes; 386+ pushes 32-bit (zero-extended).
- **#DF on 286:** always pushes garbage error code. 386+ pushes 0x0000.
- **#DB saved IP:** TF trap saves next instruction; data breakpoint saves faulting;
  execution breakpoint is a trap (next instruction). Mixed semantics.
- **NMI and #DF:** NMI during a fault handler is not a double fault condition.
- **8086 #DE:** pushes next-instruction address (non-restartable); 286+ fixed this.

## NOT TESTED (deferred)

- Triple fault detection (→ co-sim, causes reset)
- Exception during NMI handler
- Exception during double-fault handler (triple fault)
