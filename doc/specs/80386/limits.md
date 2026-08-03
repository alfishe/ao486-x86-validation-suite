# Spec: 386 Segment Limit Enforcement (32-bit + Granularity)

## Metadata
- **Source file:** `src/cpu/80386/limits.asm`
- **TIER:** RING0 | VENUE: G | GEN: 80386+ | ORACLE: manual
- **Impl-plan:** Phase 5, area `386-Limit`
- **Coverage:** [§7](../../coverage-matrix.md#7-cpu--80386-pri-1-32-bit--paging--v86)
- **Prerequisite:** [286-limit.md](../80186-286/286-limit.md)

## Purpose

Verify 386 segment limit enforcement with:
- 32-bit limits (up to 4GB)
- Granularity bit (G): byte vs 4KB page granularity
- Expand-down segments
- Big/Default bit (D/B) interaction

## Segment Descriptor Limit Fields

```
Descriptor (8 bytes):
  Bytes 0-1: Limit [15:0]
  Byte 6 bits 0-3: Limit [19:16]
  Byte 6 bit 7: G (granularity) — 0=byte, 1=4KB page

Effective limit calculation:
  If G=0: effective_limit = limit_field (0 to 0xFFFFF = 1MB)
  If G=1: effective_limit = (limit_field << 12) | 0xFFF (up to 4GB)
```

## Test Cases

### Byte granularity (G=0)

| # | Limit field | Effective limit | Access at | Expected |
|---|:-----------:|:---------------:|:---------:|----------|
| 1 | 0x00000 | 0 | offset 0 | OK (1 byte segment) |
| 2 | 0x00000 | 0 | offset 1 | #GP |
| 3 | 0x000FF | 255 | offset 255 | OK |
| 4 | 0x000FF | 255 | offset 256 | #GP |
| 5 | 0xFFFFF | 1,048,575 | offset 0xFFFFF | OK |
| 6 | 0xFFFFF | 1,048,575 | offset 0x100000 | #GP |

### Page granularity (G=1)

| # | Limit field | Effective limit | Access at | Expected |
|---|:-----------:|:---------------:|:---------:|----------|
| 1 | 0x00000 | 0x00000FFF (4KB-1) | offset 0x0FFF | OK |
| 2 | 0x00000 | 0x00000FFF | offset 0x1000 | #GP |
| 3 | 0x00001 | 0x00001FFF (8KB-1) | offset 0x1FFF | OK |
| 4 | 0x00001 | 0x00001FFF | offset 0x2000 | #GP |
| 5 | 0xFFFFF | 0xFFFFFFFF (4GB-1) | any 32-bit offset | OK |

### Effective limit formula

| G | Limit field | Effective limit | Formula |
|:-:|:-----------:|:---------------:|---------|
| 0 | 0x00100 | 256 | limit |
| 1 | 0x00100 | 0x00100FFF | (limit << 12) \| 0xFFF |
| 0 | 0xFFFFF | 1,048,575 | limit |
| 1 | 0xFFFFF | 4,294,967,295 | (limit << 12) \| 0xFFF = 0xFFFFFFFF |

### Operand size vs limit check

| # | Op size | Limit | Offset | Bytes accessed | Expected |
|---|:-------:|:-----:|:------:|:--------------:|----------|
| 1 | byte | 0x00FF | 0x00FF | 1 | OK |
| 2 | word | 0x00FF | 0x00FF | 2 | #GP (0xFF+1 > limit) |
| 3 | word | 0x0100 | 0x00FF | 2 | OK (0xFF, 0x100) |
| 4 | dword | 0x0100 | 0x00FF | 4 | #GP |
| 5 | dword | 0x0102 | 0x00FF | 4 | OK (0xFF..0x102) |

> The limit check verifies: offset + (operand_size - 1) ≤ effective_limit

### Expand-down segments (E=1)

For expand-down data segments (type has E bit set):
- Valid range: (effective_limit + 1) to (D=0: 0xFFFF, D=1: 0xFFFFFFFF)
- Below limit is INVALID, above limit is VALID (opposite of expand-up)

| # | Limit | D bit | Valid range | Access at | Expected |
|---|:-----:|:-----:|:-----------:|:---------:|----------|
| 1 | 0x7FFF | 0 | 0x8000..0xFFFF | 0x8000 | OK |
| 2 | 0x7FFF | 0 | 0x8000..0xFFFF | 0x7FFF | #GP |
| 3 | 0x7FFF | 0 | 0x8000..0xFFFF | 0x0000 | #GP |
| 4 | 0x0FFF | 1 | 0x1000..0xFFFFFFFF | 0x1000 | OK |
| 5 | 0x0FFF | 1 | 0x1000..0xFFFFFFFF | 0x0FFF | #GP |

### Expand-down with G=1

| # | Limit | G | D | Valid range | Access at | Expected |
|---|:-----:|:-:|:-:|:-----------:|:---------:|----------|
| 1 | 0x00000 | 1 | 1 | 0x1000..0xFFFFFFFF | 0x1000 | OK |
| 2 | 0x00000 | 1 | 1 | 0x1000..0xFFFFFFFF | 0x0FFF | #GP |
| 3 | 0x000FF | 1 | 1 | 0x100000..0xFFFFFFFF | 0x100000 | OK |

### Big/Default bit (D/B) interaction

| Segment | D/B | Default address/operand size | Stack operations |
|---------|:---:|:----------------------------:|------------------|
| Code | D=0 | 16-bit | — |
| Code | D=1 | 32-bit | — |
| Stack | B=0 | — | SP used, 64KB limit |
| Stack | B=1 | — | ESP used, 4GB limit |
| Data | B=0 | — | expand-down upper = 0xFFFF |
| Data | B=1 | — | expand-down upper = 0xFFFFFFFF |

### Code segment limit (EIP check)

| # | Limit | G | EIP | Expected |
|---|:-----:|:-:|:---:|----------|
| 1 | 0x00FF | 0 | 0x00FF | OK (last valid byte) |
| 2 | 0x00FF | 0 | 0x0100 | #GP (beyond limit) |
| 3 | 0x00001 | 1 | 0x1FFF | OK |
| 4 | 0x00001 | 1 | 0x2000 | #GP |

> Code segment limit is checked against EIP before each instruction fetch.

### Stack segment limit (PUSH/POP)

| # | Limit | G | B | ESP before PUSH | Expected |
|---|:-----:|:-:|:-:|:---------------:|----------|
| 1 | 0x0FFF | 0 | 0 | 0x0004 | OK (push to 0x0002) |
| 2 | 0x0001 | 0 | 0 | 0x0002 | #SS (push would go to 0x0000, below limit+1) |

## Pre/Post State

### Byte granularity limit check

```
PRE (PM32):
  Data segment descriptor at GDT[3]:
    Base = 0x00100000
    Limit = 0x000FF (G=0, effective = 255)
    Type = data, read/write, expand-up
  DS loaded with selector 0x0018 (GDT[3], RPL=0)
  EAX = 0x12345678

  OP:  MOV [0x00FF], AL    (byte access at offset 255)

POST:
  [0x00100000 + 0x00FF] = 0x78   ← write succeeds
  No exception
```

### Limit violation — word at boundary

```
PRE (PM32):
  Data segment: limit = 0x00FF (G=0)
  DS loaded

  OP:  MOV [0x00FF], AX    (word access: offsets 0xFF and 0x100)

POST:
  #GP(0) exception         ← offset 0x100 > limit 0xFF
  No memory written
```

### Page granularity (G=1)

```
PRE (PM32):
  Data segment descriptor:
    Limit = 0x00001 (G=1, effective = 0x00001FFF = 8191)
    Type = data, expand-up

  OP:  MOV EAX, [0x1FFF]   (dword access: 0x1FFF..0x2002)

POST:
  #GP(0) exception         ← 0x2002 > 0x1FFF
```

### Page granularity success

```
PRE (PM32):
  Data segment: Limit = 0x00001 (G=1, effective = 0x1FFF)

  OP:  MOV AL, [0x1FFF]    (byte access at 0x1FFF)

POST:
  AL = value at base+0x1FFF
  No exception             ← 0x1FFF ≤ 0x1FFF
```

### Expand-down segment

```
PRE (PM32):
  Stack segment descriptor:
    Limit = 0x0FFF (G=0, B=0)
    Type = data, expand-down
  Valid range: 0x1000..0xFFFF

  OP:  MOV AX, [0x0FFF]    (access at 0x0FFF)

POST:
  #SS(0) exception         ← 0x0FFF ≤ limit, invalid for expand-down
```

### Expand-down success

```
PRE (PM32):
  Stack segment: Limit = 0x0FFF, expand-down, B=0
  Valid range: 0x1000..0xFFFF

  OP:  MOV AX, [0x1000]

POST:
  AX = value at base+0x1000
  No exception             ← 0x1000 > limit
```

### Code segment EIP limit

```
PRE (PM32):
  Code segment: Limit = 0x001FF (G=0)
  EIP = 0x001FE
  [CS:0x001FE] = 0x90 (NOP, 1 byte)
  [CS:0x001FF] = 0x90 (NOP, 1 byte)
  [CS:0x00200] = 0x90 (NOP, 1 byte) — beyond limit

  Execute instruction at 0x001FE (NOP)
  Execute instruction at 0x001FF (NOP)
  Attempt fetch at 0x00200

POST:
  First two NOPs execute
  #GP(0) when EIP reaches 0x00200 (beyond limit)
```

## Descriptor Setup

```nasm
; Data segment with byte granularity, limit 0x1FF
data_desc:
    dw 0x01FF           ; limit [15:0]
    dw 0x0000           ; base [15:0]
    db 0x10             ; base [23:16]
    db 0x92             ; P=1, DPL=0, S=1, type=0010 (data r/w)
    db 0x00             ; G=0, D/B=0, limit[19:16]=0
    db 0x00             ; base [31:24]

; Data segment with page granularity, limit 0x1FF (effective = 0x1FFFFF)
data_desc_g1:
    dw 0x01FF           ; limit [15:0]
    dw 0x0000           ; base [15:0]
    db 0x10             ; base [23:16]
    db 0x92             ; P=1, DPL=0, S=1, type=0010
    db 0x80             ; G=1, D/B=0, limit[19:16]=0
    db 0x00             ; base [31:24]

; Expand-down stack segment
stack_desc_ed:
    dw 0x0FFF           ; limit [15:0]
    dw 0x0000           ; base [15:0]
    db 0x20             ; base [23:16]
    db 0x96             ; P=1, DPL=0, S=1, type=0110 (data r/w expand-down)
    db 0x40             ; G=0, B=1, limit[19:16]=0
    db 0x00             ; base [31:24]
```

## State Save/Restore

- **Save:** GDT, segment registers, descriptor cache
- **Restore:** reload GDT, reload segment registers

## Known Divergences

| Behavior | 286 | 386 | 486 |
|----------|-----|-----|-----|
| Max limit | 64KB (16-bit) | 4GB (G=1) | 4GB (G=1) |
| Granularity bit | N/A | G in descriptor | G in descriptor |
| 32-bit segments | N/A | D/B bit | D/B bit |

## Pass/Fail Criteria

- **PASS:** #GP/#SS at correct boundary; no exception within limit
- **FAIL:** exception within limit; no exception beyond limit
- **SKIP:** GEN < 80386

## NOT TESTED (deferred)

- Limit check during descriptor load (separate spec)
- Limit enforcement in V86 mode (→ v86.md)
- TSS limit enforcement (→ tss.md)
