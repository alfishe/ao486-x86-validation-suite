# Spec: 386 32-bit Operations & Addressing

## Metadata
- **Source file:** `src/cpu/80386/bit32.asm`
- **TIER:** UNIVERSAL | VENUE: G+H | GEN: 80386+ | ORACLE: manual
- **Impl-plan:** Phase 5, areas `386-32bit`, `386-Addr`
- **Coverage:** [§7](../../coverage-matrix.md#7-cpu--80386-pri-1-32-bit--paging--v86)
- **Prerequisite:** [286-pm-infra.md](../80186-286/286-pm-infra.md)

## Purpose

Verify 32-bit register operations, 32-bit addressing modes (scaled index),
new segment override prefixes (FS/GS), and 16/32-bit operand size mixing.

## Test Cases

### 32-bit GPR operations

| # | Instruction | Expected | Notes |
|---|-------------|----------|-------|
| 1 | MOV EAX, 0x12345678 | EAX = 0x12345678 | 32-bit move |
| 2 | ADD EAX, ECX | 32-bit add with 32-bit flags | |
| 3 | MOV AX, 0x1234 (in 32-bit seg) | only low 16 bits affected; upper 16 preserved | partial register |
| 4 | MOV AL, 0xFF (in 32-bit seg) | only low 8 bits; upper 24 preserved | partial register |

> Writing to a 16-bit register does NOT zero-extend to 32 bits.
> Writing to an 8-bit register does NOT affect the upper bits.
> This is a common emulator bug.

### 32-bit addressing modes

| # | Effective address form | Notes |
|---|----------------------|-------|
| 1 | [EAX] | direct register indirect |
| 2 | [EAX + ECX] | base + index |
| 3 | [EAX + ECX*2] | base + scaled index |
| 4 | [EAX + ECX*4 + 0x1000] | base + scaled index + displacement |
| 5 | [EBX*8] | scaled index without base |
| 6 | [ESP] | stack pointer indirect |
| 7 | [EBP + 0x10] | frame pointer + disp (EBP requires disp) |

### Scaled index

| # | Scale | Index | Address calculation | Notes |
|---|:-----:|-------|--------------------|----|
| 1 | ×1 | ECX=4 | base + 4 | |
| 2 | ×2 | ECX=4 | base + 8 | word array |
| 3 | ×4 | ECX=4 | base + 16 | dword array |
| 4 | ×8 | ECX=4 | base + 32 | qword array |

### FS/GS segment overrides

| # | Prefix | Segment used | Notes |
|---|--------|-------------|-------|
| 1 | 64h | FS | |
| 2 | 65h | GS | |
| 3 | 66h | operand-size override | switches 16↔32 bit |
| 4 | 67h | address-size override | switches 16↔32 bit addressing |

### Operand-size prefix (66h) mixing

| # | Segment default | Prefix | Effective size | Notes |
|---|:---------------:|--------|:--------------:|-------|
| 1 | 32-bit (D=1) | 66h | 16-bit | override to 16 |
| 2 | 16-bit (D=0) | 66h | 32-bit | override to 32 |

### Address calculation wrap at 4GB

| # | Base | Index | Expected | Notes |
|---|------|-------|----------|-------|
| 1 | 0xFFFFFFF0 | 0x20 | wraps to 0x10 | 32-bit address wraps |

## Pre/Post State (representative cases)

### Partial register write — 16-bit in 32-bit segment

```
PRE (PM32, D=1):
  EAX = 0x12345678

  OP:  MOV AX, 0xABCD     (16-bit write in 32-bit segment)

POST:
  EAX = 0x1234ABCD       ← only low 16 bits changed, upper 16 PRESERVED
  (Common emulator bug: zero-extending to 0x0000ABCD)
```

### Partial register write — 8-bit

```
PRE:
  EAX = 0x12345678

  OP:  MOV AL, 0xFF

POST:
  EAX = 0x123456FF       ← only low 8 bits, upper 24 PRESERVED
```

### 32-bit ADD with flags

```
PRE:
  EAX = 0x7FFFFFFF      (+2147483647, max signed positive)
  ECX = 0x00000001
  FLAGS = 0x00000000

  OP:  ADD EAX, ECX

POST:
  EAX = 0x80000000      (-2147483648, wrapped)
  ECX = 0x00000001      (unchanged)
  CF=0 PF=0 AF=1 ZF=0 SF=1 OF=1
  (pos+pos=neg → signed overflow)
```

### Scaled index addressing

```
PRE:
  EAX = 0x00100000     (base of dword array)
  ECX = 0x00000004     (index = element 4)
  [DS:0x00100010] = 0xDEADBEEF   (element at base + 4*4)

  OP:  MOV EDX, [EAX + ECX*4]    (scale=4 for dword array)

POST:
  EDX = 0xDEADBEEF
  Effective address = 0x00100000 + (4 * 4) = 0x00100010
```

### Operand-size prefix (66h) in 32-bit segment

```
PRE (PM32, D=1):
  EAX = 0x12345678

  OP:  66 B8 34 12       (operand-size prefix + MOV AX, 0x1234)
  (66h forces 16-bit operand size in a D=1 segment)

POST:
  EAX = 0x12341234      (upper 16 preserved, lower 16 = 0x1234)
```

### Address wrap at 4GB

```
PRE:
  EAX = 0xFFFFFFF0     (base near 4GB limit)
  ECX = 0x00000020     (index)

  OP:  MOV EDX, [EAX + ECX]   (EA = 0xFFFFFFF0 + 0x20 = 0x100000010)

POST:
  Effective address wraps: 0x00000010
  EDX = value at physical 0x00000010
```

## State Save/Restore

- **Save:** all 32-bit GPRs (EAX-EDI), FLAGS, segment regs
- **Restore:** `RESTORE_STATE`

## Pass/Fail Criteria

- **PASS:** 32-bit results correct; addressing modes compute correct EA
- **FAIL:** wrong EA or partial-register behavior
- **SKIP:** GEN < 80386
