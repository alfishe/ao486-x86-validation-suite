# Spec: Timing Constellations

## Metadata
- **Source file:** `src/timing/timing.asm`
- **TIER:** TIMING | VENUE: G⁺ | GEN: 8086+ | ORACLE: diff
- **Impl-plan:** Phase 9, area `Timing`
- **Coverage:** [§11](../../coverage-matrix.md#11-timing-constellations-pri-4--bands-never-hard-fail)
- **Refs:** [references.md](../../references.md) — Intel 486 timing charts

## Purpose

Verify instruction and peripheral timing via measurement, compared against a
per-target reference band. These tests **never hard-fail** — they report deviation
from the expected band. Cycle-exact timing is co-sim/bench territory (venue C/T),
not guest-testable.

## Measurement Methods

| Method | Precision | Availability | Notes |
|--------|-----------|-------------|-------|
| PIT channel 2 | ~838ns (1.193 MHz) | 8086+ | most portable; read via port 0x61 bit 4 |
| RDTSC | 1 clock cycle | Pentium+ (late 486) | highest precision; not available on all targets |
| Loop iteration count | coarse | all | relative comparison only |

### PIT-based measurement

```
; 1. Program PIT ch2 to mode 2 (rate generator), count=0xFFFF
; 2. Enable ch2 gate (port 0x61, bit 0=1)
; 3. Execute the timed code
; 4. Latch and read ch2 count
; 5. Elapsed = 0xFFFF - latched_count (in PIT ticks, ~838ns each)
```

> See [pit.md](../peripheral/pit.md) for PIT programming details.

## Test Cases

### Cached vs uncached loop

| # | Code | Expected | Notes |
|---|------|----------|-------|
| 1 | Tight loop `loop $` (N iterations), cache on | fast band | CR0.CD=0 |
| 2 | Same loop, cache disabled (CR0.CD=1) | slower band | 486+ |
| 3 | Delta = cached - uncached | > 0 if cache works | proves cache active |

### Branch taken vs not taken

| # | Code | Ratio | Notes |
|---|------|:-----:|-------|
| 1 | `mov cx, N; loop $` (always taken except last) | baseline taken | |
| 2 | `mov cx, N; jcxz skip; nop; skip:` (never taken) | baseline not-taken | |
| 3 | Compare timing ratio | taken/not-taken ≈ expected | branch penalty indicator |

### Interrupt latency

| # | Method | Measurement | Expected | Notes |
|---|--------|-------------|----------|-------|
| 1 | PIT ch0 IRQ0 → handler entry | time from IRQ assert to handler first instruction | coarse band | ~hundreds of clocks |
| 2 | Measure via PIT ch2 counter delta | | | |

> Exact interrupt latency is co-sim territory (venue C). This gives a coarse band only.

### FDIV / transcendental latency

| # | Instruction | Measurement | Expected | Notes |
|---|-------------|-------------|----------|-------|
| 1 | `fdiv` (80-bit) | time N FDIVs / N | per-instruction band | FPU-dependent |
| 2 | `fsqrt` | time N FSQRTs / N | per-instruction band | |
| 3 | `fsin` | time N FSINs / N | per-instruction band | transcendental is slow |

### DMA throughput

| # | Transfer | Measurement | Expected | Notes |
|---|----------|-------------|----------|-------|
| 1 | DMA single transfer, N bytes | total time / N bytes | throughput band | cycle-steal timing is venue T |

## Per-Target Reference Bands

| Target | Reference | Notes |
|--------|-----------|-------|
| 486DX-33, 0 wait states | baseline | all bands relative to this |
| ao486 on MiSTer | compare against 486DX-33 | deviation reported |
| DOSBox-X | compare | emulator timing not authoritative |
| 86Box | compare | closer to real silicon |

## Pre/Post State (representative cases)

### PIT-based measurement setup
PRE (real mode):
  PIT CH2 = unknown mode/count
  Port 0x61 bits 0-1 = unknown
OP:  ; Configure PIT channel 2 for measurement
     OUT 0x43, 0xB4   ; control: CH2, lo/hi, mode 2, binary
     OUT 0x42, 0xFF   ; count LSB = 0xFF
     OUT 0x42, 0xFF   ; count MSB = 0xFF → count = 0xFFFF
     IN  AL, 0x61
     OR  AL, 0x01     ; enable CH2 gate (bit 0)
     OUT 0x61, AL
POST:
  PIT CH2: mode 2, count = 0xFFFF, counting down at 1.193 MHz
  Port 0x61 bit 0 = 1 (CH2 gate enabled)
  ← Each PIT tick ≈ 838ns; max window = 0xFFFF × 838ns ≈ 54.9ms

### Measuring a tight loop
PRE (PIT CH2 configured as above):
  ECX = 0x00100000   (1M iterations)
  PIT CH2 count = 0xFFFF (just started)
OP:  loop_start:
     DEC ECX
     JNZ loop_start
     ; latch and read PIT CH2
     OUT 0x43, 0x80   ; latch CH2 count
     IN  AL, 0x42     ; read LSB
     MOV BL, AL
     IN  AL, 0x42     ; read MSB
     MOV BH, AL
POST:
  BX = latched count (e.g., 0xF000)
  Elapsed PIT ticks = 0xFFFF - 0xF000 = 0x0FFF = 4095
  Elapsed time = 4095 × 838ns ≈ 3.43ms
  Per-iteration = 3.43ms / 1M ≈ 3.43ns (this would be sub-PIT-tick; use larger N)

### Cached vs uncached delta
PRE (PM32, CPL=0, 486+):
  CR0 = 0x00000011   (CD=0, cache enabled)
  ECX = 0x00100000   (iterations)
  Result_cached = 0  (to store measured ticks)
OP (measure cached):
     ; (run timed loop, store result in Result_cached)
POST:
  Result_cached = 0x0FFF   (example: 4095 PIT ticks)

PRE:
  CR0 = 0x60000011   (CD=1, NW=1 → cache disabled)
OP (measure uncached):
     ; (run same timed loop)
POST:
  Result_uncached = 0x1FFF  (example: 8191 PIT ticks)
  Delta = 8191 - 4095 = 4096  ← positive delta proves cache effect
  CR0 = 0x60000011   ← MUST restore CR0.CD=0 afterward

### Branch taken vs not taken
PRE:
  ECX = 0x00100000   (iterations)
  PIT CH2 armed
OP (always-taken loop):
     loop_take:
     DEC ECX
     JNZ loop_take
     ; latch PIT
POST:
  Ticks_taken = X

PRE:
  ECX = 0x00100000
OP (never-taken conditional):
     loop_notake:
     DEC ECX
     JCXZ skip       ; never taken (CX>0)
     JMP loop_notake
     skip:
POST:
  Ticks_notake = Y
  Ratio = X / Y      ← branch penalty indicator
  ← On 486: taken branch costs ~1 extra clock vs not-taken

### RDTSC measurement (if available)
PRE (PM32 or real mode, CPUID bit TSC=1):
  EDX:EAX = unknown
OP:  RDTSC
     MOV ESI, EAX    ; save start low
     MOV EDI, EDX    ; save start high
     ; ... execute timed code ...
     RDTSC
     SUB EAX, ESI    ; elapsed low
     SBB EDX, EDI    ; elapsed high
POST:
  EDX:EAX = elapsed CPU clock cycles
  ← RDTSC gives cycle-exact count (not PIT ticks)
  ← Must check CPUID before use; not available on 8086-early486

## State Save/Restore

- **Save:** PIT ch2 config + count; CR0 (if CD toggled); IF (if IRQ used)
- **Restore:** restore PIT ch2; restore CR0.CD; restore IF

## Pass/Fail Criteria

- **PASS:** measurement falls within expected band (±tolerance); no hard FAIL for timing
- **WARN:** measurement outside band — reported as deviation, not failure
- **SKIP:** if PIT unavailable or measurement method not functional

## Reference Timing Bands (486DX-33 baseline)

### Integer instruction timing (clocks)

| Instruction | 486DX | Band (±) | Notes |
|-------------|:-----:|:--------:|-------|
| NOP | 1 | 0 | baseline |
| MOV r, r | 1 | 0 | register move |
| MOV r, m | 1 | 1 | cache hit; +3 if miss |
| MOV m, r | 1 | 1 | cache hit |
| ADD r, r | 1 | 0 | ALU |
| ADD r, m | 2 | 1 | ALU + memory |
| MUL r8 | 13-18 | 5 | varies by operand |
| MUL r16 | 13-26 | 10 | |
| MUL r32 | 13-42 | 20 | |
| DIV r8 | 16 | 3 | |
| DIV r16 | 24 | 5 | |
| DIV r32 | 40 | 5 | |
| JMP short | 3 | 1 | taken |
| Jcc short (taken) | 3 | 1 | |
| Jcc short (not taken) | 1 | 0 | falls through |
| CALL near | 3 | 1 | |
| RET near | 5 | 1 | |
| PUSH r | 1 | 0 | |
| POP r | 1 | 0 | |
| REP MOVSB | 3+N | N/2 | depends on count |
| REP MOVSD | 3+N | N/2 | faster per byte |

### FPU instruction timing (clocks)

| Instruction | 486DX | Band (±) | Notes |
|-------------|:-----:|:--------:|-------|
| FLD m64 | 3 | 1 | load double |
| FLD m80 | 6 | 2 | load extended |
| FST m64 | 3 | 1 | store double |
| FADD | 8-20 | 10 | operand-dependent |
| FMUL | 16 | 5 | |
| FDIV | 73 | 10 | slowest basic op |
| FSQRT | 83 | 10 | |
| FSIN | 257-354 | 100 | transcendental, range-dependent |
| FCOS | 257-354 | 100 | |

### Cache impact (486DX-33)

| Scenario | Ratio vs cache hit | Notes |
|----------|:------------------:|-------|
| L1 hit | 1.0x | baseline |
| L1 miss (memory) | 3-5x | depends on wait states |
| Cache disabled | 4-8x | all accesses to DRAM |

### Interrupt latency

| Event | Clocks | Band (±) | Notes |
|-------|:------:|:--------:|-------|
| INT instruction | 44 | 10 | real mode |
| Hardware IRQ | 50-100 | 30 | depends on instruction boundary |
| Exception | 40-80 | 20 | depends on type |

### Memory/bus timing

| Access | Clocks | Band (±) | Notes |
|--------|:------:|:--------:|-------|
| Aligned dword read | 1 | 0 | cache hit |
| Misaligned dword read | 3 | 1 | two bus cycles |
| I/O port read | 4-8 | 4 | varies by chipset |
| I/O port write | 4-8 | 4 | |

## Expected ao486 Deviation

| Category | Expected range | Notes |
|----------|:--------------:|-------|
| Integer ALU | ±0-1 clocks | should match closely |
| Memory access | ±2 clocks | FPGA memory timing differs |
| FPU basic | ±10% | acceptable variation |
| FPU transcendental | ±20% | implementation-dependent |
| Interrupts | ±30% | acceptable band |
| Cache miss | ±50% | memory subsystem differs |

## Measurement Procedure

### Warm-up run

```
1. Execute timed code once (populate cache)
2. Execute timed code second time (cache warm)
3. Measure third execution
```

### Iteration count calculation

```
Target measurement time: 10ms (reliable PIT precision)
PIT ticks per 10ms: ~11932 (10ms / 838ns)
Iterations needed: ceil(11932 / expected_clocks_per_iteration)

Example for NOP (1 clock):
  At 33 MHz: 1 clock = 30ns
  10ms = 333,333 clocks
  Need ~333,333 NOP iterations to fill 10ms measurement window
```

### Statistical approach

| Metric | Method |
|--------|--------|
| Mean | average of 3+ runs |
| Deviation | std dev across runs |
| Report | mean ± deviation vs baseline band |

## Known Divergences

- **Never hard-fail:** timing tests are informational. CI reports deviation, not failure.
- **TSC availability:** RDTSC (0x0F 0x31) is available on Pentium and some late 486 CPUs.
  Not available on 8086–80486DX. Detect via CPUID before use.
- **Cache effects:** first run may be uncached; warm-up runs before measuring.
- **Turbo/non-turbo:** some systems have a turbo switch. Report current clock state.
- **PIT precision:** ~838ns resolution means short code sequences (< a few microseconds)
  cannot be measured accurately. Use iteration loops.
- **ao486 clock:** may not be exactly 33 MHz; report effective rate.

## NOT TESTED (deferred to venue C/T)

- Cycle-exact instruction timing
- Bus cycle waveforms
- Wait state timing
- Cache line fill timing
- Prefetch queue behavior
