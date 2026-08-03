# Spec: 486 CPUID

## Metadata
- **Source file:** `src/cpu/80486/cpuid.asm`
- **TIER:** UNIVERSAL | VENUE: G+H | GEN: 80486+ | ORACLE: manual
- **Impl-plan:** Phase 6, area `486-CPUID`
- **Coverage:** [§8.4](../../coverage-matrix.md#84-hard-cases--cpuid)

## Purpose

Verify CPUID instruction: EAX=0 (vendor string), EAX=1 (family/model/stepping/feature).

## Test Cases

### CPUID detectability

| # | Action | Expected | Notes |
|---|--------|----------|-------|
| 1 | Toggle EFLAGS.ID bit | can toggle → CPUID available | detection method |
| 2 | Cannot toggle ID bit | CPUID not available | SKIP |

### EAX=0: Vendor ID

| # | Input EAX | Output | Notes |
|---|-----------|--------|-------|
| 1 | 0 | EAX=max leaf, EBX:ECX:EDX=vendor string | |

Expected vendor strings (golden per platform):
- Intel: "GenuineIntel"
- AMD: "AuthenticAMD"
- ao486: depends on core implementation (check what ao486 reports)

### EAX=1: Family/Model/Stepping

| # | Field | Bits in EAX | Notes |
|---|-------|:-----------:|-------|
| 1 | Stepping | 3:0 | |
| 2 | Model | 7:4 | |
| 3 | Family | 11:8 | 4 = 486 |
| 4 | Type | 13:12 | 0=OEM, 1=ODR, 2=DT |
| 5 | Extended model | 19:16 | |
| 6 | Extended family | 27:20 | |

### EAX=1: Feature flags

| # | Field | Register | Bit | Notes |
|---|-------|----------|:---:|-------|
| 1 | FPU | EDX | 0 | on-chip FPU |
| 2 | VME | EDX | 1 | V86 mode extensions |
| 3 | DE | EDX | 2 | debugging extensions |
| 4 | PSE | EDX | 3 | page size extensions (4MB) |
| 5 | TSC | EDX | 4 | time stamp counter |
| 6 | MSR | EDX | 5 | model specific registers |

## Pre/Post State (representative cases)

### CPUID detection — toggle EFLAGS.ID
PRE:
  EFLAGS = 0x00000002   (ID bit21 = 0)
OP:  PUSHFD
     OR DWORD [ESP], 0x200000   (set ID bit21)
     POPFD
     PUSHFD
     POP EAX
POST:
  If EAX & 0x200000 ≠ 0  → CPUID available (ID bit was writable)
  If EAX & 0x200000 == 0 → CPUID not available → SKIP

### CPUID EAX=0 — vendor string
PRE:
  EAX = 0x00000000
  EBX = 0xFFFFFFFF  (unknown)
  ECX = 0xFFFFFFFF
  EDX = 0xFFFFFFFF
OP:  CPUID             (with EAX=0)
POST (Intel 486 example):
  EAX = 0x00000001    (max CPUID leaf = 1)
  EBX = 0x756E6547    ("Genu" in little-endian)
  EDX = 0x49656E69    ("ineI")
  ECX = 0x6C65746E    ("ntel")
  ← EBX:EDX:ECX = "GenuineIntel" when read as ASCII

### CPUID EAX=1 — family/model/stepping
PRE:
  EAX = 0x00000001
  EBX = 0x00000000
  ECX = 0x00000000
  EDX = 0x00000000
OP:  CPUID             (with EAX=1)
POST (Intel 486 DX2 example):
  EAX = 0x00000430    (stepping=0, model=3, family=4, type=0)
    bits 3:0   = 0x0  (stepping)
    bits 7:4   = 0x3  (model)
    bits 11:8  = 0x4  (family = 486)
    bits 13:12 = 0x0  (type = OEM)
  EBX = varies        (brand index, CLFLUSH line size, etc.)
  EDX = 0x00000011    (FPU=1 bit0, VME=0, DE=0, PSE=0, TSC=1 bit4, MSR=1 bit5)
    ← bit0 FPU on-chip = 1 (486DX has integrated FPU)
    ← bit4 TSC = 1 (RDTSC available)

### CPUID at CPL=3 — OK (unprivileged)
PRE (PM32, CPL=3):
  EAX = 0x00000000
OP:  CPUID
POST:
  no exception        ← CPUID is usable from any privilege level
  EAX/EBX/ECX/EDX = vendor info as above

## State Save/Restore

- **Save:** EBX (CPUID clobbers EAX/EBX/ECX/EDX)
- **Restore:** restore EBX

## Pass/Fail Criteria

- **PASS:** vendor string matches expected; family/model correct for 486
- **SKIP:** if ID bit cannot be toggled (CPUID unavailable)
