# Test Module Specifications — Index

Detailed per-module design specs.  Each spec is a self-contained document
that a test author can implement from without needing to reverse-engineer
intent from the coverage matrix or implementation plan.

**Relationship to other docs:**

```
doc/
├── prd.md                  — what & why (product requirements)
├── technical-design.md     — architecture: runner, MODULE_HEADER, macros, shims
├── coverage-matrix.md      — WHAT areas + hard cases (the "matrix")
├── prep-analysis.md        — HOW each area breaks into cases + divergences
├── implementation-plan.md  — WHEN each module is built (phased checklist)
├── test-venues.md          — WHERE each test runs (G/H/C/T)
├── adding-tests.md         — HOW to write a test (tutorial + patterns)
├── external-integration.md — external suite import analysis
├── references.md           — datasheets, manuals, external suites
└── specs/                  — THIS FOLDER: per-module construction specs
    ├── index.md            — this file (enumeration + cross-links)
    ├── 8086/               — 8086/88 CPU core ISA (arithmetic, logic, shift, BCD, string, …)
    ├── x87/                — 8087/287/387/486 FPU ISA (load/store, arithmetic, specials, …)
    ├── 80186-286/          — 80186 extensions + 80286 protected mode
    ├── 80386/              — 80386 32-bit ISA (paging, V86, TSS, debug regs, …)
    ├── 80486/              — 80486 additions (CMPXCHG, CPUID, cache, WP, …)
    ├── peripheral/         — PC hardware peripherals (PIC, PIT, DMA, KBC, RTC, IDE, VGA, …)
    ├── system/             — system integration (A20, exceptions, mode transitions, …)
    └── timing/             — timing constellations
```

**Each spec file follows this template:**

1. **Metadata** — module name, source file, TIER, VENUE, GEN, ORACLE, impl-plan rows
2. **Cross-references** — links to coverage-matrix section, prep-analysis section, adding-tests patterns
3. **Prerequisites** — shared infrastructure needed (GDT, IDT, exception handlers, etc.)
4. **Test cases** — per-case: setup, inputs, expected result + flags, oracle source
5. **State save/restore** — what global state is touched, how it's restored
6. **Known divergences** — per-generation differences (from prep-analysis §1.2/§1.2a)
7. **Pass/fail criteria** — what constitutes PASS, FAIL, SKIP for this module

---

## Full Enumeration (by ISA scope)

### 8086 — 8086/88 CPU Core (12 specs)

Coverage: [coverage-matrix §3](../coverage-matrix.md#3-cpu--80868088-pri-1-foundation)
Divergences: [prep-analysis §1](../prep-analysis.md#1-cross-cpu-divergence-catalog)
Pattern: [adding-tests.md "Example: Testing ADD"](../adding-tests.md#example-testing-add-instruction)

| Spec | File | Impl-plan area | Coverage § | Pri |
|------|------|----------------|------------|:---:|
| 8086 Smoke | [8086/smoke.md](8086/smoke.md) | 8086-Smoke | §3 | 1 |
| 8086 Arithmetic | [8086/arith.md](8086/arith.md) | 8086-Arith | §3, §3.1, §3.2 | 1 |
| 8086 Logic | [8086/logic.md](8086/logic.md) | 8086-Logic | §3, §3.1 | 1 |
| 8086 Shift/Rotate | [8086/shift.md](8086/shift.md) | 8086-Shift | §3, §3.1 | 1 |
| 8086 BCD | [8086/bcd.md](8086/bcd.md) | 8086-BCD | §3, §3.2 | 2 |
| 8086 String | [8086/string.md](8086/string.md) | 8086-String | §3 | 1 |
| 8086 Control Flow | [8086/control.md](8086/control.md) | 8086-Ctrl | §3 | 2 |
| 8086 Stack | [8086/stack.md](8086/stack.md) | 8086-Stack | §3, §3.1 | 2 |
| 8086 Segment Ops | [8086/segment.md](8086/segment.md) | 8086-Seg | §3 | 2 |
| 8086 Misc | [8086/misc.md](8086/misc.md) | 8086-Misc | §3 | 3 |
| 8086 Encoding | [8086/encoding.md](8086/encoding.md) | 8086-Enc | §3, §3.3 | 2 |
| 8086 Flags | [8086/flags.md](8086/flags.md) | 8086-Flags | §3 | 2 |

### x87 — 8087/287/387/486 FPU (12 specs)

Coverage: [coverage-matrix §4](../coverage-matrix.md#4-fpu--8087--287--387--486-pri-1-a-domain-of-its-own)
Divergences: [prep-analysis §5](../prep-analysis.md#5-fpu-corner-cases), [§10](../prep-analysis.md#10-fpu-state-image-format-detail)

| Spec | File | Impl-plan area | Coverage § | Pri |
|------|------|----------------|------------|:---:|
| x87 Detection | [x87/detect.md](x87/detect.md) | FPU-Detect | §4 | 1 |
| x87 Basic Load/Store | [x87/basic.md](x87/basic.md) | FPU-Basic | §4 | 1 |
| x87 Arithmetic | [x87/arith.md](x87/arith.md) | FPU-Arith | §4, §4.2 | 1 |
| x87 Special Values | [x87/special.md](x87/special.md) | FPU-Special | §4, §4.1 | 1 |
| x87 Compare | [x87/compare.md](x87/compare.md) | FPU-Compare | §4, §4.4 | 1 |
| x87 Stack/Tag | [x87/stack.md](x87/stack.md) | FPU-Stack | §4, §4.3 | 1 |
| x87 Control | [x87/control.md](x87/control.md) | FPU-Ctrl | §4 | 1 |
| x87 Exceptions | [x87/exception.md](x87/exception.md) | FPU-Exc | §4, §4.7 | 1 |
| x87 Save/Restore | [x87/save.md](x87/save.md) | FPU-Save | §4, §4.7 | 1 |
| x87 Transcendentals | [x87/trans.md](x87/trans.md) | FPU-Trans | §4, §4.5 | 2 |
| x87 Partial Remainder | [x87/prem.md](x87/prem.md) | FPU-PREM | §4, §4.6 | 2 |
| x87 Constants | [x87/const.md](x87/const.md) | FPU-Const | §4 | 3 |

### x87 — FPU Generation Differences (1 additional spec)

| Spec | File | Impl-plan area | Coverage § | Pri |
|------|------|----------------|------------|:---:|
| x87 Generation Differences | [x87/generations.md](x87/generations.md) | FPU-Gen | §4 | 1 |

### 80186-286 — 80186 Extensions + 80286 Protected Mode (12 specs)

Coverage: [coverage-matrix §5](../coverage-matrix.md#5-cpu--80186-pri-3-thin-layer), [§6](../coverage-matrix.md#6-cpu--80286-pri-1-for-pm-the-first-big-divergence-surface)
Divergences: [prep-analysis §2](../prep-analysis.md#2-protected-mode--paging--full-check-matrix), [§1.2a](../prep-analysis.md#12a-generation-specific-divergences-286-vs-386-vs-486)
Pattern: [adding-tests.md "RING0 Self-Switching"](../adding-tests.md#ring0-self-switching-pm-pattern)

| Spec | File | Impl-plan area | Coverage § | Pri |
|------|------|----------------|------------|:---:|
| 80186 Smoke | [80186-286/186-smoke.md](80186-286/186-smoke.md) | 186-Smoke | §5 | 0 |
| 80186 New Instructions | [80186-286/186-new.md](80186-286/186-new.md) | 186 | §5 | 2 |
| 80186 ENTER/LEAVE | [80186-286/186-stack.md](80186-286/186-stack.md) | 186-Stack | §5 | 2 |
| 80186 INS/OUTS | [80186-286/186-io-string.md](80186-286/186-io-string.md) | 186-IO | §5 | 2 |
| 80186 BOUND | [80186-286/186-bound.md](80186-286/186-bound.md) | 186-BOUND | §5 | 2 |
| 286 Smoke | [80186-286/286-smoke.md](80186-286/286-smoke.md) | 286-Smoke | §6 | 0 |
| 286 Real-Mode Extensions | [80186-286/286-real.md](80186-286/286-real.md) | 286-Real | §6 | 2 |
| 286 PM Infrastructure | [80186-286/286-pm-infra.md](80186-286/286-pm-infra.md) | 286-PM | §6 | 1 |
| 286 Descriptor Checks | [80186-286/286-descriptors.md](80186-286/286-descriptors.md) | 286-Desc | §6, §6.1 | 1 |
| 286 Limit Enforcement | [80186-286/286-limit.md](80186-286/286-limit.md) | 286-Limit | §6, §6.2 | 1 |
| 286 Exceptions | [80186-286/286-exceptions.md](80186-286/286-exceptions.md) | 286-Exc | §6 | 1 |
| 286 System Instructions | [80186-286/286-system.md](80186-286/286-system.md) | 286-Sys, 286-Desc | §6, §6.3, §6.4 | 2 |

### 80386 — 32-bit ISA, Paging, V86 (10 specs)

Coverage: [coverage-matrix §7](../coverage-matrix.md#7-cpu--80386-pri-1-32-bit--paging--v86)
Divergences: [prep-analysis §2](../prep-analysis.md#2-protected-mode--paging--full-check-matrix), [§7](../prep-analysis.md#7-tss-task-switch-matrix), [§8](../prep-analysis.md#8-v86-mode--iopl-sensitivity-matrix), [§9](../prep-analysis.md#9-exception-priority-matrix)
Pattern: [adding-tests.md "Exception Handler"](../adding-tests.md#exception-handler-pattern)

| Spec | File | Impl-plan area | Coverage § | Pri |
|------|------|----------------|------------|:---:|
| 386 Smoke | [80386/386-smoke.md](80386/386-smoke.md) | 386-Smoke | §7 | 0 |
| 386 32-bit Operations | [80386/32bit.md](80386/32bit.md) | 386-32bit, 386-Addr | §7 | 1 |
| 386 New Instructions | [80386/new.md](80386/new.md) | 386-New | §7 | 1 |
| 386 Call Gates | [80386/gates.md](80386/gates.md) | 386-Gate | §7, ext-int §3 | 1 |
| 386 TSS Task Switch | [80386/tss.md](80386/tss.md) | 386-TSS | §7, ext-int §2.3 | 2 |
| 386 Segment Limits (32-bit + G) | [80386/limits.md](80386/limits.md) | 386-Limit | §7 | 1 |
| 386 Paging | [80386/paging.md](80386/paging.md) | 386-Page | §7, §7.1 | 1 |
| 386 V86 Mode | [80386/v86.md](80386/v86.md) | 386-V86 | §7 | 2 |
| 386 Debug Registers | [80386/debug.md](80386/debug.md) | 386-Debug | §7 | 2 |
| 386 Control Registers | [80386/cr.md](80386/cr.md) | 386-CR | §7 | 2 |

### 80486 — 486 Additions (6 specs)

Coverage: [coverage-matrix §8](../coverage-matrix.md#8-cpu--80387--80486-pri-12)
Divergences: [prep-analysis §1.2a](../prep-analysis.md#12a-generation-specific-divergences-286-vs-386-vs-486)

| Spec | File | Impl-plan area | Coverage § | Pri |
|------|------|----------------|------------|:---:|
| 486 Smoke | [80486/486-smoke.md](80486/486-smoke.md) | 486-Smoke | §8 | 0 |
| 486 New Instructions | [80486/new.md](80486/new.md) | 486-New | §8, §8.1 | 1 |
| 486 Cache Coherence | [80486/cache.md](80486/cache.md) | 486-Cache | §8, §8.2 | 1 |
| 486 CPUID | [80486/cpuid.md](80486/cpuid.md) | 486-CPUID | §8, §8.4 | 2 |
| 486 Alignment Check | [80486/ac.md](80486/ac.md) | 486-AC | §8, §8.3 | 2 |
| 486 Write Protect | [80486/wp.md](80486/wp.md) | 486-WP | §7.1 | 2 |

### Peripheral — PC Hardware (10 specs)

Coverage: [coverage-matrix §9](../coverage-matrix.md#9-peripherals-pri-12--the-projects-least-duplicated-coverage)
Detail: [prep-analysis §6](../prep-analysis.md#6-peripheral-stateful-behavior), [§6.2a](../prep-analysis.md#62a-pit-mode-specific-behavior-matrix), [§11](../prep-analysis.md#11-ideata-stateful-behavior-matrix)

| Spec | File | Impl-plan area | Coverage § | Pri |
|------|------|----------------|------------|:---:|
| Peripheral Smoke | [peripheral/peripheral-smoke.md](peripheral/peripheral-smoke.md) | Periph-Smoke | §9 | 0 |
| 8259 PIC | [peripheral/pic.md](peripheral/pic.md) | PIC | §9, §9.1 | 1 |
| 8254 PIT | [peripheral/pit.md](peripheral/pit.md) | PIT | §9, §9.2 | 1 |
| 8237 DMA | [peripheral/dma.md](peripheral/dma.md) | DMA | §9, §9.3 | 2 |
| 8042 KBC | [peripheral/kbc.md](peripheral/kbc.md) | KBC | §9, §9.4 | 2 |
| MC146818 RTC | [peripheral/rtc.md](peripheral/rtc.md) | RTC | §9, §9.5 | 2 |
| IDE/ATA | [peripheral/ide.md](peripheral/ide.md) | IDE | §9, §9.6 | 2 |
| VGA | [peripheral/vga.md](peripheral/vga.md) | VGA | §9, §9.7 | 2 |
| Sound (Speaker/OPL/SB) | [peripheral/sound.md](peripheral/sound.md) | Sound | §9 | 3 |
| UART 8250/16550 | [peripheral/uart.md](peripheral/uart.md) | UART | §9, §9.8 | 2 |

### System — Integration & Boundaries (6 specs)

Coverage: [coverage-matrix §10](../coverage-matrix.md#10-system-integration-pri-1--uniquely-guest-observable)
Detail: [prep-analysis §9](../prep-analysis.md#9-exception-priority-matrix)

| Spec | File | Impl-plan area | Coverage § | Pri |
|------|------|----------------|------------|:---:|
| System Smoke | [system/system-smoke.md](system/system-smoke.md) | System-Smoke | §10 | 0 |
| A20 Gate | [system/a20.md](system/a20.md) | A20 | §10, §10.1 | 1 |
| Interrupt Boundaries | [system/int-boundaries.md](system/int-boundaries.md) | IntBound | §10, §10.2 | 1 |
| Exception Taxonomy | [system/exceptions.md](system/exceptions.md) | Except | §10, §10.2 | 1 |
| Mode Transitions | [system/mode-transitions.md](system/mode-transitions.md) | Mode | §10 | 1 |
| Memory Map | [system/memory-map.md](system/memory-map.md) | Memory | §10 | 3 |

### Timing — Measurement Constellations (1 spec)

Coverage: [coverage-matrix §11](../coverage-matrix.md#11-timing-constellations-pri-4--bands-never-hard-fail)

| Spec | File | Impl-plan area | Coverage § | Pri |
|------|------|----------------|------------|:---:|
| Timing Constellations | [timing/timing.md](timing/timing.md) | Timing | §11 | 4 |

---

**Total: 70 spec files across 8 ISA-scoped subfolders.**

Build order follows [coverage-matrix §14](../coverage-matrix.md#14-prioritized-build-order-max-bug-yield-first),
NOT the folder order. Within each scope, implement in §14 priority order.
