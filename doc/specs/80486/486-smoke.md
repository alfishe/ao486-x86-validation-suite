# Spec: 80486 Smoke Test (CPU Detection)

## Metadata
- **Source file:** `src/cpu/80486/smoke.asm`
- **TIER:** UNIVERSAL | VENUE: G | GEN: 80486+ | ORACLE: manual
- **Impl-plan:** Phase 1, Level 0
- **Coverage:** [§8](../../coverage-matrix.md#8-cpu--80387--80486-pri-12)

## Purpose

Detect 80486+ CPU presence. The 486 introduced EFLAGS bit 18 (AC, Alignment Check).
On 386, bit 18 is reserved and always reads as 0. On 486+, it can be toggled.

## Detection Method

```nasm
; Toggle EFLAGS.AC (bit 18)
    pushfd
    pop eax
    mov ebx, eax        ; save original
    xor eax, 0x40000    ; flip AC bit (bit 18)
    push eax
    popfd
    pushfd
    pop eax
    xor eax, ebx        ; compare with original
    and eax, 0x40000    ; isolate AC bit
    ; If EAX == 0 → 386 (bit 18 stuck)
    ; If EAX != 0 → 486+ (bit 18 toggled)
```

## Test Cases

| # | Test | 386 result | 486+ result | Detection |
|---|------|------------|-------------|-----------|
| 1 | Toggle EFLAGS.AC | stays 0 | toggles | 486+ if bit changes |
| 2 | XADD instruction | #UD | executes | 486+ if no fault |
| 3 | BSWAP instruction | #UD | executes | 486+ if no fault |
| 4 | CMPXCHG instruction | #UD | executes | 486+ if no fault |

## Pre/Post State

### EFLAGS.AC toggle detection
```
PRE (PM32 or real mode with 32-bit override):
  EFLAGS.AC = 0

OP:  PUSHFD
     POP EAX
     MOV EBX, EAX
     XOR EAX, 0x40000   ; flip bit 18
     PUSH EAX
     POPFD
     PUSHFD
     POP EAX
     XOR EAX, EBX
     AND EAX, 0x40000

POST (386):
  EAX = 0x00000000   ← bit 18 could not be toggled
  → CPU is 386

POST (486+):
  EAX = 0x00040000   ← bit 18 toggled successfully
  → CPU is 486+
```

### BSWAP detection
```
PRE (real mode or PM32):
  INT 6 handler installed
  EAX = 0x12345678

OP:  BSWAP EAX          ; 0F C8

POST (386):
  INT 6 triggered → CPU is 386

POST (486+):
  EAX = 0x78563412 (bytes reversed)
  → CPU is 486+
```

### CMPXCHG detection
```
PRE:
  INT 6 handler installed
  EAX = 0x00000001
  EBX = 0x00000001
  ECX = 0x00000002

OP:  CMPXCHG EBX, ECX   ; 0F B1 CB

POST (386):
  INT 6 triggered → CPU is 386

POST (486+):
  EBX = 0x00000002 (exchanged, since EAX == old EBX)
  ZF = 1
  → CPU is 486+
```

## Pass/Fail Criteria

- **PASS:** detection method correctly identifies CPU as 386 vs 486+
- **FAIL:** misdetection
- **SKIP:** never (this is the gate for all 486+ tests)

## Known Divergences

- **486SX vs 486DX:** both detected as 486+; 486SX lacks integrated FPU.
- **CPUID availability:** early 486 (pre-April 1993) lack CPUID; later 486 and
  Pentium have it. Use EFLAGS.ID (bit 21) toggle to detect CPUID support.
- **ao486:** implements 486DX-class features; should pass all detection tests.
