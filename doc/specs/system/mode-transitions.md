# Spec: Mode Transitions (Real↔PM↔V86, Unreal Mode)

## Metadata
- **Source file:** `src/core/modetrans.asm`
- **TIER:** RING0 | VENUE: G | GEN: 80286+ | ORACLE: manual
- **Impl-plan:** Phase 8, area `Mode`
- **Coverage:** [§10](../../coverage-matrix.md#10-system-integration-pri-1--uniquely-guest-observable)
- **Detail:** [prep-analysis §1.2a](../../prep-analysis.md#12a-generation-specific-divergences-286-vs-386-vs-486)
- **Refs:** [references.md](../../references.md) — Intel 80386 PRM; 80286 PRM

## Purpose

Verify CPU mode transition sequences: real → PM entry, PM → real exit (386+ only;
286 requires reset), PM ↔ V86 transitions, and unreal mode (big real mode) persistence.

## Prerequisites

- [286-pm-infra.md](../80186-286/286-pm-infra.md) — GDT layout, selectors, PM entry/exit
- [paging.md](../80386/paging.md) — paging setup for PM32
- [v86.md](../80386/v86.md) — V86 entry/exit and IOPL sensitivity

## Test Cases

### Real → PM entry (286/386)

| # | Action | Expected | Notes |
|---|--------|----------|-------|
| 1 | Build GDT; LGDT | GDT loaded | GDTR.base = GDT address |
| 2 | `mov eax, cr0; or eax, 1; mov cr0, eax` | PE bit set | CR0.PE=1 |
| 3 | Far JMP to PM code selector (flush pipeline) | CS = code selector, CPL=0 | |
| 4 | Load data segment registers (DS, ES, SS) from GDT | valid PM selectors | |
| 5 | Load task register (LTR) or set up stack | | |

> See [286-pm-infra.md](../80186-286/286-pm-infra.md) for the exact GDT layout and
> selector definitions.

### PM → Real exit

| # | CPU gen | Method | Expected | Notes |
|---|---------|--------|----------|-------|
| 1 | 386+ | Clear PG → far JMP → clear PE → far JMP to real-mode CS | back in real mode | software exit |
| 2 | 286 | Cannot exit PM via software | must use KBC reset or triple-fault | 286 limitation |

**386+ exit sequence:**

```
; 1. Disable paging (if enabled)
mov  eax, cr0
and  eax, 0x7FFFFFFF    ; clear PG
mov  cr0, eax
; 2. Far JMP to flush TLB
jmp  selector:offset
; 3. Clear PE
mov  eax, cr0
and  eax, ~1            ; clear PE
mov  cr0, eax
; 4. Far JMP to real-mode segment
jmp  0xFFFF:real_handler
```

### 16-bit PM ↔ 32-bit PM

| # | Transition | Method | Expected | Notes |
|---|-----------|--------|----------|-------|
| 1 | PM16 → PM32 | Far JMP to 32-bit code segment (D=1) | EIP 32-bit, 32-bit operands | operand-size prefix |
| 2 | PM32 → PM16 | Far JMP to 16-bit code segment (D=0) | IP 16-bit, 16-bit operands | |

### PM → V86 entry (386+)

| # | Action | Expected | Notes |
|---|--------|----------|-------|
| 1 | Build IRET stack frame with EFLAGS.VM=1 | push SS, ESP, EFLAGS(VM=1), CS, EIP | |
| 2 | IRET with VM=1 in stacked EFLAGS | enters V86 mode | CPL becomes 3, IOPL matters |

> See [v86.md](../80386/v86.md) for V86 IOPL sensitivity and monitor pattern.

### V86 → PM exit (386+)

| # | Trigger | Expected | Notes |
|---|---------|----------|-------|
| 1 | V86 executes sensitive insn (INT, CLI, etc.) with IOPL<3 | #GP fault, handler in PM | V86 monitor |
| 2 | IRET from PM handler with VM=0 | returns to PM | |

### Unreal mode (big real mode)

| # | Step | Expected | Notes |
|---|------|----------|-------|
| 1 | Enter PM temporarily | PE=1 | |
| 2 | Load DS/ES/SS with a 4GB data segment (limit=0xFFFFFFFF, granular) | base=0, limit=4GB | |
| 3 | Exit PM back to real mode | PE=0, but segment cache retains large limit | |
| 4 | Access memory above 1MB in real mode | works (segment cache still has 4GB limit) | "unreal" mode |

> **Unreal mode trick:** the segment descriptor cache retains the PM limit after
> switching back to real mode. This allows 32-bit addressing in real mode (used by
> HIMEM.SYS and DOS extenders). The cache is per-segment-register; each must be loaded
> in PM before returning to real mode.

### Unreal mode persistence

| # | Action | Expected | Notes |
|---|--------|----------|-------|
| 1 | Load DS in PM, return to real, access 0x100000 | works | DS cache has 4GB limit |
| 2 | Load only DS in PM, try ES access to 0x100000 | FAILS if ES not loaded in PM | per-register |
| 3 | Far JMP after returning to real | segment reloaded, cache cleared | unreal lost |

## Pre/Post State (representative cases)

### Real → PM entry (386+)
PRE (real mode):
  CR0 = 0x00000010   (PE=0, ET=1 only; real mode)
  CS = 0x0000 (real-mode segment)
  GDT at 0x00080000:
    [0x08] = code segment: base=0, limit=0xFFFFF, D=1 (32-bit), type=0x9A
    [0x10] = data segment: base=0, limit=0xFFFFF, D=1 (32-bit), type=0x92
  GDTR.base = 0x00080000, GDTR.limit = 0x3F
OP:  LGDT [gdtr_ptr]        ; load GDT register
     MOV EAX, CR0
     OR  EAX, 0x00000001     ; set PE bit
     MOV CR0, EAX            ; CR0 = 0x00000011
     JMP DWORD 0x0008:pm_entry  ; far jump flushes prefetch queue
POST (PM32):
  CR0 = 0x00000011   (PE=1)
  CS = 0x0008, base=0, limit=0xFFFFF, D=1
  EIP = pm_entry (32-bit)
  ← Must load DS/ES/SS from GDT immediately

### PM → Real exit (386+)
PRE (PM32, no paging):
  CR0 = 0x00000011   (PE=1)
  CS = 0x0008 (PM code selector)
OP:  MOV EAX, CR0
     AND EAX, 0x7FFFFFFE     ; clear PG and PE
     MOV CR0, EAX            ; CR0 = 0x00000010
     JMP 0xFFFF:real_handler ; far jump to real-mode segment
POST (real mode):
  CR0 = 0x00000010   (PE=0, ET=1)
  CS = 0xFFFF (real-mode segment, base = 0xFFFF0)
  ← Segment registers now use real-mode addressing (base = selector × 16)
  ← IDTR may still point to IDT; must reload with real-mode IVT (lidt)

### PM → V86 entry via IRET
PRE (PM32, CPL=0):
  CR0 = 0x00000011   (PE=1)
  EFLAGS = 0x00000002  (VM=0)
  Ring 0 stack frame prepared:
    [ESP+0x00] = V86_EIP      (target in V86 code)
    [ESP+0x04] = V86_CS       (real-mode segment, e.g., 0x0000)
    [ESP+0x08] = 0x00020002   (EFLAGS with VM=1 bit17)
    [ESP+0x0C] = V86_ESP
    [ESP+0x10] = V86_SS
OP:  IRETD
POST (V86 mode):
  EFLAGS = 0x00020002  (VM=1)
  CS = V86_CS, base = V86_CS × 16  (real-mode addressing)
  EIP = V86_EIP
  CPL = 3 effectively
  ← Paging still active; V86 runs at user privilege

### Unreal mode setup
PRE (real mode → PM → real):
  CR0 = 0x00000010   (real mode)
  DS cache: base=0, limit=0xFFFF (real-mode 64K)
OP:
  ; Step 1: Enter PM temporarily
  LGDT [gdtr_ptr]
  MOV EAX, CR0
  OR  EAX, 1
  MOV CR0, EAX
  JMP DWORD 0x0008:pm_start

  ; Step 2: Load DS with 4GB flat data segment
  MOV AX, 0x0010   ; GDT entry: base=0, limit=0xFFFFFFFF, G=1, D=1
  MOV DS, AX       ; DS cache now has 4GB limit

  ; Step 3: Exit PM back to real mode
  MOV EAX, CR0
  AND EAX, ~1
  MOV CR0, EAX
  JMP 0x0000:real_back
POST (unreal mode):
  CR0 = 0x00000010   (PE=0, real mode)
  DS selector = whatever, but DS cache retains 4GB limit
  DS:offset can now access any 32-bit address in real mode
  ← If far JMP reloads CS, or if DS is reloaded via MOV DS,AX in real mode,
    the cache is reset to 64K and unreal mode is lost

### Unreal mode persistence — access above 1MB
PRE (unreal mode, DS cache = 4GB limit):
  DS = 0x0000, but cache has base=0, limit=0xFFFFFFFF
  Memory at physical 0x00100000 = 0x42
OP:  MOV EAX, 0x00100000
     MOV BL, [DS:EAX]    ; 32-bit addressing in real mode
POST:
  BL = 0x42             ← access to 1MB+ succeeded without A20 or PM
  ← This works because DS cache still has the PM-era 4GB limit

## State Save/Restore

- **Save:** CR0, CR3 (if paging), EFLAGS, GDTR, IDTR, TR, LDTR, all segment registers
- **Restore:** restore CR0/CR3; reload GDTR/IDTR; restore original mode
- **Note:** restoring real mode after PM on 286 requires special handling (reset path)

## Pass/Fail Criteria

- **PASS:** PM entry/exit works; V86 entry/exit works; unreal mode persists; 16/32-bit
  PM transitions correct
- **FAIL:** PM exit hangs (286); unreal mode doesn't persist; V86 not entered
- **SKIP:** V86 tests on GEN<80386; unreal mode on GEN<80386

## Known Divergences

- **286 PM exit:** cannot exit PM via software. Must use KBC reset (port 0x64, cmd 0xFE)
  or triple-fault. This is architecturally impossible to avoid.
- **Unreal mode:** behavior is CPU-implementation-specific (relies on descriptor cache
  not being flushed). Works on 386+ but not guaranteed by the architecture.
- **V86 IOPL:** sensitive instruction behavior depends on IOPL. See
  [v86.md](../80386/v86.md) for the full IOPL sensitivity matrix.
