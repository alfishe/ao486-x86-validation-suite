# Spec: FPU Generation Differences (8087/287/387/486)

## Metadata
- **Source file:** `src/fpu/detect.asm`, `src/fpu/compat.asm`
- **TIER:** UNIVERSAL | VENUE: G+H | GEN: 8086+ (FPU required) | ORACLE: golden
- **Impl-plan:** Phase 3, area `FPU-Gen`
- **Coverage:** [§4](../../coverage-matrix.md#4-fpu--8087--287--387--486-pri-1-a-domain-of-its-own)
- **Detail:** [prep-analysis §5](../../prep-analysis.md#5-fpu-corner-cases), [§10](../../prep-analysis.md#10-fpu-state-image-format-detail)

## Purpose

Document and test FPU generation differences that affect compatibility.
Pin undefined behaviors to golden values per generation.

## FPU Detection

| Test | 8087 | 80287 | 80387 | 486 FPU |
|------|:----:|:-----:|:-----:|:-------:|
| FNINIT; check CW | 0x03FF | 0x03FF | 0x037F | 0x037F |
| Infinity control (CW bit 12) | used | used | ignored | ignored |
| +Inf == -Inf after FCOMPP | depends on IC | depends on IC | always unequal | always unequal |

### Detection algorithm

```nasm
detect_fpu:
    fninit
    fnstsw ax
    cmp al, 0
    jne .no_fpu
    
    ; Check control word default
    fnstcw [cw]
    mov ax, [cw]
    and ax, 0x0F3F          ; mask reserved bits
    cmp ax, 0x033F          ; 8087/287 default
    je .is_8087_or_287
    cmp ax, 0x037F          ; 387/486 default
    je .is_387_or_486
    
    ; Distinguish 8087 vs 287: check for 80287 presence via FSETPM
    ; (287 has FSETPM, 8087 doesn't)
    
    ; Distinguish 387 vs 486: check CPUID or 486-specific behavior
```

## Instruction Availability

| Instruction | 8087 | 287 | 387 | 486 | Notes |
|-------------|:----:|:---:|:---:|:---:|-------|
| FSIN, FCOS | — | — | ✓ | ✓ | Transcendentals |
| FSINCOS | — | — | ✓ | ✓ | |
| FPREM1 | — | — | ✓ | ✓ | IEEE remainder |
| FUCOM, FUCOMP, FUCOMPP | — | — | ✓ | ✓ | Unordered compare |
| FCMOV* | — | — | — | P6+ | Conditional move |
| FSETPM | — | ✓ | — | — | 287-only |
| FFREEP | ✓ | ✓ | ✓ | ✓ | Undocumented pop |

## Behavioral Differences

### Infinity arithmetic

| Operation | 8087/287 (IC=0, projective) | 8087/287 (IC=1, affine) | 387/486 (affine only) |
|-----------|:---------------------------:|:-----------------------:|:---------------------:|
| +Inf compare -Inf | equal | unequal | unequal |
| +Inf + (-Inf) | NaN | NaN | NaN |
| 0 × ±Inf | NaN | NaN | NaN |

### Control word differences

| Bit | 8087 | 287 | 387 | 486 |
|:---:|------|-----|-----|-----|
| 12 (IC) | Infinity control | Infinity control | Reserved (ignored) | Reserved |
| 5 (reserved) | varies | varies | 0 | 0 |

### Status word C1 after operations

| Condition | 8087 | 287 | 387 | 486 |
|-----------|:----:|:---:|:---:|:---:|
| Stack overflow | C1=1 | C1=1 | C1=1 | C1=1 |
| Stack underflow | C1=0 | C1=0 | C1=0 | C1=0 |
| Round up occurred | undefined | undefined | C1=1 | C1=1 |

### Denormal handling

| FPU | Denormal operand | Denormal result |
|-----|------------------|-----------------|
| 8087 | #D, then process | flush to zero (some ops) |
| 287 | #D, then process | flush to zero (some ops) |
| 387 | #D if unmasked | full denormal support |
| 486 | #D if unmasked | full denormal support |

### FNINIT default values

| Register | 8087/287 | 387/486 |
|----------|:--------:|:-------:|
| CW | 0x03FF | 0x037F |
| SW | 0x0000 | 0x0000 |
| TW | 0xFFFF | 0xFFFF |
| IP | 0 | 0 |
| DP | 0 | 0 |

### FSAVE/FRSTOR format

| Field | 8087 (94 bytes) | 287 PM (94 bytes) | 387/486 (108 bytes) |
|-------|:---------------:|:-----------------:|:-------------------:|
| Offset 0 | CW | CW | CW (32-bit) |
| Offset 2/4 | SW | SW | SW (32-bit) |
| Offset 4/8 | TW | TW | TW (32-bit) |
| Offset 6/12 | IP [15:0] | IP [15:0] | IP (32-bit) |
| ... | ... | ... | ... |
| Data regs | ST(0)-ST(7), 10 bytes each | same | same |

See [save.md](save.md) for detailed format.

## Test Cases

### CW default after FNINIT

| # | FPU | Expected CW | Notes |
|---|-----|:-----------:|-------|
| 1 | 8087 | 0x03FF | IC=1, all exceptions masked |
| 2 | 287 | 0x03FF | same as 8087 |
| 3 | 387 | 0x037F | IC reserved (0), bit 6 always 1 |
| 4 | 486 | 0x037F | same as 387 |

### Infinity control (8087/287 only)

| # | IC | +Inf vs -Inf compare | Expected C0,C2,C3 |
|---|:--:|:--------------------:|:-----------------:|
| 1 | 0 (projective) | FCOMPP | C3=1 (equal) |
| 2 | 1 (affine) | FCOMPP | C0=1 (less) or C0=0,C3=0 |
| 3 | (387/486) | FCOMPP | always unequal |

### FSIN/FCOS availability

| # | FPU | FSIN | Expected |
|---|-----|------|----------|
| 1 | 8087 | FSIN | #UD |
| 2 | 287 | FSIN | #UD |
| 3 | 387 | FSIN | result |
| 4 | 486 | FSIN | result |

### FPREM vs FPREM1

| # | FPU | Instruction | Algorithm |
|---|-----|-------------|-----------|
| 1 | 8087 | FPREM | truncation toward 0 |
| 2 | 287 | FPREM | truncation toward 0 |
| 3 | 387 | FPREM | truncation toward 0 |
| 3 | 387 | FPREM1 | IEEE round-to-nearest |
| 4 | 486 | FPREM1 | IEEE round-to-nearest |

### C1 round-up indicator (387+)

| # | FPU | Operation | C1 after |
|---|-----|-----------|:--------:|
| 1 | 8087 | FADD (round up) | undefined |
| 2 | 287 | FADD (round up) | undefined |
| 3 | 387 | FADD (round up) | 1 |
| 4 | 486 | FADD (round up) | 1 |

## Pre/Post State

### FNINIT CW verification

```
PRE:
  FPU initialized (any state)

  OP:  FNINIT
       FNSTCW [cw]

POST (8087/287):
  [cw] = 0x03FF
  Bits: IC=1, RC=00, PC=11, all masks=1

POST (387/486):
  [cw] = 0x037F
  Bits: IC=0 (reserved), RC=00, PC=11, all masks=1
```

### Infinity compare (IC-dependent)

```
PRE (287, IC=0 projective):
  CW bit 12 = 0
  ST(0) = +Inf
  ST(1) = -Inf

  OP:  FCOMPP

POST:
  C3=1, C2=0, C0=0    ← +Inf == -Inf (projective infinity)
  Stack popped twice

PRE (287, IC=1 affine):
  CW bit 12 = 1
  ST(0) = +Inf
  ST(1) = -Inf

  OP:  FCOMPP

POST:
  C3=0, C2=0, C0=1    ← +Inf > -Inf (affine: distinct infinities)
```

### FSIN on 287 (#UD)

```
PRE (287):
  FPU = 80287

  OP:  FSIN            (opcode D9 FE)

POST:
  #UD exception        ← instruction not recognized
```

### FSIN on 387

```
PRE (387):
  ST(0) = π/6

  OP:  FSIN

POST:
  ST(0) = 0.5          ← sin(π/6) = 0.5
  No exception
```

## Golden Values

### Undefined flags per generation

Load golden values from `data/vectors/fpu_gen_golden.json`:

```json
{
  "8087": {
    "fninit_cw": "0x03FF",
    "mul_zero_flags": "...",
    "...": "..."
  },
  "287": { ... },
  "387": { ... },
  "486": { ... }
}
```

## State Save/Restore

- **Save:** full FPU state (FNSAVE)
- **Restore:** FRSTOR (format must match FPU generation)

## Known Divergences Summary

| Feature | 8087 | 287 | 387 | 486 |
|---------|:----:|:---:|:---:|:---:|
| CW default | 0x03FF | 0x03FF | 0x037F | 0x037F |
| IC bit effective | yes | yes | no | no |
| FSIN/FCOS | no | no | yes | yes |
| FPREM1 | no | no | yes | yes |
| FUCOM* | no | no | yes | yes |
| Full denormal | no | no | yes | yes |
| C1 round-up | no | no | yes | yes |
| FSAVE size | 94 | 94 | 108 | 108 |

## Pass/Fail Criteria

- **PASS:** correct CW default; generation-specific behavior matches golden
- **FAIL:** wrong CW; behavior doesn't match detected FPU type
- **SKIP:** no FPU detected
