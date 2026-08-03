# Spec: FPU Basic Load/Store

## Metadata
- **Source file:** `src/fpu/8087/basic.asm`
- **TIER:** UNIVERSAL | VENUE: G+H | GEN: 8086+ | ORACLE: manual
- **Impl-plan:** Phase 3, area `FPU-Basic`
- **Coverage:** [§4](../../coverage-matrix.md#4-fpu--8087--287--387--486-pri-1-a-domain-of-its-own)

## Purpose

Verify FLD (integer, real, ST(i)), FST/FSTP, FILD, FIST/FISTP, FBSTP/FBLD.
Confirm 80-bit extended precision round-trip is lossless.

## Prerequisites

- FPU detection passed (`g_fpu_type >= FPU_8087`)
- FNINIT to establish clean state

## Test Cases

### Integer load/store round-trip

| # | Type | Value | Load | Store back | Expected | Notes |
|---|------|-------|------|-----------|----------|-------|
| 1 | word | 0x1234 | FILD | FISTP | 0x1234 | exact |
| 2 | word | -1 (0xFFFF) | FILD | FISTP | -1 | signed |
| 3 | word | 0x8000 (INT16_MIN) | FILD | FISTP | -32768 | boundary |
| 4 | dword | 0x12345678 | FILD | FISTP | 0x12345678 | |
| 5 | dword | -1 | FILD | FISTP | -1 | |
| 6 | qword | 0x123456789ABC | FILD | FISTP | same | 64-bit int |
| 7 | qword | INT64_MIN | FILD | FISTP | exact | boundary |

### Real load/store round-trip

| # | Type | Value | Load | Store | Expected | Notes |
|---|------|-------|------|-------|----------|-------|
| 1 | dword | 1.0f | FLD | FSTP | 1.0f | single precision |
| 2 | qword | 1.0 | FLD | FSTP | 1.0 | double precision |
| 3 | tbyte | 1.0L | FLD | FSTP | 1.0L | extended (lossless) |
| 4 | tbyte | π (80-bit) | FLD | FSTP | exact | lossless round-trip |

> **Key:** extended precision (80-bit) load/store must be byte-exact.
> This is the only precision where round-trip is guaranteed lossless.

### Precision conversion on store

| # | Value in ST(0) | Store as | Expected | Notes |
|---|----------------|----------|----------|-------|
| 1 | 1.0/3.0 (ext) | dword (single) | 0x3EAAAAAB | rounded to 24-bit mantissa |
| 2 | 1.0/3.0 (ext) | qword (double) | 0x3FD5555555555555 | rounded to 53-bit mantissa |
| 3 | 1.0/3.0 (ext) | tbyte (extended) | exact | no rounding |

### Packed BCD (FBSTP/FBLD)

| # | Value | FBLD | FBSTP | Expected | Notes |
|---|-------|------|-------|----------|-------|
| 1 | 12345 (BCD) | load | store back | 12345 | round-trip |
| 2 | -12345 (BCD) | load | store back | -12345 | sign bit (bit 79) |
| 3 | 0 (all zero BCD) | load | store back | 0 | |

### FLD ST(i) / FST ST(i)

| # | Action | Stack after | Notes |
|---|--------|-------------|-------|
| 1 | FLD ST(0) | pushes copy of ST(0) | TOP decremented |
| 2 | FLD ST(1) | pushes copy of ST(1) | |
| 3 | FST ST(1) | copies ST(0) to ST(1), ST(0) stays | no push/pop |

### Stack overflow (FLD on full stack)

| # | Stack state | Action | Expected | Notes |
|---|-------------|--------|----------|-------|
| 1 | 8 values loaded | FLD again | #IS (invalid op), ST set | stack overflow |

## Pre/Post State (representative cases)

### FLD 1.0 — push onto stack

```
PRE (after FNINIT):
  CW = 0x037F (default: all masks set, nearest, extended)
  SW: TOP=0, all C0-C3=0, all exception bits clear
  TW: all registers = 11 (empty)
  Stack: [empty, empty, empty, empty, empty, empty, empty, empty]
           ST(0) ST(1) ST(2) ST(3) ST(4) ST(5) ST(6) ST(7)

  OP:  FLD1

POST:
  SW: TOP=7 (decremented 0→7, wraps)
  TW: ST(0)=tag(7)=00 (valid); rest still empty
  Stack: [1.0, empty, empty, empty, empty, empty, empty, empty]
           ST(0) ST(1)                                  ST(7)
```

### FLD ST(0) — duplicate top

```
PRE:
  TOP = 3
  ST(0) = 3.14,  ST(1) = 2.0
  Stack (physical R3=ST0, R4=ST1): [3.14, 2.0, empty, ...]

  OP:  FLD ST(0)

POST:
  TOP = 2 (decremented)
  ST(0) = 3.14 (copy),  ST(1) = 3.14 (old ST0),  ST(2) = 2.0 (old ST1)
```

### FILD/FISTP — integer round-trip

```
PRE:
  Memory at DS:0x1000 = 0x1234 (16-bit word)
  TOP = 0, Stack empty

  OP:  FILD word [0x1000]

POST (after FILD):
  TOP = 7
  ST(0) = +4660.0 (= 0x1234)
  TW(ST0) = 00 (valid)

  OP:  FISTP word [0x1002]

POST (after FISTP):
  TOP = 0 (back to empty)
  [DS:0x1002] = 0x1234  (exact round-trip)
```

### Precision conversion on store

```
PRE:
  TOP = 7
  ST(0) = 1.0/3.0 (extended, 64-bit mantissa)
  = 3FFF FFFFFFFFFFFFFFFFB (80-bit)

  OP:  FSTP dword [0x1000]   (store as single, 32-bit)

POST:
  [DS:0x1000..0x1003] = 0x3EAAAAAB  (rounded to 24-bit mantissa)
  TOP = 0 (stack popped)
```

### Stack overflow (#IS)

```
PRE:
  TOP = 0, all 8 registers filled with valid values
  TW: all 00 (valid)

  OP:  FLD1

POST:
  SW: #IE (bit 0) set, TOP decremented
  ST(0) = QNaN (old ST(7) overwritten)
  (If #IE masked: QNaN result, no exception delivered)
  (If #IE unmasked: exception handler invoked)
```

## State Save/Restore

- **Save:** full FPU state (FSAVE to 108-byte buffer)
- **Restore:** FRSTOR; verify stack is empty (TOP=0 after FNINIT)

## Pass/Fail Criteria

- **PASS:** round-trip values match; precision conversion correct
- **FAIL:** value mismatch or precision error
- **SKIP:** FPU not detected
