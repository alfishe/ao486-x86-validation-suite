# Spec: FPU Constants

## Metadata
- **Source file:** `src/fpu/8087/const.asm`
- **TIER:** UNIVERSAL | VENUE: G+H | GEN: 8086+ | ORACLE: manual
- **Impl-plan:** Phase 3, area `FPU-Const`
- **Coverage:** [§4](../../coverage-matrix.md#4-fpu--8087--287--387--486-pri-1-a-domain-of-its-own)

## Purpose

Verify FLDL2E, FLDL2T, FLDLG2, FLDLN2, FLDPI, FLDZ, FLD1.
These load predefined constants — verify exact 80-bit bit patterns.

## Test Cases

### Each constant — exact bit pattern

| Instruction | Constant | 80-bit hex (sign|exp|significand) | Decimal approx |
|-------------|----------|-----------------------------------|----------------|
| FLD1 | +1.0 | 3F FF 8000 0000 0000 0000 | 1.0 |
| FLDZ | +0.0 | 00 00 0000 0000 0000 0000 | 0.0 |
| FLDPI | π | 40 00 C90F DAA2 2168 C235 | 3.14159265358979323851 |
| FLDL2E | log2(e) | 3F FE B8AA 3B29 5C17 8029 | 1.44269504088896340736 |
| FLDL2T | log2(10) | 40 00 9A20 9A84 FBCF F799 | 3.32192809488736234781 |
| FLDLG2 | log10(2) | 3F FD DE5B D8A9 3728 7195 | 0.30102999566398119521 |
| FLDLN2 | ln(2) | 3F FE B172 17F7 D1CF 79AC | 0.69314718055994530942 |

> These values are defined in the Intel manual and must be byte-exact.
> Verify by loading, storing to a 10-byte buffer, and comparing with
> the expected hex pattern.

### Stack effect

| Instruction | TOP change | Notes |
|-------------|:----------:|-------|
| FLDxxx | TOP -= 1 | pushes constant onto stack |

## Pre/Post State (representative cases)

### FLDPI — load π

```
PRE:
  TOP = 0, Stack empty (after FNINIT)
  TW = 0xFFFF (all empty)

  OP:  FLDPI

POST:
  TOP = 7
  ST(0) = π = 4000 C90FDAA2 2168C235  (80-bit)
  TW: R7 = 00 (valid)
  Memory layout if stored (FSTP tbyte):
    [0x1000..0x1009] = 35 C2 68 21 A2 DA 0F C9 00 40
    (little-endian byte order of 4000 C90FDAA2 2168C235)
```

### FLD1 — load +1.0

```
PRE:
  TOP = 0, Stack empty

  OP:  FLD1

POST:
  TOP = 7
  ST(0) = +1.0 = 3FFF 80000000 00000000
  TW: R7 = 00 (valid)
```

### FLDZ — load +0.0

```
PRE:
  TOP = 0, Stack empty

  OP:  FLDZ

POST:
  TOP = 7
  ST(0) = +0.0 = 0000 00000000 00000000
  TW: R7 = 01 (zero tag)
  Note: +0.0 has tag=01(zero), NOT 00(valid)
```

### Verify exact bit pattern via store

```
PRE:
  TOP = 7
  ST(0) = π (loaded via FLDPI)
  Buffer at DS:0x2000 = uninitialized

  OP:  FSTP tbyte [0x2000]   (store 80-bit, pop)

POST:
  [0x2000] = 0x35  (byte 0, LSB)
  [0x2001] = 0xC2
  [0x2002] = 0x68
  [0x2003] = 0x21
  [0x2004] = 0xA2
  [0x2005] = 0xDA
  [0x2006] = 0x0F
  [0x2007] = 0xC9
  [0x2008] = 0x00
  [0x2009] = 0x40  (byte 9, MSB = sign+exponent)
  TOP = 0 (popped back to empty)
```

## State Save/Restore

- Full FPU state save/restore

## Pass/Fail Criteria

- **PASS:** stored 80-bit value matches the exact reference hex
- **FAIL:** any bit differs
- **SKIP:** FPU not detected
