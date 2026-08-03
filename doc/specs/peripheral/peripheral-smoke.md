# Spec: Peripheral Smoke Test (Presence Detection)

## Metadata
- **Source file:** `src/peripheral/smoke.asm`
- **TIER:** HARDWARE | VENUE: G | GEN: 8086+ | ORACLE: manual
- **Impl-plan:** Phase 1, Level 0
- **Coverage:** [§9](../../coverage-matrix.md#9-peripherals-pri-12--the-projects-least-duplicated-coverage)

## Purpose

Quick presence detection for PC peripherals before running detailed peripheral
tests. Each peripheral is probed with a non-destructive read or register
round-trip to confirm it exists and responds.

## Detection Methods

### PIC (8259)
```nasm
; Read IRR — should return some value
    mov al, 0x0A        ; OCW3: read IRR
    out 0x20, al
    in al, 0x20         ; read IRR
    ; If bus floats (0xFF) or times out → no PIC
```

### PIT (8254)
```nasm
; Read-back channel 0 status
    mov al, 0xE2        ; read-back: CH0, status only
    out 0x43, al
    in al, 0x40         ; read status byte
    ; Bits 6-7 indicate mode; if valid → PIT present
```

### RTC (MC146818)
```nasm
; Read Status A
    mov al, 0x0A
    out 0x70, al
    in al, 0x71
    ; Check divider bits (4-6) are reasonable (010 = normal)
```

### KBC (8042)
```nasm
; Read status register
    in al, 0x64
    ; If timeout/bus float (0xFF) → no KBC
    ; Check bits 0-1 (OBF, IBF) are reasonable
```

### DMA (8237)
```nasm
; Read DMA1 status register
    in al, 0x08
    ; Upper 4 bits = TC flags, lower 4 = request flags
    ; If bus floats (0xFF) continuously → no DMA
```

## Test Cases

| # | Peripheral | Port | Test | Present if |
|---|------------|:----:|------|------------|
| 1 | PIC1 | 0x20 | read IRR | != 0xFF, stable |
| 2 | PIC2 | 0xA0 | read IRR | != 0xFF, stable |
| 3 | PIT | 0x43/0x40 | read-back status | bits 6-7 valid mode |
| 4 | RTC | 0x70/0x71 | read Status A | divider = 010 |
| 5 | KBC | 0x64 | read status | != 0xFF |
| 6 | DMA1 | 0x08 | read status | != 0xFF, stable |
| 7 | DMA2 | 0xD0 | read status | != 0xFF, stable |

## Pre/Post State

### PIC presence check
```
PRE:
  PIC state = unknown

OP:  MOV AL, 0x0A       ; OCW3: read IRR
     OUT 0x20, AL
     IN AL, 0x20        ; read IRR
     MOV BL, AL
     IN AL, 0x20        ; read again
     CMP AL, BL         ; should be stable

POST:
  If AL == BL and AL != 0xFF → PIC present
  If AL == 0xFF or unstable → PIC absent or broken
```

### PIT presence check
```
PRE:
  PIT state = unknown

OP:  MOV AL, 0xE2       ; read-back CH0
     OUT 0x43, AL
     IN AL, 0x40        ; status byte

POST:
  Bits 6-7 = mode (0-5 valid)
  If valid mode → PIT present
  If 0xFF or invalid → PIT absent
```

### RTC presence check
```
PRE:
  RTC state = unknown

OP:  MOV AL, 0x0A
     OUT 0x70, AL
     IN AL, 0x71

POST:
  Bits 4-6 (DV) should be 010 (normal divider)
  If DV = 010 → RTC present
  If 0xFF or DV invalid → RTC absent
```

## Pass/Fail Criteria

- **PASS:** peripheral responds with valid, stable data
- **FAIL:** timeout, bus float (0xFF), or invalid data
- **SKIP:** if peripheral not required for current test scope

## Peripheral Presence Matrix

| Peripheral | PC/XT | AT | ao486 | Required |
|------------|:-----:|:--:|:-----:|:--------:|
| PIC1 | yes | yes | yes | always |
| PIC2 | no | yes | yes | AT+ |
| PIT | yes | yes | yes | always |
| RTC | no | yes | yes | AT+ |
| KBC | no | yes | yes | AT+ |
| DMA1 | yes | yes | yes | always |
| DMA2 | no | yes | yes | AT+ |

## Known Divergences

- **XT vs AT:** XT lacks PIC2, RTC, KBC, DMA2. Smoke test should detect and
  report which peripherals are present.
- **Bus float:** absent I/O ports may return last bus value, not necessarily 0xFF.
  Multiple reads and stability check recommended.
