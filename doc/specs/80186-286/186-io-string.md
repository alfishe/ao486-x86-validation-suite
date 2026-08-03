# Spec: 80186 INS/OUTS I/O String Operations

## Metadata
- **Source file:** `src/cpu/80186/iostring.asm`
- **TIER:** HARDWARE | VENUE: G | GEN: 80186+ | ORACLE: manual
- **Impl-plan:** Phase 4, area `186-IO`
- **Coverage:** [§5](../../coverage-matrix.md#5-cpu--80186-pri-3-thin-layer)

## Purpose

Verify INS/OUTS instructions: port-to-memory and memory-to-port string transfers
with REP prefix, direction flag handling, and proper segment usage.

## Prerequisites

- Safe I/O port for testing (e.g., POST diagnostic port 0x80, or PIT counter)
- Memory buffer for transfers
- DF save/restore

## Instruction Forms

| Mnemonic | Opcode | Width | Direction |
|----------|:------:|:-----:|-----------|
| INSB | 6C | byte | DX → ES:DI |
| INSW | 6D | word | DX → ES:DI |
| INSD | 6D (32-bit) | dword | DX → ES:EDI (386+) |
| OUTSB | 6E | byte | DS:SI → DX |
| OUTSW | 6F | word | DS:SI → DX |
| OUTSD | 6F (32-bit) | dword | DS:ESI → DX (386+) |

## Test Cases

### INS — port to memory

| # | Port (DX) | Width | DF | Initial DI | CX | Expected DI | Memory |
|---|:---------:|:-----:|:--:|:----------:|:--:|:-----------:|--------|
| 1 | 0x80 | byte | 0 | 0x1000 | 1 | 0x1001 | [ES:0x1000]=port value |
| 2 | 0x80 | byte | 1 | 0x1000 | 1 | 0x0FFF | [ES:0x1000]=port value |
| 3 | 0x40 | word | 0 | 0x1000 | 1 | 0x1002 | [ES:0x1000]=port value |
| 4 | 0x40 | word | 1 | 0x1000 | 1 | 0x0FFE | [ES:0x1000]=port value |

### OUTS — memory to port

| # | Port (DX) | Width | DF | Initial SI | CX | Expected SI | Notes |
|---|:---------:|:-----:|:--:|:----------:|:--:|:-----------:|-------|
| 1 | 0x80 | byte | 0 | 0x1000 | 1 | 0x1001 | [DS:0x1000]→port |
| 2 | 0x80 | byte | 1 | 0x1000 | 1 | 0x0FFF | decrement |
| 3 | 0x40 | word | 0 | 0x1000 | 1 | 0x1002 | word transfer |

### REP INS — block input

| # | Port | CX | Width | DF | Final DI delta | Notes |
|---|:----:|:--:|:-----:|:--:|:--------------:|-------|
| 1 | 0x80 | 0 | byte | 0 | 0 | CX=0 does nothing |
| 2 | 0x80 | 4 | byte | 0 | +4 | 4 bytes read |
| 3 | 0x80 | 4 | byte | 1 | -4 | backward |
| 4 | 0x40 | 4 | word | 0 | +8 | 4 words = 8 bytes |

### REP OUTS — block output

| # | Port | CX | Width | DF | Final SI delta | Notes |
|---|:----:|:--:|:-----:|:--:|:--------------:|-------|
| 1 | 0x80 | 4 | byte | 0 | +4 | 4 bytes written |
| 2 | 0x80 | 16 | byte | 0 | +16 | block transfer |

### Segment usage

| Instruction | Source segment | Dest segment | Override allowed |
|-------------|:--------------:|:------------:|:----------------:|
| INS | — | ES (fixed) | NO |
| OUTS | DS | — | YES (CS, ES, SS) |

| # | Instruction | Override | Expected | Notes |
|---|-------------|----------|----------|-------|
| 1 | OUTSB | none | DS:SI | default |
| 2 | CS: OUTSB | CS: | CS:SI | source override |
| 3 | ES: INSB | ES: | still ES:DI | INS dest not overridable |

## Port Selection for Testing

### Safe ports (minimal side effects)

| Port | Device | Read behavior | Write behavior |
|:----:|--------|---------------|----------------|
| 0x80 | POST diag | returns last write | latches value |
| 0x61 | PPI port B | speaker/misc | speaker control |
| 0x40 | PIT counter 0 | count value | load count |

### Test with loopback (write then read)

```
1. OUTSB to port 0x80 with known value
2. INSB from port 0x80
3. Verify memory contains the written value
```

## Pre/Post State

### INS — single byte input

```
PRE:
  DX = 0x0080              (POST diagnostic port)
  ES:DI = 0x2000:0x0100
  [ES:0x0100] = 0x00       (will be overwritten)
  DF = 0                   (forward)
  Port 0x80 will return 0x55 (last value written)

  OP:  INSB

POST:
  [ES:0x0100] = 0x55       ← byte read from port
  DI = 0x0101              ← DI += 1 (DF=0)
  DX unchanged
```

### INS — backward direction

```
PRE:
  DX = 0x0080
  ES:DI = 0x2000:0x0100
  DF = 1                   (backward)

  OP:  INSB

POST:
  [ES:0x0100] = port value
  DI = 0x00FF              ← DI -= 1 (DF=1)
```

### OUTS — single byte output

```
PRE:
  DX = 0x0080
  DS:SI = 0x1000:0x0200
  [DS:0x0200] = 0xAA
  DF = 0

  OP:  OUTSB

POST:
  Port 0x80 receives 0xAA
  SI = 0x0201              ← SI += 1
```

### REP INSW — block word input

```
PRE:
  DX = 0x0040              (PIT counter 0)
  ES:DI = 0x2000:0x0100
  CX = 4                   (4 words = 8 bytes)
  DF = 0

  OP:  REP INSW

POST:
  [ES:0x0100..0x0107] = 4 words read from port
  DI = 0x0108              ← DI += 8
  CX = 0                   ← decremented to zero
```

### REP OUTSB with CX=0

```
PRE:
  DX = 0x0080
  DS:SI = 0x1000:0x0200
  CX = 0
  DF = 0

  OP:  REP OUTSB

POST:
  No port access           ← CX=0 means no iterations
  SI unchanged
  CX = 0
```

### Segment override on OUTS

```
PRE:
  DX = 0x0080
  CS:SI (using override)
  DS:SI = 0x1000:0x0200, [DS:0x0200] = 0xAA
  CS:SI = 0x0800:0x0200, [CS:0x0200] = 0x55
  DF = 0

  OP:  CS: OUTSB           (segment override prefix 2E)

POST:
  Port 0x80 receives 0x55  ← from CS:SI, not DS:SI
  SI = 0x0201
```

## Protected Mode Considerations (286+)

### IOPL checks

| # | CPL | IOPL | Expected | Notes |
|---|:---:|:----:|----------|-------|
| 1 | 0 | any | OK | ring 0 always allowed |
| 2 | 3 | 3 | OK | CPL ≤ IOPL |
| 3 | 3 | 0 | #GP | CPL > IOPL |

### I/O permission bitmap (386+)

| # | CPL | IOPL | Bitmap bit | Expected | Notes |
|---|:---:|:----:|:----------:|----------|-------|
| 1 | 3 | 0 | 0 (allowed) | OK | bitmap overrides IOPL |
| 2 | 3 | 0 | 1 (denied) | #GP | |

## State Save/Restore

- **Save:** SI, DI, DX, CX, DF, ES, DS, FLAGS
- **Restore:** all above; port state may not be restorable

## Known Divergences

| Behavior | 80186 | 286 | 386 |
|----------|-------|-----|-----|
| IOPL check | none | yes | yes |
| I/O bitmap | none | none | yes |
| INSD/OUTSD | no | no | yes |

## Pass/Fail Criteria

- **PASS:** correct SI/DI adjustment; data transferred correctly
- **FAIL:** wrong pointer, wrong data, unexpected #GP
- **SKIP:** GEN < 80186; or port not accessible (emulator restriction)

## NOT TESTED (deferred)

- Exact timing of I/O bus cycles (→T)
- DMA interaction during REP INS/OUTS (→T)
- I/O permission bitmap exhaustive coverage (→ separate PM I/O spec)
