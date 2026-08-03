# AGENTS.md — Rules for Building & Maintaining the x86 Validation Suite

Guidance for AI agents and human contributors working on this project. Read this
before writing a test, touching the build system, or opening a PR.

Companion docs:
- [doc/implementation-plan.md](doc/implementation-plan.md) — **master checklist with all phases and tasks**
- [doc/specs/index.md](doc/specs/index.md) — **detailed per-module test specifications (59 files: exact inputs, expected outputs, flags, divergences)**
- [doc/prd.md](doc/prd.md) — what and why
- [doc/technical-design.md](doc/technical-design.md) — architecture & module interface
- [doc/test-venues.md](doc/test-venues.md) — **guest vs host vs co-sim vs bench delimitation (read before scoping any test)**
- [doc/coverage-matrix.md](doc/coverage-matrix.md) — per-area coverage + hard-case catalog + venue mapping
- [doc/external-integration.md](doc/external-integration.md) — test386.asm & SingleStepTests import analysis
- [doc/adding-tests.md](doc/adding-tests.md) — step-by-step test-writing tutorial
- [doc/references.md](doc/references.md) — datasheets, manuals, external suites

**AGENTS.md is the rulebook; adding-tests.md is the tutorial.** When they overlap,
AGENTS.md wins.

---

## 0. Prime Directive

**Priority #1 is MS-DOS in all CPU modes**, because the primary consumer is
**ao486 on MiSTer FPGA**, validated by booting DOS and running these tests on the
core. Linux and Win32 targets are secondary and exist mainly as an **oracle
cross-check** (see §4.4). Never let a Linux/Win32 convenience compromise the DOS
build or DOS behavior.

---

## 1. Non-Negotiable Principles

Every test MUST be:

1. **Self-checking** — the test decides PASS/FAIL itself and reports a status code.
   No human eyeballing output.
2. **Non-corrupting** — it snapshots and restores any global state it touches (FPU
   stack, descriptor tables, PIC masks, PIT counters, video regs, DF, segment regs).
   A test that dirties state poisons every test after it.
3. **Generation-gated** — it checks CPU/FPU capability first and `SKIP`s cleanly on
   unsupported hardware. A 386 test on a 286 must SKIP, never `#UD`-crash.
4. **Deterministic** — same inputs → same result. Any entropy (RTC, timer seed) is
   logged so a failure is reproducible.
5. **Bounded** — it cannot hang. Loops have iteration ceilings; hardware polls have
   timeouts; a watchdog path exists.
6. **Documented** — a header comment states what is tested, expected behavior, the
   **datasheet/manual reference**, and any known cross-CPU divergence.
7. **Isolated & re-runnable** — running it twice, or in any order, yields the same
   result. No hidden ordering dependencies between tests.

A test that cannot satisfy all seven is not merged.

---

## 2. What We Are Actually Testing

We chase the **corners emulators miss**, not the happy path games already exercise.
Before writing a test, consult [coverage-matrix.md](doc/coverage-matrix.md) §14
(prioritized build order) and the per-area hard-case catalogs. If your test only proves
"ADD adds," it has low value unless it also nails the flag corners.

The oracle problem is real: **how do we know the expected answer?** Ranked by trust:

1. **Architectural definition** — Intel manual says exactly this (most instructions).
2. **Golden vector from real silicon** — for "undefined-but-deterministic" behavior,
   we pin the observed value from a reference chip and assert byte-exact match.
3. **Differential** — run the same logic on a known-good reference (host CPU via the
   Linux/Win32 oracle build, or a trusted emulator) and compare.
4. **Cross-suite** — corroborate against SingleStepTests / ZXALL vectors.

Mark each test's oracle source in its header (`ORACLE: manual | golden | diff | xsuite`).

---

## 3. Environment Tiers — Which Targets a Test Can Build For

**Not every test can run on every platform.** A real-mode or ring-0 test cannot run
in Linux/Win32 userspace. Every test declares exactly one tier; the build system uses
it to decide which target executables include it.

| Tier | Meaning | DOS real | DOS PM (ring0) | Linux/Win32 userspace |
|------|---------|:--------:|:--------------:|:---------------------:|
| `UNIVERSAL` | Pure ISA/FPU logic, no privilege, no mode assumptions | ✅ | ✅ | ✅ (oracle) |
| `REALMODE` | Requires real mode / segmented 1MB / A20 / real-mode IVT | ✅ | — | — |
| `RING0` | Needs CPL0: CRn/DRn, descriptor tables, paging, PM transitions, `HLT`, `CLI` | ✅ (self-switch) | ✅ | — |
| `HARDWARE` | Touches peripherals / ports / IRQs / DMA | ✅ | ✅ | — |
| `TIMING` | Measurement-based, needs known clock/board | ✅ | ✅ | — (host-untrusted) |

Rules:
- `UNIVERSAL` tests are the only ones that also build for Linux/Win32. They are our
  oracle cross-check — the same bytes, run on a trusted host CPU, confirm our expected
  values before we trust them against ao486.
- `RING0`/paging/V86/PM-transition tests under DOS **do their own mode switching**.
  Do **not** rely on a DPMI host (that abstracts away the very CPU behavior we test).
- `HARDWARE` and `TIMING` are DOS/bare-metal only and must guard against a hostile
  environment (unexpected TSRs, an emulator that stubs a device).
- Declare the tier in the module header (see §6) so the linker can include/exclude it
  per target.

---

## 4. Cross-Platform Build Architecture

### 4.1 One Source, Many Targets

Assembly is written **once** in NASM against the shared includes. Platform difference
is handled by:
- a per-target **entry/runtime shim** (process startup, exit, console/serial/file I/O),
- a build-time symbol `TARGET_{DOS,LINUX,WIN32}` and `MODE_{REAL,PM16,PM32}`,
- the tier gate from §3.

Test *logic* never contains OS calls directly — it uses the framework's output/abort
API, which each target implements.

```
                    ┌────────────────────────┐
                    │   Shared test sources   │  (NASM, tier-tagged)
                    │   + include/*.inc       │
                    └───────────┬────────────┘
             ┌──────────────────┼──────────────────┐
             ▼                  ▼                  ▼
      ┌────────────┐    ┌────────────┐     ┌────────────┐
      │  DOS shim  │    │ Linux shim │     │ Win32 shim │
      │ real+PM    │    │  ELF32/64  │     │    PE32    │
      └─────┬──────┘    └─────┬──────┘     └─────┬──────┘
            ▼                 ▼                  ▼
      X86VAL.EXE (MZ)   x86val (ELF)       x86val.exe (PE)
      [all tiers]       [UNIVERSAL only]   [UNIVERSAL only]
```

### 4.2 Toolchain (host-agnostic: Linux, macOS, Windows)

| Purpose | Tool | Notes |
|---------|------|-------|
| Assembler | **NASM 2.14+** | single source of truth for all targets |
| DOS link (MZ .EXE) | **wlink** (OpenWatcom) or **jwlink** | `nasm -f obj` → linked MZ |
| DOS tiny (.COM) | `nasm -f bin` | for the smallest real-mode probes |
| Linux link | **ld** (binutils) / gcc | `nasm -f elf32` / `-f elf64` |
| Win32 link | **ld** (mingw-w64) / GoLink / polink | `nasm -f win32` |
| Emulator (test) | **DOSBox-X**, **86Box**, **PCem** | DOSBox-X primary for quick loop |
| Boot image | `tools/bootimg.py` | standalone bootable (secondary priority) |
| Real target | **ao486 on MiSTer** | the acceptance platform |

Keep the toolchain buildable on a plain Linux/macOS host — no proprietary DOS-only
assemblers. NASM + OpenWatcom `wlink` covers DOS from any host.

### 4.3 Build Invocations

```bash
make                 # default: DOS build, all tiers  -> build/bin/X86VAL.EXE
make dos             # explicit DOS (real + self-switched PM), all tiers
make linux           # ELF, UNIVERSAL tier only (oracle)
make win32           # PE,  UNIVERSAL tier only (oracle)
make oracle          # linux + win32, run locally, dump expected-value vectors
make boot            # bootable image (secondary)

make cpu-8086        # subset build (see Makefile for all subsets)
make clean
```

Every target must build clean with zero warnings before a PR.

### 4.4 Temporary Files — Use `scratch/`

**All temporary files go to `scratch/` in the project root.** This directory is
gitignored and must never be committed.

```
x86-validation-suite/
├── scratch/              # ← ALL temp files here (gitignored)
│   ├── results_*.txt     # Test output captures
│   ├── dosbox-temp.conf  # Generated configs
│   ├── poc01_*.json      # POC intermediate files
│   └── ...
├── build/                # Build artifacts (also gitignored)
└── ...
```

Rules:
- Scripts MUST use `$PROJECT_ROOT/scratch/`, never local temp dirs
- Name files descriptively: `poc01_results_20260803.txt`, not `tmp.txt`
- Clean up old files periodically (not automated)
- Never hardcode `/tmp` or similar — use `scratch/`

Example in shell scripts:
```bash
PROJECT_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SCRATCH="$PROJECT_ROOT/scratch"
mkdir -p "$SCRATCH"
RESULT="$SCRATCH/test_results_$(date +%Y%m%d_%H%M%S).txt"
```

### 4.4 The Oracle Cross-Check Workflow

`UNIVERSAL` tests carry expected values. To trust those values:

```bash
make oracle                        # build+run UNIVERSAL tests on the host CPU
# -> emits data/vectors/oracle_<arch>.json (host CPU is the reference)
```
Then the DOS/ao486 run is compared against that oracle. A mismatch means either a core
bug (good — we found one) or a bad expected value (fix the test). Document which.

Caveat: the host is a *modern* CPU. For "undefined-but-deterministic" flags that
changed across generations, the host is NOT authoritative — use a period-correct
golden vector instead and tag `ORACLE: golden`.

---

## 5. Directory & Naming Conventions

```
src/
  core/                     framework (runner, output, config, detect, timing, memory)
  arch/                     per-target shims: dos/, linux/, win32/
  cpu/<gen>/<group>.asm     8086 80186 80286 80386 80486 ; groups: arith,logic,shift,...
  fpu/<gen>/<group>.asm     8087 80287 80387 80486
  peripheral/<dev>/<x>.asm  pic pit dma kbc rtc ide vga sound serial
  timing/                   measurement constellations
include/                    test.inc x86.inc ports.inc fpu.inc pmode.inc
tests/                      imported/golden vectors (SingleStepTests, ZXALL, reference)
tools/                      importers, comparators, boot image, stats
```

Naming:
- Files: lowercase, `snake` if needed, grouped by function (`arith.asm`, not `add.asm`).
- Test functions: `test_<insn>_<variant>` (`test_shl_r16_cl_count0`).
- Labels: local `%%` inside macros; module labels prefixed by area (`fpu_`, `pic_`).
- One conceptual area per module; keep modules < 64 KB (NFR-7).

---

## 6. How To Write a Test (Rules)

Follow [adding-tests.md](doc/adding-tests.md) for the full walkthrough, and
[doc/specs/index.md](doc/specs/index.md) for the exact test-case tables, expected
values, and per-module state save/restore contracts. The rules that gate a merge:

### 6.1 Mandatory Module Header

```nasm
;============================================================================
; MODULE: cpu/8086/shift.asm
; TIER:   UNIVERSAL              ; build target: one of §3 tiers
; VENUE:  G                      ; test venue: G | G-assist | H (see test-venues.md)
; GEN:    8086+                  ; minimum CPU; note per-test overrides
; ORACLE: manual + golden        ; how expected values are justified
; DESC:   SHL/SHR/SAR/ROL/ROR/RCL/RCR — result & flag corners, count masking
; REFS:   Intel 8086 Family Users Manual §2.6; iAPX286 PRM §3 (count mask)
;============================================================================
```

`TIER` (which target executable) and `VENUE` (guest-testable or not) are independent
axes. A test only lives in this repo if its `VENUE` is `G` or `G-assist` (plus `H` for
`UNIVERSAL`). Cycle-exact/internal/pin behavior (`VENUE` C or T) does **not** belong
here — track it in the co-sim/bench references. See [test-venues.md](doc/test-venues.md).

Plus the binary `MODULE_HEADER` struct (magic/version/init/run/cleanup/table) from
[technical-design.md](doc/technical-design.md) §2.1.

### 6.2 Per-Test Header

State the cases, expected result **and flags**, the reference, and known divergence:

```nasm
;----------------------------------------------------------------------------
; test_shl_r16_cl_count0 — SHL r16, CL with CL=0 leaves ALL flags unchanged
; Cases: CL=0 with pre-set/pre-clear flags; assert flags identical afterward
; Ref:   iAPX286 PRM — shift by 0 is a no-op incl. flags
; Diverge: 8086 masks nothing but count 0 is still no-op; behavior same here
;----------------------------------------------------------------------------
```

### 6.3 Required Patterns

- **Capability gate first.** Call `require_cpu`/`require_fpu` and `SKIP` if unmet.
- **Snapshot/restore** every global you touch. Use the provided
  `SAVE_STATE`/`RESTORE_STATE` helpers; for peripherals use the device's
  `*_save`/`*_restore`.
- **Assert result AND flags.** Never check the result and ignore flags for arithmetic/
  logic/shift ops — flags are where the bugs live.
- **On failure, record detail**: expected, actual, and a message (`RECORD_FAILURE`).
  A bare `STATUS_FAIL` with no detail is rejected.
- **No OS calls in test logic.** Emit output only through the framework API so the
  same source builds for every target.
- **No magic numbers.** Use the symbolic constants in `include/*.inc`; add new ones
  there, not inline.

### 6.4 FPU-Specific Rules

- `FNINIT` at entry if you need a known state; restore the caller's FPU state on exit.
- Compare 80-bit results via stored image + integer compare, not via `FCOMPP` alone
  (which itself can raise the exceptions you're testing).
- Mask/unmask exceptions explicitly; never assume the incoming control word.

### 6.5 Peripheral/Hardware Rules

- Disable interrupts (`CLI`) only across the minimal critical section; always re-enable.
- Restore PIC masks, PIT modes/counts, DMA state, and video registers exactly.
- Timeout every `IN`-poll loop (a stubbed device in an emulator must not hang you).
- Never trigger a real destructive action (no disk writes to real media without an
  explicit opt-in flag and a scratch target).

---

## 7. Coding Standards (NASM)

- NASM syntax, Intel operand order, explicit operand sizes (`mov word [x], 0`).
- `BITS 16` / `BITS 32` blocks are explicit; never rely on default.
- Comments explain **why / which spec**, not what the mnemonic obviously does.
- One instruction per line; align operands for readability, not obsessively.
- Reference the datasheet/manual section for any non-obvious sequence (esp. peripheral
  init and mode switches).
- Portable across NASM targets: no `-f obj`-only or `-f elf`-only constructs in shared
  test logic — target-specifics live in `src/arch/<target>/`.
- Reproducible builds: no timestamps, no host paths baked into output.

---

## 8. Quality Gates (must pass before merge)

A change is mergeable only when ALL hold:

1. **Builds clean, zero warnings**, for every target the touched tier requires
   (`make dos` always; `make linux win32` if the test is `UNIVERSAL`).
2. **Runs green on DOSBox-X** (real mode) and, for `RING0`/PM tests, on **86Box**
   (better protected-mode/peripheral fidelity).
3. **Oracle agreement** for `UNIVERSAL` tests (`make oracle`), or a documented,
   justified divergence.
4. **No state leakage** — the suite passes when the new test is run first, last, and
   twice consecutively.
5. **Skips cleanly** on a CPU generation below its `GEN`.
6. **Header complete** — TIER/GEN/ORACLE/REFS present and accurate.
7. **Deterministic** — two runs produce identical result records (modulo logged
   timing bands for `TIMING`).

### CI Expectation

CI runs `make dos linux win32`, then executes the DOS build under DOSBox-X and 86Box
headless, the Linux/Win32 oracle natively, and diffs against `tests/reference/`.
Timing tests report deviation vs the target band and never hard-fail CI (they warn).

---

## 9. Testing Your Tests

```bash
# Fast loop
make cpu-8086 && dosbox-x -conf ci/dosbox.conf build/bin/X86VAL.EXE

# Higher-fidelity PM / peripherals
make dos && 86box --config ci/86box.cfg      # loads and runs the suite

# Oracle self-check for UNIVERSAL logic
make oracle && python3 tools/compare.py data/vectors/oracle_x86_64.json \
                                         data/vectors/dos_run.json

# The acceptance target
#   Copy X86VAL.EXE to the MiSTer, boot DOS on ao486, run, capture serial log.
```

Cross-validate against external suites:
```bash
python3 tools/import_singlestep.py <vectors.json> tests/      # SingleStepTests
# ZXALL: adopt patterns/reporting; see doc/references.md
```

---

## 10. Common Pitfalls (learned & inherited)

- **Assuming "undefined" flags don't matter** — real software depended on them; pin
  golden values (coverage-matrix §3.1).
- **Forgetting DF** — a test that runs a string op must clear/restore DF; a stray DF=1
  breaks later tests.
- **Leaving the FPU stack dirty** — the classic cross-test poison.
- **Count-mask assumptions** — 8086 vs 286+ shift-count behavior differs (coverage-matrix §3.1).
- **DOS PM tests via DPMI** — abstracts the CPU we mean to test; self-switch instead.
- **Polling a device with no timeout** — hangs on a stubbing emulator.
- **Host CPU as oracle for period-specific undefined behavior** — it isn't; use golden.
- **OS calls sprinkled in test logic** — breaks the multi-target build; use the API.
- **Silent SKIP** — a skip must be reported and counted, never invisible.

---

## 11. Contribution Workflow

1. Pick from the prioritized build order ([coverage-matrix.md](doc/coverage-matrix.md) §14).
2. **Read the spec** for your module — find it in [doc/specs/index.md](doc/specs/index.md).
3. Write the test per §6; complete the header.
4. `make dos` (+ `make linux win32` if `UNIVERSAL`) — zero warnings.
5. Green on DOSBox-X and, for PM/HW, 86Box; oracle agreement or documented divergence.
6. Confirm no state leakage (first/last/twice) and clean SKIP below `GEN`.
7. Update coverage notes if you closed a gap.
8. **Do not commit unless explicitly asked** — leave commits/pushes to a human
   maintainer's request. Include your test results in the PR/summary.

Commit messages: what behavior is now covered, which gap it closes, platforms verified,
oracle source.

---

## 12. Roadmap Alignment (build order)

Follow prd.md milestones, but within each, order by coverage-matrix §14 bug-yield:
flags → division faults → string/REP/DF → PM descriptor loading → FPU specials →
interrupt boundaries → PIC/PIT/VGA stateful → paging → A20/unreal → 486 SMC/#AC →
timing. MS-DOS all-modes coverage leads every milestone; Linux/Win32 oracle follows
for the `UNIVERSAL` subset only.
