# Test Venues — What Belongs Where

This document draws the **hard line** between what this suite (a software program
running inside an emulated or real guest) can validate, and what it **cannot** and
must be pushed to host oracle, HDL co-simulation, or a bench/testbench.

Getting this boundary right is the single most important scoping decision in the
project. A test placed in the wrong venue is either impossible to write correctly or
produces false confidence.

---

## 1. The Four Venues

| Venue | What runs | What it can observe | Authority |
|-------|-----------|---------------------|-----------|
| **G — Guest** (this suite) | A DOS/bare-metal x86 program on ao486 / emulator / real HW | Only **software-visible architectural state**: GPRs, flags, segment/descriptor state, memory, exceptions, peripheral *register* state, gross/aggregate timing | Black-box, end-to-end |
| **H — Host Oracle** | The same `UNIVERSAL` test bytes on a trusted native CPU (Linux/Win32) | Same software-visible state, but on a *reference* CPU | Ground truth for defined behavior only |
| **C — Co-simulation** | RTL (Verilator/Icarus) driven by SingleStepTests-style vectors | Full CPU state injection + read-back **per instruction**, plus internal signals exposed by the RTL | Microarchitecture, per-instruction exactness |
| **T — Testbench / Bench** | HDL testbench or logic-analyzer on real silicon/board | Pin-level bus protocol, cycle timing, wait states, cache-fill bursts, arbitration | Electrical / cycle / bus behavior |

The guest suite **is venue G**. Everything below classifies each behavior as
G-suitable or not, and if not, names the venue that owns it.

---

## 2. The Governing Question

A behavior is **guest-testable (G)** if and only if BOTH hold:

1. **Observable** — its effect surfaces in software-visible architectural state
   (a register, a flag, memory, an exception, a device register, or a timing delta
   large enough to measure with PIT/TSC above noise).
2. **Constructible** — the required precondition state can be *set up from software*
   without the setup itself destroying what you're trying to observe.

If it fails **Observable**, it belongs to **C** (internal signals) or **T** (pins).
If it fails **Constructible**, it belongs to **C** (arbitrary state injection).

---

## 3. Guest-Testable (G) — The Bulk of This Suite

These are software-visible and software-constructible. This is where the project's
value concentrates.

| Domain | Why G works |
|--------|-------------|
| Instruction functional results | dest register/memory is directly readable |
| Flag outputs (incl. undefined-but-deterministic) | PUSHF reads them; pin golden values |
| Exception occurrence, vector, error code, pushed CS:IP | handler observes all of it |
| Fault-vs-trap restart semantics | pushed CS:IP distinguishes them |
| Descriptor load side effects (Accessed bit) | re-read the descriptor from memory |
| Privilege/limit/type/present checks | they raise observable faults |
| Paging translation *results*, #PF error code, final A/D bits, TLB staleness | translation outcome + faults are observable |
| Mode transitions (real↔PM↔V86, unreal) functional correctness | post-transition behavior is observable |
| A20 wrap | read `FFFF:0010` vs `0000:0000` |
| SMC / cache coherence *functional* result | fetched bytes' effect is observable |
| Peripheral register R/W and **stateful** behavior (PIC EOI/spurious, PIT latch/readback, DMA TC, RTC UIP, VGA flip-flop, UART FIFO/loopback) | all via port reads and resulting IRQs |
| FPU numeric results, special values, condition codes, exception flags, save/restore images | stored to memory and compared |
| Gross timing **bands** and ratios (cached vs uncached loop, taken vs not-taken) | aggregate PIT/TSC measurement |

---

## 4. NOT Guest-Testable — And Where It Goes

### 4.1 Fails "Observable" → Co-sim (C) or Testbench (T)

| Behavior | Why not G | Venue |
|----------|-----------|-------|
| Exact per-instruction **cycle count** | guest timing is polluted by prefetch, refresh, IRQs; can't isolate one instruction deterministically | **C** (RTL cycle count) / **T** (silicon) |
| Prefetch queue **depth & fill order** | internal; only crude SMC side-effects leak | **C** / **T** |
| Cache **line-fill bursts, LRU/replacement, internal tags** | only gross hit/miss *timing* leaks, not structure | **C** / **T** |
| Bus **wait states, pin protocol, BE#/ADS#/RDY# timing** | electrical, invisible to software | **T** |
| DMA/refresh **cycle-stealing exact timing** | only aggregate throughput leaks | **T** (**C** if bus modeled) |
| Microcode **sequencing / internal temporaries** | never surfaces | **C** / **T** |
| FPU **internal 68-bit datapath / guard-round-sticky bits** | only the rounded result surfaces | **C** |
| Signals the RTL exposes for debug (valid, stall, forward) | not architectural | **C** |
| Post-**triple-fault reset** sequence | guest is dead; can't observe from within | **C** / **T** |
| Power-on / **reset default state** | no software has run yet to read it | **C** / **T** |

### 4.2 Fails "Constructible" → Co-sim (C)

The guest can only reach states it can build with instruction sequences, and the
building perturbs flags/registers. Co-sim injects arbitrary state atomically.

| Behavior | Why not G | Venue |
|----------|-----------|-------|
| Exhaustive **operand × flag** sweeps (e.g. every 2^32 × CF/DF combo) | combinatorially impossible to enumerate from a program in reasonable time | **C** (vector-driven) |
| Precise **simultaneous-exception priority** | hard to make two faults occur on the exact same instruction from software | **C** |
| **Mid-instruction interruption** points | not addressable from software | **C** / **T** |
| Arbitrary **reserved-bit / illegal descriptor** combos | many can't be loaded without first faulting | **C** (partly G via LOADALL) |
| Exact **A/D-bit update atomicity/ordering** | result is G; *timing/atomicity* is not | **C** / **T** |
| **Boundary-straddle at electrical level** (bus split of a misaligned access) | functional result is G; bus behavior is T | **T** |

### 4.3 Guest-*Partial* (G-assist) — Observable but Weak; Corroborate Elsewhere

These yield *something* from the guest but are authoritative only in C/T:

| Behavior | Guest gives | Authoritative venue |
|----------|-------------|---------------------|
| Cache hit/miss | timing *band* proving caching happens | C/T for structure |
| Prefetch effects | SMC stale-vs-fresh yes/no (8086/8088) | C/T for depth |
| Instruction timing | ratios & bands, not exact cycles | C for cycles |
| Interrupt latency | coarse INT→handler delta | C for exact |

---

## 5. Decision Flowchart

```
                        ┌─────────────────────────────┐
                        │  Behavior to validate        │
                        └──────────────┬──────────────┘
                                       ▼
                     ┌─────────────────────────────────────┐
                     │ Software-visible architectural effect?│
                     └───────────────┬───────────────┬──────┘
                                 no  │               │ yes
                                     ▼               ▼
                        ┌────────────────┐   ┌────────────────────────────┐
                        │ Pin/electrical? │   │ Constructible from software │
                        └───────┬─────┬──┘   │ without destroying the obs.? │
                            yes  │     │ no   └──────────┬──────────┬───────┘
                                 ▼     ▼             yes │          │ no
                            ┌──────┐ ┌──────┐            ▼          ▼
                            │  T   │ │  C   │       ┌────────┐  ┌────────┐
                            │bench │ │co-sim│       │  G     │  │  C     │
                            └──────┘ └──────┘       │ guest  │  │co-sim  │
                                                    └───┬────┘  └────────┘
                                                        │
                                          UNIVERSAL tier? also run H (oracle)
```

---

## 6. Division of Labor with SingleStepTests & ZXALL

| Suite | Venue | Owns |
|-------|-------|------|
| **This suite (x86-validation)** | **G** (+ H for UNIVERSAL) | End-to-end guest correctness on ao486: functional ISA/FPU results & flags, exceptions, PM/paging outcomes, **peripheral stateful behavior**, mode transitions, gross timing bands |
| **SingleStepTests** | **C** | Per-instruction exhaustive state vectors for RTL co-sim; also imported into G for edge-case values where constructible |
| **ZXALL** | **G** | Guest-side compatibility methodology we adopt |
| **HDL testbenches (ao486 repo)** | **T** | Bus protocol, cache fills, wait states, cycle timing |
| **Host oracle** | **H** | Confirms UNIVERSAL expected values on trusted silicon before trusting them against ao486 |

Peripheral/system-integration behavior (PIC, PIT, DMA, VGA, IDE, mode switches, A20)
is **uniquely ours** — SingleStepTests is CPU-core only and co-sim rarely wires full
peripherals. This is the project's strongest, least-duplicated contribution.

---

## 7. Rules of Placement (enforced in review)

1. If a proposed test needs a cycle-exact count → **reject from G**, route to C, and,
   if the guest can still measure a *band*, keep only the band as `TIMING` tier.
2. If it needs arbitrary state injection → route to C (or use LOADALL in G only when
   the state is genuinely constructible and the test documents it).
3. If it observes pins/bus → **T only**.
4. If it is software-visible and constructible → **G**, and if `UNIVERSAL`, add **H**.
5. Every test's header names its venue (`VENUE: G | G-assist | H`) — C/T items are not
   in this repo's test tree; they are tracked as references to the co-sim/bench repos.
