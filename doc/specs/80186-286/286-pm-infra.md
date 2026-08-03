# Spec: 286 PM Infrastructure

## Metadata
- **Source file:** `src/cpu/80286/pm_infra.asm`
- **TIER:** RING0 | VENUE: G | GEN: 80286+ | ORACLE: manual
- **Impl-plan:** Phase 4, area `286-PM`
- **Coverage:** [§6](../../coverage-matrix.md#6-cpu--80286-pri-1-for-pm-the-first-big-divergence-surface)
- **Divergences:** [prep-analysis §2](../../prep-analysis.md#2-protected-mode--paging--full-check-matrix), [§1.2a](../../prep-analysis.md#12a-generation-specific-divergences-286-vs-386-vs-486)
- **Pattern:** [adding-tests.md "RING0 Self-Switching"](../../adding-tests.md#ring0-self-switching-pm-pattern)

## Purpose

Establish the PM entry/exit infrastructure that all subsequent PM test
modules depend on.  This is the most critical infrastructure module —
without it, no PM tests can run.

## Shared PM Infrastructure (built in this module)

### GDT Layout

```
GDT_BASE:
    dq 0                    ; null descriptor (selector 0x0000)
    ; --- code segment, ring 0 ---
    dw 0xFFFF               ; limit low (4GB with G=1 on 386+, 64KB on 286)
    dw 0x0000               ; base low
    db 0x00                 ; base mid
    db 0x9A                 ; access: P=1, DPL=0, S=1, type=code exec/read
    db 0x0F                 ; gran: G=0(286)/1(386+), D/B=1, limit high=0xF
    db 0x00                 ; base high
    ; --- data segment, ring 0 ---
    dw 0xFFFF
    dw 0x0000
    db 0x00
    db 0x92                 ; access: P=1, DPL=0, S=1, type=data read/write
    db 0x0F
    db 0x00
    ; --- code segment, ring 3 (if 386+) ---
    dw 0xFFFF
    dw 0x0000
    db 0x00
    db 0xFA                 ; access: P=1, DPL=3, S=1, type=code
    db 0x0F
    db 0x00
    ; --- data segment, ring 3 (if 386+) ---
    dw 0xFFFF
    dw 0x0000
    db 0x00
    db 0xF2                 ; access: P=1, DPL=3, S=1, type=data
    db 0x0F
    db 0x00
    ; --- TSS descriptor ---
    dw TSS_SIZE - 1         ; limit
    dw TSS_BASE_LO
    db TSS_BASE_MID
    db 0x89                 ; access: P=1, DPL=0, type=386 TSS (available)
    db 0x00                 ; gran
    db TSS_BASE_HI
```

### Selector Definitions

```
CODE_SEL0    equ 0x08      ; GDT entry 1, ring 0 code
DATA_SEL0    equ 0x10      ; GDT entry 2, ring 0 data
CODE_SEL3    equ 0x18 | 3  ; GDT entry 3, ring 3 code (RPL=3)
DATA_SEL3    equ 0x20 | 3  ; GDT entry 4, ring 3 data (RPL=3)
TSS_SEL      equ 0x28      ; GDT entry 5, TSS
```

### PM Entry Sequence

```nasm
; --- Load GDT ---
    lgdt [gdtr]
; --- Enter PM ---
    mov eax, cr0
    or eax, CR0_PE          ; set Protection Enable
    mov cr0, eax
; --- Far jump to flush prefetch and load CS ---
    jmp dword CODE_SEL0:pm_entry

pm_entry:
    ; Now in 32-bit protected mode (386+) or 16-bit PM (286)
    mov ax, DATA_SEL0       ; load data segments
    mov ds, ax
    mov es, ax
    mov fs, ax              ; 386+ only
    mov gs, ax              ; 386+ only
    mov ss, ax
    mov esp, PM_STACK_TOP
; --- Load TSS (for task switching tests) ---
    ltr TSS_SEL
; --- Load IDT ---
    lidt [idtr]
; --- Now PM infrastructure is ready ---
```

### PM Exit Sequence (386+ only)

```nasm
; --- Must be in ring 0 ---
    cli
    ; Reset DS/ES/SS to flat data selector with 16-bit limit
    ; (or use a 16-bit data selector for the transition)
    mov ax, DATA_SEL0
    mov ds, ax
    mov es, ax
    mov ss, ax
    ; Disable paging (if enabled)
    mov eax, cr0
    and eax, ~CR0_PG
    mov cr0, eax
    ; Clear PE
    and eax, ~CR0_PE
    mov cr0, eax
    ; Far jump to real mode code
    jmp 0x0000:rm_entry

rm_entry:
    ; Now in real mode
    ; Reload segment registers with real-mode values
    mov ax, 0x0000
    mov ds, ax
    ; ... restore IDT, etc.
```

> **286 cannot exit PM to real mode via software.** The 286 PM→RM transition
> requires a keyboard controller reset (port 0x64, command 0xFE) or a
> triple-fault. This is documented in prep-analysis §1.2a.

## Test Cases

### PM entry from real mode

| # | Action | Expected | Notes |
|---|--------|----------|-------|
| 1 | LGDT + LMSW(PE) + far JMP | CS=CODE_SEL0, CPL=0 | basic entry |
| 2 | Load DS/ES/SS after entry | segment regs = DATA_SEL0 | |
| 3 | LTR TSS_SEL | TR loaded, no exception | |

### PM exit (386+ only)

| # | Action | Expected | Notes |
|---|--------|----------|-------|
| 1 | Clear PG, then clear PE, far JMP | back in real mode | 386+ |

### Exception handler installation

| # | Exception | IDT entry | Gate type | Notes |
|---|-----------|:---------:|-----------|-------|
| 1 | #GP (13) | 13 | 386 trap gate (0x8F) or int gate (0x8E) | |
| 2 | #UD (6) | 6 | 386 int gate | |
| 3 | #PF (14) | 14 | 386 int gate (386+) | |
| 4 | IRQ0-15 | 0x20-0x2F | 386 int gate | PIC remapped |

### Verify CPL

| # | Test | Expected | Notes |
|---|------|----------|-------|
| 1 | Read CS selector | RPL=0, DPL=0 | CPL = DPL of current CS |

## Pre/Post State (representative cases)

### PM entry — CR0 transition

```
PRE (real mode):
  CR0 = 0x----0010  (PE=0, MP=1)
  CS = real-mode segment (base = CS << 4)
  GDT loaded via LGDT but not yet active

  OP:  MOV EAX, CR0
        OR EAX, 1            (set PE bit)
        MOV CR0, EAX
        JMP far CODE_SEL0:pm_entry   (far jump flushes prefetch)

POST:
  CR0 = 0x----0011  (PE=1)
  CS = 0x08 (CODE_SEL0), CPL=0
  CS hidden cache: loaded from GDT entry 1
    base=0x00000000, limit=0xFFFFFFFF (386+ with G=1)
  Execution continues at pm_entry in PM
```

### Segment register load after PM entry

```
PRE (just entered PM32):
  DS = real-mode value (stale cache)
  AX = 0x10 (DATA_SEL0)

  OP:  MOV DS, AX

POST:
  DS = 0x10  (selector)
  DS hidden cache: base=0x00000000, limit=0xFFFFFFFF, access=0x92
  (flat data segment covering all 4GB on 386+)
```

### PM exit (386+ only) — CR0 transition back

```
PRE (PM32, CPL=0):
  CR0 = 0x----0011  (PE=1, MP=1)
  Paging disabled (PG=0)

  OP:  CLI
        MOV AX, DATA_SEL0
        MOV DS, AX ; MOV ES, AX ; MOV SS, AX   (reload with 16-bit friendly selector)
        MOV EAX, CR0
        AND EAX, ~1           (clear PE)
        MOV CR0, EAX
        JMP 0x0000:rm_entry   (far jump to real-mode CS)

POST:
  CR0 = 0x----0010  (PE=0)
  CS = 0x0000 (real mode)
  DS/ES/SS = 0x0000 (must reload in real mode)
  Back in real mode
```

### TSS load via LTR

```
PRE (PM32, CPL=0):
  TR = stale/zero
  GDT entry TSS_SEL (0x28): type=0x89 (available 386 TSS)
    base=TSS_BASE, limit=TSS_SIZE-1

  OP:  LTR AX    where AX = 0x28

POST:
  TR = 0x28
  TR hidden cache: loaded from GDT
  TSS descriptor: type changes 0x89 → 0x0B (busy TSS)
  (TSS marked busy to prevent re-entry)
```

## State Save/Restore

- **Save:** CR0, GDT register, IDT register, all segment regs, TR
- **Restore:** restore real-mode IDT (IVT), segment regs, CR0 (clear PE)
- **Critical:** The 286 PM→RM transition is destructive (reset). Design tests
  so that all PM tests run before exiting PM. Or use triple-fault to reset.

## Known Divergences

| Behavior | 286 | 386+ | Action |
|----------|------|------|--------|
| PM exit | reset only | `MOV CR0, ~PE` | 286 uses keyboard reset |
| G bit | absent | present | 286 limit is 16-bit max |
| FS/GS | absent | present | 386+ only |
| 32-bit ops | absent | present | 386+ only |

## Pass/Fail Criteria

- **PASS:** PM entry succeeds; all segment regs loaded; exceptions catchable
- **FAIL:** #GP during PM entry or segment load
- **SKIP:** GEN < 80286
