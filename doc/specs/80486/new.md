# Spec: 486 New Instructions

## Metadata
- **Source file:** `src/cpu/80486/new.asm`
- **TIER:** UNIVERSAL | VENUE: G+H | GEN: 80486+ | ORACLE: manual
- **Impl-plan:** Phase 6, area `486-New`
- **Coverage:** [§8.1](../../coverage-matrix.md#81-hard-cases--486-new-instructions)

## Purpose

Verify XADD, CMPXCHG, CMPXCHG8B, BSWAP, INVD, WBINVD, INVLPG.

## Test Cases

### XADD (exchange and add)

| # | op1 | op2 | Expected op1 | Expected op2 | Flags | Notes |
|---|-----|-----|-------------|-------------|-------|-------|
| 1 | 0x10 | 0x20 | 0x30 (sum) | 0x10 (original op1) | CF/ZF from 0x30 | |
| 2 | 0xFF | 0x01 | 0x00 (wrap) | 0xFF | CF=1, ZF=1 | |

### CMPXCHG (compare and exchange)

| # | EAX | op2 | dest | Expected dest | ZF | Notes |
|---|-----|-----|------|--------------|:--:|-------|
| 1 | 0x10 | 0x20 | 0x10 | 0x20 (swapped) | 1 | match → exchange |
| 2 | 0x10 | 0x20 | 0x30 | 0x30 (unchanged) | 0 | no match → EAX=dest |

> CMPXCHG compares EAX with dest. If equal: dest=op2, ZF=1.
> If not: EAX=dest, ZF=0. Flags reflect the comparison (as CMP EAX, dest).

### CMPXCHG8B (compare and exchange 8 bytes)

| # | EDX:EAX | dest (8 bytes) | ECX:EBX | Expected | ZF | Notes |
|---|---------|---------------|---------|----------|:--:|-------|
| 1 | matches dest | — | new value | dest=ECX:EBX | 1 | exchange |
| 2 | doesn't match | — | — | EDX:EAX=dest | 0 | load dest into EDX:EAX |

> CMPXCHG8B is 486+. Early 486 steppings had a #UD erratum on locked CMPXCHG8B.

### BSWAP (byte swap)

| # | Input EAX | Expected EAX | Notes |
|---|-----------|-------------|-------|
| 1 | 0x12345678 | 0x78563412 | reverse byte order |
| 2 | 0x000000FF | 0xFF000000 | |
| 3 | 0xAABBCCDD | 0xDDCCBBAA | |

> BSWAP works on 32-bit registers only. BSWAP on a 16-bit register is undefined.

## Pre/Post State (representative cases)

### XADD — exchange and add
PRE:
  EAX = 0x00000010   (op1)
  EBX = 0x00000020   (op2)
  FLAGS = 0x0000
OP:  XADD EAX, EBX
POST:
  EAX = 0x00000030   ← sum (0x10 + 0x20)
  EBX = 0x00000010   ← original value of EAX
  ZF=0  SF=0  CF=0   (0x30 is non-zero, positive, no carry)

PRE (wrap case):
  EAX = 0x000000FF   (8-bit op)
  BL  = 0x01
  FLAGS = 0x0000
OP:  XADD AL, BL
POST:
  AL = 0x00          ← wrapped from 0xFF + 0x01
  BL = 0xFF          ← original AL
  CF=1  ZF=1  SF=0   (carry out, zero result)

### CMPXCHG — match, exchange
PRE:
  EAX = 0x00000010   (expected value)
  EBX = 0x00000020   (new value)
  mem at [ESI] = 0x00000010  (matches EAX)
  FLAGS = 0x0000
OP:  CMPXCHG [ESI], EBX
POST:
  mem = 0x00000020   ← exchanged: dest now has EBX
  EAX = 0x00000010   ← unchanged (match, no load)
  ZF = 1             ← match → exchange occurred

### CMPXCHG — no match, load dest
PRE:
  EAX = 0x00000010   (expected)
  EBX = 0x00000020   (new value)
  mem at [ESI] = 0x00000030  (does NOT match EAX)
  FLAGS = 0x0000
OP:  CMPXCHG [ESI], EBX
POST:
  mem = 0x00000030   ← unchanged (no exchange)
  EAX = 0x00000030   ← loaded from dest
  ZF = 0             ← no match → exchange skipped
  ← flags reflect comparison (as CMP EAX=0x10, dest=0x30)

### CMPXCHG8B — match, exchange 8 bytes
PRE:
  EDX:EAX = 0xAABBCCDD_11223344  (expected)
  ECX:EBX = 0x00000000_99999999  (new value)
  mem [ESI] (8 bytes) = 0xAABBCCDD_11223344  (matches)
  FLAGS = 0x0000
OP:  CMPXCHG8B [ESI]
POST:
  mem = 0x00000000_99999999  ← exchanged: ECX:EBX written
  EDX:EAX = 0xAABBCCDD_11223344  ← unchanged
  ZF = 1             ← match

### CMPXCHG8B — no match
PRE:
  EDX:EAX = 0x00000000_00000001  (expected)
  ECX:EBX = 0x00000000_00000002  (new value)
  mem [ESI] (8 bytes) = 0x00000000_00000005  (does NOT match)
  FLAGS = 0x0000
OP:  CMPXCHG8B [ESI]
POST:
  mem = 0x00000000_00000005  ← unchanged
  EDX:EAX = 0x00000000_00000005  ← loaded from dest
  ZF = 0             ← no match

### BSWAP EAX — reverse byte order
PRE:
  EAX = 0x12345678
  byte layout: [12][34][56][78] (big-endian visual)
OP:  BSWAP EAX
POST:
  EAX = 0x78563412   ← bytes reversed: [78][56][34][12]

PRE:
  EAX = 0x000000FF
OP:  BSWAP EAX
POST:
  EAX = 0xFF000000

## State Save/Restore

- **Save:** EAX, EBX, ECX, EDX, FLAGS
- **Restore:** `RESTORE_STATE`

## Pass/Fail Criteria

- **PASS:** all operations produce correct results
- **FAIL:** any mismatch
- **SKIP:** GEN < 80486
