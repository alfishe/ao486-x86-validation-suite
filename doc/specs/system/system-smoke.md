# Spec: System Smoke Test (BIOS & Environment Sanity)

## Metadata
- **Source file:** `src/system/smoke.asm`
- **TIER:** REALMODE | VENUE: G | GEN: 8086+ | ORACLE: manual
- **Impl-plan:** Phase 8, Level 0
- **Coverage:** [§10](../../coverage-matrix.md#10-system-integration-pri-1--uniquely-guest-observable)

## Purpose

Detect and validate the basic MS-DOS / BIOS environment tailored for the ao486 MiSTer core (which uses Bochs BIOS and a custom VGA BIOS). Before executing system-level tests that modify the IDT, GDT, or A20 line, we must verify that the base environment is stable and that standard BIOS vectors are hooked.

## Detection Methods

### 0. IVT Sanity (must run first)
```nasm
; Verify critical IVT entries are hooked before calling them
    xor ax, ax
    mov ds, ax
    
    ; Check INT 10h (video)
    mov ax, [0x0040]    ; INT 10h offset
    or ax, [0x0042]     ; INT 10h segment
    jz .no_video_bios   ; both zero = not hooked
    
    ; Check INT 1Ah (timer)
    mov ax, [0x0068]    ; INT 1Ah offset
    or ax, [0x006A]     ; INT 1Ah segment
    jz .no_timer_bios
```

### 1. BIOS Data Area (BDA) Sanity
```nasm
; Read BDA at 0040:0000 to verify RAM structure
    mov ax, 0x0040
    mov ds, ax
    
    ; Equipment word (40:10)
    mov ax, [0x0010]    ; BDA 40:10 = equipment word
    ; Bits 4-5 = initial video mode (01=40col, 10=80col, 11=mono)
    ; Should be non-zero for VGA system
    
    ; Base memory size (40:13)
    mov ax, [0x0013]    ; BDA 40:13 = Base memory size in KB
    ; Expected: usually 0x0280 (640KB) for ao486 MS-DOS
```

### 2. INT 10h (Video) Sanity
```nasm
; Get current video mode
    mov ah, 0x0F
    int 0x10
    ; Expected: AL = video mode (usually 03h for text mode), AH = columns
```

### 3. INT 1Ah (Timer) Sanity
```nasm
; Read system timer counter
    mov ah, 0x00
    int 0x1A
    ; Expected: CX:DX = tick count, CF = 0
```

### 4. INT 13h (Disk) Sanity
```nasm
; Get drive parameters for drive 0x80 (HDD C:)
    mov ah, 0x08
    mov dl, 0x80
    int 0x13
    ; Expected: CF = 0 (success if HDD present), CH = max cylinder, DH = max head
```

## Test Cases

| # | Subsystem | Action | Expected | Notes |
|---|-----------|--------|----------|-------|
| 0 | IVT | Check IVT[10h] != 0 | segment:offset non-zero | Must pass before INT 10h |
| 1 | IVT | Check IVT[1Ah] != 0 | segment:offset non-zero | Must pass before INT 1Ah |
| 2 | BDA | Read word at 0040:0010 | bits 4-5 != 00 | Equipment word, video mode |
| 3 | BDA | Read word at 0040:0013 | >= 0x0100 (256KB) | ao486 typical: 0x0280 |
| 4 | INT 10h | AH=0x0F (Get Video Mode) | AL=0x03, AH>=80 | Confirms VGA BIOS |
| 5 | INT 1Ah | AH=0x00 (Read Timer) | CF=0 | Confirms timer tick |
| 6 | INT 13h | AH=0x08, DL=0x80 (Drive Parm) | CF=0 or warn | HDD optional |

## Pre/Post State

### INT 10h Video Sanity
```
PRE:
  System running in real mode.
  VGA BIOS active.

OP:  MOV AH, 0x0F
     INT 0x10

POST:
  AL = Current video mode (typically 0x03 for DOS text mode).
  AH = Number of character columns (typically 80).
  BH = Active display page.
```

## Timing Tolerances

| Operation | Timeout | Notes |
|-----------|:-------:|-------|
| IVT/BDA read | immediate | memory access, no timeout needed |
| INT 10h | 1s | should return in microseconds |
| INT 1Ah | 1s | should return in microseconds |
| INT 13h | 5s | disk access may take longer |

> If any INT call hangs beyond timeout, the environment is broken — abort smoke test.

## Pass/Fail Criteria

- **PASS:** IVT entries hooked; BDA contains reasonable memory values; INT 10h/1Ah execute without crashing and return expected success flags.
- **FAIL:** IVT[10h] or IVT[1Ah] = 0:0; system hang; invalid video mode (AL=0); CF=1 on timer read; equipment word video bits = 00.
- **WARN:** INT 13h returns CF=1 (no HDD) — logged but not a failure.
- **SKIP:** If running as a Linux/Win32 `UNIVERSAL` build (this test requires `REALMODE` DOS environment).

## Known Divergences

- **Hard Drive Presence:** If booting from a floppy on ao486 without an HDD mounted, INT 13h DL=0x80 will return CF=1 (Error). The test should gracefully handle CF=1 by logging a warning rather than failing the smoke test, as the suite can still run from a floppy.
- **Bochs BIOS specific:** The ao486 core uses a Bochs-derived BIOS. BDA variables (like equipment word at 40:10) will reflect the specific Bochs BIOS hardware strapping.
