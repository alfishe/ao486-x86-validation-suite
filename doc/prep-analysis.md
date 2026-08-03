# Preparation-Phase Deep Analysis

Consolidates the hard-case detail that [coverage-matrix.md](coverage-matrix.md)
references but does not fully expand.  This document is the **actionable
reference for test authors**: every table below is something a test must
exercise, with the expected behavior and divergence notes.

**Relationship to other docs:**
- [coverage-matrix.md](coverage-matrix.md) — *what* areas we cover and at what priority
- This document — *how* each area breaks down into individual test cases, and
  *where* the generation/vendor divergences are
- [specs/index.md](specs/index.md) — *detailed per-module specifications* with exact
  input/expected-output tables and pass/fail criteria; this document's tables are
  referenced from those specs
- [implementation-plan.md](implementation-plan.md) — *when* each test is built

---

## 1. Cross-CPU Divergence Catalog

Every row below is a place where behavior **legitimately differs** across CPU
generations.  A test that ignores this will produce false failures.  Each entry
must be **generation-gated** (`require_cpu` / `SKIP`) and, where the divergence
is in the *result* itself (not just availability), the expected value must be
tagged per-generation.

### 1.1 Instruction-availability divergences

These determine whether an instruction exists at all on a given generation.
The test framework gates these via `GEN:` in the module header and `require_cpu`.

| Instruction / Encoding | 8086 | 80186 | 80286 | 80386 | 80486 | Test action |
|------------------------|:----:|:-----:|:-----:|:-----:|:-----:|-------------|
| PUSHA/POPA, PUSH imm, IMUL imm, SHIFT imm8, ENTER/LEAVE, BOUND, INS/OUTS | — | ✓ | ✓ | ✓ | ✓ | Gen-gate: SKIP below 186 |
| Shift count masking (`& 0x1F`) | **no mask** | **no mask** | ✓ mask | ✓ mask | ✓ mask | Test 8086 raw-count path separately from 286+ masked path |
| LMSW, LGDT, LIDT, LLDT, LTR, VERR/VERW, LAR/LSL, ARPL | — | — | ✓ | ✓ | ✓ | Gen-gate: SKIP below 286 |
| All PM instructions in real mode (286) | — | — | #UD | varies | varies | 286 raises #UD for most PM insns in real mode; 386+ allows some (LGDT/SIDT) |
| MOVSX/MOVZX, SETcc, BT/BTS/BTR/BTC, BSF/BSR, SHLD/SHRD, LFS/LGS/LSS | — | — | — | ✓ | ✓ | Gen-gate: SKIP below 386 |
| 32-bit GPR / addressing / operand-size prefix | partial | partial | partial | ✓ | ✓ | 8086/186/286 ignore 66h/67h or behave differently |
| BSWAP, XADD, CMPXCHG, INVD, WBINVD, INVLPG | — | — | — | — | ✓ | Gen-gate: SKIP below 486 |
| CPUID | — | — | — | — | late-486 only | Gen-gate + ID-bit toggle check |
| FCMOV, FCOMI | — | — | — | — | — | **Out of scope** (P6+); always SKIP |
| LOADALL (`0F 05` 286, `0F 07` 386) | — | — | ✓ 286 | ✓ 386 | — | Gen-gated; constructible subset only |
| RDTSC | — | — | — | 486DX+ | 486DX+ | Requires CPUID to detect feature bit; early 486 fallback to PIT |


### 1.2 Behavioral divergences (same instruction, different result)

These are the most dangerous: the instruction exists on all generations but
produces a **different result or flag value**.  Each must be pinned with a
per-generation golden value.

| Behavior | 8086 | 286+ | Impact | Oracle |
|----------|------|------|--------|--------|
| `PUSH SP` | pushes decremented SP | pushes original SP | Stack-layout difference | golden (per-gen) |
| Shift count masking | raw (255 = 255 shifts) | `& 0x1F` (255 → 31) | Result+flags differ entirely | golden (per-gen) |
| `#DE` return address | next-instruction addr | DIV's own addr | Handler sees different CS:IP | golden (per-gen) |
| `MUL`/`IMUL` undefined flags | SF/ZF/AF/PF from internal result | different internal values | FLAGS mismatch if hardcoded | golden (per-gen) |
| `DIV`/`IDIV` all flags | undefined; varies across steppings | undefined; different values | Never assert; pin golden | golden (per-gen+stepping) |
| Shift OF (count > 1) | undefined; specific pattern | undefined; different pattern | OF mismatch | golden (per-gen) |
| Logic-op AF (`AND`/`OR`/`XOR`/`TEST`) | undefined; specific value | undefined; may differ | AF mismatch | golden (per-gen) |
| `POPF`/`PUSHF` reserved bits 12-15 | always set (0xF) | cleared (gates detection) | Detection algorithm depends on this | manual + golden |
| Segment-offset wrap (0xFFFF word access) | wraps to 0 | #GP (286+ PM) | Real-mode 8086 wraps; 286+ in PM faults | manual |
| `SALC` (`D6`) | AL = CF ? 0xFF : 0x00 | same on all gens | Documented in no manual | golden |
| `0F` opcode | `POP CS` | 2-byte opcode prefix | 8086-only alias | golden (8086 only) |
| `60`-`6F` opcodes | Jcc aliases (of `70`-`7F`) | PUSHA/POPA/etc (186+) | 8086-only alias | golden (per-gen) |
| `WAIT`/`FWAIT` exception delivery | INT via 8259 (8087) | #MF or IRQ13 (286/387) | #MF vector 16 (486 integrated) | golden (per-gen) |
| FPU projective infinity (287) | projective | affine (387+) | `+Inf == -Inf` comparison differs | golden (per-gen) |
| FPU `FXAM` pseudo-denormal | classified differently 387 vs 486 | different C1 for unnormals | Classification mismatch | golden (per-gen) |
| FPU state image (FSAVE) | 14-byte (real) / 28-byte (PM) | same sizes, but 387+ adds 94/108 | Layout differs by mode+gen | golden (per-gen+mode) |

### 1.2a Generation-specific divergences (286 vs 386 vs 486)

The §1.2 table above uses a coarse **8086 vs 286+** split.  But several
behaviors differ **within** the 286+ family — between 286, 386, and 486.
These are critical for a test suite targeting all four generations.

#### System-level divergences

| Behavior | 286 | 386 | 486 | Test action |
|----------|:---:|:---:|:---:|-------------|
| PM exit method | **cannot clear PE** — must reset CPU via KBC trick | `MOV CR0, AND ~PE` + far JMP | same as 386 | 286 PM-exit test is a golden-only reset path |
| LMSW vs MOV CR0 | LMSW only (can set PE, cannot read full CR0) | MOV CR0 full read/write | same as 386 | 286 must use LMSW; 386+ should use MOV CR0 |
| SGDT/SIDT high byte | **garbage** (undefined) | zero-extended | zero-extended | 286 must mask high byte; 386+ should see 0 |
| SMSW width | 16-bit (PE/MP/EM/TS only) | 32-bit (adds ET/NE/PG) | 32-bit (adds WP/AM/NW/CD/CE) | 286 lacks ET/NE/PG/WP/AM bits |
| Descriptor limit field | 16-bit (max 64 KB, no G-bit granularity) | 20-bit + G-bit (4 KB pages) | same as 386 | 286 cannot have page-granular segments |
| TSS format | **44-byte** minimum (no CR3, no I/O bitmap) | **104-byte** minimum (full 32-bit regs, CR3, I/O map ptr) | same as 386 | TSS structure must be gen-gated |
| CR0 defined bits | PE, MP, EM, TS | + ET, NE, PG | + WP, AM, NW, CD, PG, CE | Reserved bits may read as 1 or 0; pin golden |
| EFLAGS defined bits | bits 0–11 (same as 8086 + NT) | + RF (16), VM (17) | + AC (18), CPUID ID (21) | Reserved-bit reads differ per gen |
| Alignment check (#AC) | n/a | n/a (no AC bit) | CR0.AM + EFLAGS.AC → #AC in ring 3 | 486-only feature; gen-gate |

#### FPU coprocessor divergences

| Behavior | 80287 | 80387 | 486DX (integrated) | Test action |
|----------|:-----:|:-----:|:-------------------:|-------------|
| Infinity model | **projective** (+Inf == -Inf) | **affine** (+Inf > -Inf) | affine | 287 FCOM on ±Inf must be golden-pinned |
| Exception delivery | IRQ13 via 8259 | IRQ13 or #MF (config) | **#MF (vector 16)**, integrated | Delivery path is gen+config dependent |
| Pseudo-denormal (FXAM) | not classified | classified one way | classified differently | Pin C1 condition code per gen |
| FPTAN/FSIN/FCOS | n/a (80287 lacks these) | available, range-limited | available | Gen-gate transcendentals |
| FSCALE rounding of large scale | truncates | truncates (same) | truncates (same) | No divergence — but pin anyway |
| FPU tag word after FLD of sNaN | marks valid | marks valid | may mark special | Pin golden per gen |

#### Instruction-result divergences (286 vs 386 vs 486)

| Behavior | 286 | 386 | 486 | Test action |
|----------|:---:|:---:|:---:|-------------|
| SHL/SHR count mask | `& 0x1F` (same as 386/486) | `& 0x1F` | `& 0x1F` | **No divergence** — 286 already masks; only 8086 differs |
| BSF/BSR src=0 dest | n/a (386+ only) | dest unchanged, ZF=1 | dest unchanged, ZF=1 | No 286-vs-486 divergence here |
| MOVZX/MOVSX result | n/a (386+ only) | per spec | per spec | No divergence within 386+ |
| BSWAP on 16-bit reg | n/a (486+ only) | n/a | undefined; zero-extends high word | 486-only; pin golden |
| XADD flags | n/a (486+ only) | n/a | full arithmetic flags | 486-only |
| CMPXCHG ZF semantics | n/a (486+ only) | n/a | ZF=1 if match, ZF=0 if mismatch | 486-only |
| LOCK prefix #UD on invalid | #UD | #UD | #UD (same) | No divergence within 286+ |

> **Summary:** The primary 286-vs-386-vs-486 divergences are in **system
> architecture** (PM exit, TSS format, CR0 bits, descriptor granularity) and
> **FPU behavior** (infinity model, exception delivery, FXAM classification).
> Pure arithmetic/logic instruction results are **uniform** across 286+ —
> only 8086 diverges there.

### 1.3 Vendor-clone divergences (informational, not hard-fail)

ao486 targets Intel behavior, but real-world clones exist.  Record, don't fail.

| Vendor / Chip | Divergence | Test action |
|---------------|------------|-------------|
| NEC V20/V30 | Adds 80186 ISA + 8080 emulation mode; some timing differs | Record vendor string; SKIP 8080-mode tests on Intel |
| AMD Am486 | CPUID vendor "AuthenticAMD"; some CPUID feature bits differ | Don't hardcode "GenuineIntel" |
| Cyrix 486DX/DX2 | CPUID vendor "CyrixInstead"; different CPUID leaf layout | Record; don't hard-fail vendor string |
| UMC U5D | CPUID vendor "UMC UMC UMC" | Record |

---

## 2. Protected Mode & Paging — Full Check Matrix

This section expands coverage-matrix §6.1–§6.3 and §7.1 into the exhaustive
case list that PM/paging test modules must implement.  Each row is one test case.

### 2.1 Segment descriptor load checks

For each `MOV Sreg` / `LDS` / `LES` / `LFS` / `LGS` / `LSS` / `POP Sreg`:

| # | Selector | Descriptor | CPL | Expected | Error code | Oracle |
|---|----------|------------|-----|----------|------------|--------|
| 1 | null (index=0, TI=0) | — | 0 | load OK into DS/ES/FS/GS; **use** → #GP | 0x0000 | manual |
| 2 | null into SS | — | 0 | **#GP immediately** | 0x0000 | manual |
| 3 | index > GDT limit | — | 0 | #GP | selector + TI=0 | manual |
| 4 | index > LDT limit | TI=1 | 0 | #GP | selector + TI=1 | manual |
| 5 | P=0 (not present), non-SS | P=0 | 0 | #NP | selector | manual |
| 6 | P=0 into SS | P=0 | 0 | **#SS** (not #NP) | selector | manual |
| 7 | data desc into CS | type=data | 0 | #GP | selector | manual |
| 8 | exec-only code into DS/ES | type=exec-only | 0 | #GP | selector | manual |
| 9 | DPL < CPL (non-conforming code) | DPL=0, CPL=3 | 3 | #GP | selector | manual |
| 10 | DPL < CPL (data, non-conforming) | DPL=0, CPL=3 | 3 | #GP | selector | manual |
| 11 | RPL > CPL | RPL=3, CPL=0 | 0 | load OK (RPL dominates) | — | manual |
| 12 | conforming code, DPL < CPL | conforming, DPL=0 | 3 | load OK (conforming allows) | — | manual |
| 13 | read via code-seg exec/read into DS | type=XR | 0 | load OK | — | manual |
| 14 | Accessed bit (A=0) | A=0 | 0 | load OK; **A→1 written back** to desc | — | golden (read desc after) |

**Test construction:** build a GDT with crafted descriptors, load each, verify
the exception (or success).  For A-bit: re-read the descriptor from memory after
the load and confirm A=1.

### 2.2 Segment limit enforcement

| # | Segment type | Limit | Access | Expected | Notes |
|---|-------------|-------|--------|----------|-------|
| 1 | data, G=0 (byte) | 0x000F | byte at offset 0x0F | OK | last valid byte |
| 2 | data, G=0 | 0x000F | byte at offset 0x10 | #GP | limit+1 |
| 3 | data, G=0 | 0x000F | word at offset 0x0F | #GP | straddles limit |
| 4 | data, G=1 (page) | 0x00000 | byte at offset 0xFFF | OK | limit×4K-1 |
| 5 | data, G=1 | 0x00000 | byte at offset 0x1000 | #GP | first invalid |
| 6 | **expand-down** stack, G=0 | 0x0FFF | offset 0x1000 | OK | inverted: above limit is valid |
| 7 | expand-down, G=0 | 0x0FFF | offset 0x0FFF | #GP | at/below limit is invalid |
| 8 | expand-down, G=1 | 0x00000 | offset 0xFFFFF000 | OK | |
| 9 | expand-down, G=1 | 0x00000 | offset 0x00000 | #GP | |
| 10 | code, D=0 (16-bit) | — | — | SP-width = 16-bit | D/B bit controls |
| 11 | code, D=1 (32-bit) | — | — | ESP-width = 32-bit | |
| 12 | 286: limit field 16-bit | max 64KB | — | — | 386+ extends to 20-bit (G=1) |

**Key trap:** expand-down segments invert the limit check — valid offsets are
**above** the limit, not below.  This is the single most common PM bug.

### 2.3 Call gate & privilege transition matrix

| # | Gate type | CPL→target DPL | Stack switch? | Param copy? | Expected |
|---|-----------|----------------|---------------|-------------|----------|
| 1 | CALL gate, same priv | 0→0 | no | no | push CS:EIP; jump to target |
| 2 | CALL gate, more priv | 3→0 | **yes** (TSS SS0:ESP0) | yes (dword count) | old SS:ESP pushed; new stack loaded |
| 3 | CALL gate, less priv | 3→3 (conforming) | no | no | conforming: CPL stays, no stack switch |
| 4 | CALL gate, DPL < CPL | gate DPL=0, CPL=3 | — | — | #GP (can't even enter gate) |
| 5 | JMP gate, same priv | 0→0 | no | no | no return addr pushed |
| 6 | JMP gate, more priv | 3→0 | — | — | #GP (JMP can't raise privilege) |
| 7 | JMP gate, conforming | 3→0 conforming | no | no | CPL stays 3; jump OK |
| 8 | RETF to lower priv | 0→3 | yes (pop SS:ESP) | — | privilege drop via RET |
| 9 | IRET to lower priv | 0→3 | yes | — | privilege drop; restore IF from stack |
| 10 | INT *n* via gate | 3→0 | yes | — | same as CALL gate cross-priv |
| 11 | INT *n* gate DPL=3, CPL=0 | — | — | — | #GP (software INT respects gate DPL) |
| 12 | HW interrupt | 3→0 | yes | — | ignores gate DPL (HW always enters) |

**Critical distinction:** software `INT n` checks gate DPL against CPL (row 11),
but a **hardware interrupt** does NOT — it always enters regardless of DPL.
This is a frequent emulator bug.

**TSS stack switch:** on cross-privilege CALL gate, the CPU reads SS0:ESP0 from
the TSS.  If the TSS is malformed (bad limit, SS0 not present), expect #TS.

### 2.4 Paging fault matrix

`#PF` error code: bit0=P (0=not-present, 1=protection), bit1=W/R (1=write),
bit2=U/S (1=user).  Each combination must be deliberately triggered.

| # | PTE setup | Access | Error code | Condition |
|---|-----------|--------|------------|-----------|
| 1 | P=0 | read, CPL=0 | P=0, W=0, U=0 | not-present, supervisor |
| 2 | P=0 | read, CPL=3 | P=0, W=0, U=1 | not-present, user |
| 3 | P=1, R/W=0 | write, CPL=0 | P=1, W=1, U=0 | write to RO, supervisor |
| 4 | P=1, R/W=0 | write, CPL=3 | P=1, W=1, U=1 | write to RO, user |
| 5 | P=1, U/S=0 | read, CPL=3 | P=1, W=0, U=1 | user read of supervisor page |
| 6 | P=1, U/S=0, R/W=0 | write, CPL=3 | P=1, W=1, U=1 | user write of supervisor RO |
| 7 | PDE P=0 (PTE P=1) | any | P=0 | page directory not present |
| 8 | reserved-bit set (486+) | any | P=0, RSVD | reserved bits in PTE |
| 9 | CPL=0, WP=1, U/S=1, R/W=0 | write | P=1, W=1, U=1 | **486 WP=1**: supvr write to user RO → #PF |
| 10 | CPL=0, WP=0, U/S=1, R/W=0 | write | — (OK) | **486 WP=0**: supvr CAN write user RO |

**Row 9–10 is the CR0.WP feature (486 only):** WP=1 enforces write-protect for
supervisor code (copy-on-write support); WP=0 lets ring-0 write any read-only
page.  386 lacked this enforcement entirely.  Test both WP values.

### 2.5 A/D bit and TLB cases

| # | Setup | Action | Expected | Oracle |
|---|-------|--------|----------|--------|
| 1 | PTE A=0 | read | A→1 in PTE | golden (re-read PTE) |
| 2 | PTE A=0 | write | A→1 **and** D→1 | golden |
| 3 | PTE A=1, D=0 | read | D stays 0 | golden |
| 4 | PDE A=0 | read leaf | A→1 in **PDE too** | golden |
| 5 | modify PTE, no flush | read | **old translation** persists (TLB stale) | manual |
| 6 | `MOV CR3` after PTE change | read | new translation loaded | manual |
| 7 | `INVLPG` (486) one page | read | only that page re-walked | manual |

**Row 5 is testable**: deliberately modify a PTE without flushing, read the
page, and confirm the *old* mapping is used.  This proves the TLB caches.
---

## 3. Exception Taxonomy & Error-Code Matrix

Every exception handler test must verify: (a) the correct **vector**, (b) the
correct **classification** (fault pushes faulting-instruction CS:EIP; trap pushes
next-instruction CS:EIP), and (c) whether an **error code** was pushed.

### 3.1 Classification & error-code push

| Vector | Mnemonic | Class | Error code? | Pushed CS:EIP | Notes |
|--------|----------|-------|-------------|---------------|-------|
| 0 | #DE | fault | no | faulting insn (286+); **next insn (8086)** | 8086-vs-286 divergence |
| 1 | #DB | trap/fault | no | varies | fault for DR match; trap for single-step TF |
| 2 | NMI | interrupt | no | next insn | hardware; IF not cleared on 286 |
| 3 | #BP | trap | no | next insn (INT 3 is 1 byte) | `CC` |
| 4 | #OF | trap | no | next insn | `INTO` / `CE` |
| 5 | #BR | trap | no | next insn | `BOUND` / `62` |
| 6 | #UD | fault | no | faulting insn | |
| 7 | #NM | fault | no | faulting insn | FPU not present |
| 8 | #DF | abort | **yes** (always 0) | faulting insn | contributory exception while handling another |
| 9 | #CSO | fault | no | faulting insn | 386 only; coprocessor segment overrun |
| 10 | #TS | fault | **yes** | faulting insn | invalid TSS |
| 11 | #NP | fault | **yes** | faulting insn | segment not present |
| 12 | #SS | fault | **yes** | faulting insn | stack fault |
| 13 | #GP | fault | **yes** | faulting insn | general protection |
| 14 | #PF | fault | **yes** | faulting insn | restartable |
| 16 | #MF | fault | no | faulting/fwait insn | FPU error (486 integrated) |
| 17 | #AC | fault | **yes** (always 0) | faulting insn | alignment check (486+, CPL=3 only) |

### 3.2 Error-code encoding

Error codes for #TS/#NP/#SS/#GP have a common format:

```
 bit 15-3:  selector index (of the offending selector)
 bit 2:     TI (0=GDT, 1=LDT)
 bit 1:     IDT (1=error originated from IDT, not GDT/LDT)
 bit 0:     EXT (1=external interrupt caused the exception)
```

**Test cases for error-code decoding:**
- Load selector `0x0028` into DS with a not-present descriptor → error code
  should be `0x0028` (index=5, TI=0, IDT=0, EXT=0)
- Load selector `0x004F` (TI=1, LDT) → error code `0x004F | TI=1`
- Hardware interrupt that triggers a bad segment load → EXT bit should be 1
- INT instruction through an IDT gate with bad DPL → IDT bit set

### 3.3 Double fault (#DF) classification

#DF (vector 8) occurs when a second exception is detected **while handling** a
first.  The classification of "contributory" vs "benign" determines whether #DF
fires or the two exceptions are delivered independently.

| First exception | Second exception → | Benign | Contributory | Page fault |
|-----------------|-------------------|:------:|:------------:|:----------:|
| **Benign** (#DE, #BP, #OF, #BR, #UD, #NM) | | handle independently | handle independently | handle independently |
| **Contributory** (#TS, #NP, #SS, #GP) | | handle independently | **#DF** | **#DF** |
| **Page fault** (#PF) | | handle independently | **#DF** | **#DF** |

**Key:** a contributory exception during a contributory handler → #DF.
A benign exception is never escalated.  `#DF` → `#DF` → **triple fault** →
system reset (observable only in sim; guest is dead).

**Test construction:**
1. Benign + benign: `INT 0` (divide) handler that does another `DIV 0` → both
   #DE delivered independently (nested), **not** #DF.
2. Contributory + contributory: #GP handler that loads a bad segment → #DF.
3. #PF + #PF: page fault handler that accesses another missing page → #DF.

> Triple-fault and post-reset state are **venue C/T** (guest is dead).  Only the
> first two levels are testable guest-side.
---

## 4. Golden-Vector Schema

Defines the canonical JSON format for golden vectors stored in
`data/vectors/golden_*.json`.  Every golden entry must carry full provenance
so its trust level is auditable.

### 4.1 Schema

```json
{
  "schema_version": 1,
  "vector_type": "flags" | "result" | "fpu80" | "state_image",
  "provenance": {
    "source": "i486DX-33-S-stepping",
    "source_type": "real_hw" | "emulator",
    "emulator_version": null,
    "capture_date": "2026-08-03",
    "capture_method": "PUSHF after instruction, stored to memory",
    "oracle_tag": "golden" | "provisional-golden",
    "notes": "Flags captured by executing op then PUSHF; verified on two units"
  },
  "vectors": [
    {
      "id": "mul_8bit_255x255",
      "instruction": "MUL AL", "operands": {"AL": "0xFF", "BL": "0xFF"},
      "gen_min": "CPU_8086", "gen_max": "CPU_80486",
      "pre_flags": "0x0000",
      "result": {"AX": "0xFE01"},
      "post_flags": "0x0801",
      "undefined_flags": ["SF", "ZF", "AF", "PF"],
      "note": "CF=1 (AH!=0); OF/SF/ZF/AF/PF are undefined-but-deterministic"
    }
  ]
}
```

### 4.2 Field definitions

| Field | Type | Meaning |
|-------|------|---------|
| `vector_type` | enum | `flags`=FLAGS-only; `result`=GPR result; `fpu80`=80-bit FPU mantissa; `state_image`=full FPU state (FSAVE image) |
| `provenance.source` | string | Exact chip/stepping or emulator+version |
| `provenance.source_type` | enum | `real_hw` (authoritative) or `emulator` (provisional) |
| `provenance.oracle_tag` | enum | `golden` or `provisional-golden` (maps to test-header `ORACLE:` field) |
| `vectors[].gen_min/gen_max` | string | CPU generation range where this value applies |
| `vectors[].pre_flags` | hex | FLAGS value before instruction (the seed) |
| `vectors[].post_flags` | hex | FLAGS value after instruction (the golden pin) |
| `vectors[].undefined_flags` | array | Which flags in `post_flags` are "undefined" (reported as informational, not hard-fail) |

### 4.3 Trust rules

1. **`source_type: real_hw` + `oracle_tag: golden`** → authoritative; test may hard-assert `post_flags`.
2. **`source_type: emulator` + `oracle_tag: provisional-golden`** → informational; test reports divergence but does **not** hard-fail.  Must be re-captured on real HW before promotion.
3. **Provenance is immutable** — once captured, the value is not modified; a new capture creates a new entry with updated provenance.
4. If `gen_min` ≠ `gen_max` and values differ between generations, emit **separate entries** per generation (never a single "average" value).

---

## 5. FPU Corner-Case Taxonomy

The FPU has the highest ratio of "spec requires this exact bit pattern" to
"emulator gets it wrong."  This section is the exhaustive case list for FPU
test modules.  Each case must be exercised for every arithmetic op (ADD/SUB/
MUL/DIV/SQRT) and for transcendental ops where applicable.

### 5.1 IEEE-754 special-value matrix

For binary ops, the **operand-pair classification** determines the result.  Each
cell is one test case.  Apply to FADD, FMUL, FDIV at minimum.

| A \ B | QNaN | SNaN | +Inf | −Inf | +0 | −0 | Denorm | Norm |
|-------|------|------|------|------|----|----|--------|------|
| QNaN | QNaN(A) | QNaN(A) | QNaN(A) | QNaN(A) | QNaN(A) | QNaN(A) | QNaN(A) | QNaN(A) |
| SNaN | QNaN(B) | **QNaN** | QNaN | QNaN | QNaN | QNaN | QNaN | QNaN |
| +Inf | QNaN(B) | QNaN(B) | +Inf | **#I** | +Inf | +Inf | +Inf | +Inf |
| −Inf | QNaN(B) | QNaN(B) | **#I** | −Inf | −Inf | −Inf | −Inf | −Inf |
| +0 | QNaN(B) | QNaN(B) | +Inf | −Inf | **+0** | **+0†** | +0 | B |
| −0 | QNaN(B) | QNaN(B) | +Inf | −Inf | **+0†** | **−0** | −0 | B |
| Denorm | QNaN(B) | QNaN(B) | +Inf | −Inf | ±0(sign) | ±0(sign) | **denorm†** | normal |
| Norm | QNaN(B) | QNaN(B) | ±Inf | ±Inf | ±A | ±A | normal | computed |

**Legend:** `#I`=invalid-op exception; `†`=cases where sign rules are subtle
(e.g., +0 + +0 = +0; +0 + −0 = +0; −0 + −0 = −0 — these are the IEEE sign
rules that emulators frequently botch); `denorm†` may produce denormal or
normal result depending on exponent arithmetic.

### 5.2 Rounding-mode matrix

For each op, test all four rounding modes (RC bits in FCW):

| RC | Name | Behavior on exact half |
|----|------|------------------------|
| 00 | Round-to-nearest-even (default) | ties → even mantissa LSB |
| 01 | Round down (toward −Inf) | always toward −Inf |
| 10 | Round up (toward +Inf) | always toward +Inf |
| 11 | Round toward zero (chop) | truncate |

**Critical case:** `0.5 + 0.5` in each RC.  In nearest-even, depends on parity.
In RC=01, result is `0.0` (both halves round down to 0, sum is 0).
**Test:** every op × every RC × {exact-half, just-above-half, just-below-half}.

### 5.3 Exception-flag matrix

| Exception | Bit (FSW) | Mask (FCW) | When masked | When unmasked |
|-----------|-----------|------------|-------------|---------------|
| Invalid (#I) | IE | IM | set flag; return QNaN | trap; PC, OP retained in FPU |
| Denormal (#D) | DE | DM | set flag; proceed | trap before op |
| Zero-divide (#Z) | ZE | ZM | set flag; return ±Inf | trap |
| Overflow (#O) | OE | OM | set flag; ±Inf or ±MAX (per RC) | trap; rounded result in PC |
| Underflow (#U) | UE | UM | set flag (if precision loss too); proceed | trap if precision lost |
| Precision (#P) | PE | PM | set flag; rounded result | trap (rare; sets C1=1 if rounded up) |

**Stack fault (SF/ES in FSW):** triggered when pushing to a full stack or
popping an empty stack.  Not maskable.  Sets #IS (invalid-stack) which overlaps
with #I encoding.

**Test for each exception:** mask + unmask; verify flag set in FSW; verify
result for masked case; verify FPU state preserved for unmasked case.

### 5.4 Condition-code (C0–C3) cases for FCOM/FTST/FXAM

| Instruction | Condition | C3 | C2 | C1 | C0 |
|-------------|-----------|----|----|----|----|
| FCOM | A > B | 0 | 0 | — | 0 |
| FCOM | A < B | 0 | 0 | — | 1 |
| FCOM | A == B | 1 | 0 | — | 0 |
| FCOM | unordered (NaN) | 1 | 1 | — | 1 |
| FTST | ST > 0 | 0 | 0 | — | 0 |
| FTST | ST < 0 | 0 | 0 | — | 1 |
| FTST | ST == 0 | 1 | 0 | — | 0 |
| FTST | unordered | 1 | 1 | — | 1 |
| FXAM | unsupported | 0 | 0 | sign | 0 |
| FXAM | NaN | 0 | 0 | sign | 1 |
| FXAM | Normal | 0 | 1 | sign | 0 |
| FXAM | Infinity | 0 | 1 | sign | 1 |
| FXAM | Zero | 1 | 0 | sign | 0 |
| FXAM | Empty | 1 | 0 | sign | 1 |
| FXAM | Denormal | 1 | 1 | sign | 0 |

**C1 in FXAM:** the sign bit of the operand.  Each class must be tested with
both positive and negative sign.

**Pseudo-denormal (387/487 only):** exponent all-zeros, integer-bit set.
FXAM reports it as "Denormal" on 387 but classification differs on 486.
**Golden-vector required.**

### 5.5 Transcendental range limits (287+)

| Op | Valid input range | Out-of-range result |
|----|-------------------|---------------------|
| FPATAN | any (0 to ±Inf) | always defined |
| F2XM1 | −1 < ST < +1 | undefined result (no exception) |
| FYL2X | ST > 0 | invalid if ST ≤ 0 |
| FYL2XP1 | −(1−√/2) < ST < 1−√/2 | undefined outside |
| FCOS | |ST| < 2⁶³ | if out of range, C2=1, ST unchanged |
| FSIN | |ST| < 2⁶³ | if out of range, C2=1, ST unchanged |
| FSINCOS | same as FSIN | same |
| FPTAN | |ST| < 2⁶³ | if out of range, C2=1; otherwise pushes 1.0 then tan |

**Test:** within-range (verify result); boundary (exactly 2⁶³−1); out-of-range
(verify C2=1, ST unchanged).  Transcendental accuracy is ±1 ULP on 387/487.

### 5.6 FPU constants (FLDPI, FLDL2E, FLDL2T, FLDLG2, FLDLN2, FLD1, FLDZ)

Each loads a hardwired 80-bit value.  The **exact bit patterns are golden
vectors** — they must match silicon byte-for-byte.

| Constant | Value (approx) | Exact 80-bit hex (487) |
|----------|----------------|------------------------|
| FLD1 | +1.0 | `3FFF 8000 0000 0000 0000` |
| FLDZ | +0.0 | `0000 0000 0000 0000 0000` |
| FLDPI | π | `4000 C90F DAA2 2168 C235` |
| FLDL2E | log₂(e) | `3FFF B8AA 3B29 5C17 F0BC` |
| FLDL2T | log₂(10) | `4000 D49A 784B CD1B 8AFE` |
| FLDLG2 | log₁₀(2) | `3FFD 9A20 9A84 FBCF F799` |
| FLDLN2 | ln(2) | `3FFE B172 17F7 D1CF 79AC` |

These bit patterns are the single most testable FPU golden vector — if a core
gets these wrong, every transcendental derived from them is wrong.
---

## 6. Peripheral Stateful Behavior Matrix

Peripheral tests are the highest-value after CPU/FPU because devices are
**stateful**: their behavior depends on prior writes, and a bug often manifests
as wrong interrupt delivery, lost timer ticks, or a hung DMA.  Every test must
snapshot and restore the device's complete register set.

### 6.1 PIC (8259) — stateful traps

| # | Setup | Action | Expected | Bug this catches |
|---|-------|--------|----------|------------------|
| 1 | OCW3 P=1 (read IRR), then P=1 (read ISR) | IN port 0x20 | ISR value, not IRR | Read-select flip-flop not maintained |
| 2 | OCW3 RR=1 (read register), RIS=0 then RIS=1 | IN 0x20 | IRR then ISR | RIS bit ignored |
| 3 | Mask all in OCW1, trigger IRQ3, unmask | IN 0x20 | pending bit in IRR | Lost pending interrupt |
| 4 | Auto-EOI mode (ICW4 AEOI=1) | trigger IRQ | ISR cleared automatically | ISR bit stuck set |
| 5 | Spurious IRQ7 (IRQ asserted+deasserted before INTA) | INTA cycle | vector 0x07 (spurious) | Delivers wrong vector |
| 6 | Edge-triggered vs level-triggered (ICW1 LTIM) | pulse vs hold | Different delivery timing | Level/edge mode wrong |
| 7 | Special fully nested mode (ICW4 SFNM) | cascade priority | ISR not cleared by EOI of slave | Cascade priority broken |
| 8 | Rotate-on-EOI (OCW2 R=1, SL=0, EOI=1) | EOI | priority rotates | Priority stays fixed |
| 9 | Specific EOI (OCW2 SL=1, EOI=1, L2-L0) | EOI level 3 | only ISR bit 3 cleared | Wrong bit cleared |

**Row 5 (spurious IRQ7)** is the signature PIC test.  It requires precise
timing between IRQ assertion and INTA — best done with PIT-triggered IRQ.

### 6.2 PIT (8254) — stateful traps

| # | Setup | Action | Expected | Bug this catches |
|---|-------|--------|----------|------------------|
| 1 | Counter 0, mode 2 (rate gen), count=0xFFFF | read latch | counter decrements | Counter not running |
| 2 | Read-back command (0x43: COUNT\|STATUS, sel=0) | IN 0x40 | latched count+status byte | Read-back command ignored |
| 3 | Latch counter 0 (0x43: 0x00) then read 0x40 | IN 0x40 ×2 | latched count (stable) | Counter continues to run during read |
| 4 | Read-back status, mode bits | IN 0x40 | status byte with mode/output/null-count | Status byte wrong format |
| 5 | BCD mode (BCD bit in control word) | load count | counts in BCD | Decimal not BCD |
| 6 | Mode 3 (square wave), even count | observe OUT | 50% duty cycle | Duty cycle wrong for odd count |
| 7 | Write LSB then MSB (access mode 3) | load count | both bytes accepted | LSB-only overwrite |
| 8 | Counter read without latch | IN 0x40 ×2 | unstable (may be off-by-one) | Documented behavior; golden |

**Row 3 (latch)** is the most common PIT bug — reading the counter directly
without latching returns inconsistent bytes because the counter decrements
between the two IN reads.

### 6.2a PIT mode-specific behavior matrix

All six modes must be tested. Each has distinct OUT behavior and GATE sensitivity.

| Mode | Name | OUT behavior | GATE=0 effect | GATE rising edge | Count=0 means | Key test |
|------|------|-------------|---------------|-----------------|---------------|----------|
| 0 | Interrupt on TC | OUT goes high at TC, stays high | Pauses counting | No effect | 0x10000 (65536) | OUT initial low, goes high after N counts |
| 1 | Hardware retriggerable one-shot | OUT low for N counts after GATE rise | No effect (triggered by GATE) | **Retriggers**: reloads count, OUT pulse | 0x10000 | Pulse width = N ticks; retrigger restarts |
| 2 | Rate generator | OUT high, brief low pulse each cycle | **Freezes** counting (OUT goes high) | Restarts from initial count | 0x10000 | Periodic pulse; GATE=0 stops output |
| 3 | Square wave | OUT toggles each half-period | **Freezes** OUT at current level | Restarts from initial count | 0x10000 | 50% duty for even; asymmetric for odd counts |
| 4 | Software triggered strobe | OUT high, goes low for 1 clk at TC | Pauses counting | No effect | 0x10000 | Single strobe pulse after N counts |
| 5 | Hardware triggered strobe | OUT high, low pulse after GATE-triggered count | No effect | **Triggers**: loads count, strobe at TC | 0x10000 | Like mode 4 but waits for GATE |

**Mode 3 odd-count asymmetry:** for odd counts, mode 3 outputs HIGH for
(N+1)/2 counts and LOW for (N-1)/2 counts. This is a classic emulator bug.
**Mode 2 GATE behavior:** GATE=0 causes OUT to go HIGH immediately and
freezes counting — distinct from mode 0 where GATE=0 just pauses.

### 6.3 DMA (8237) — stateful traps

| # | Setup | Action | Expected | Bug this catches |
|---|-------|--------|----------|------------------|
| 1 | Channel 0, single mode, auto-init | trigger DREQ | transfer occurs, then reloads | No auto-reload |
| 2 | Terminal count (TC) reached | observe | EOP asserted; status TC bit set | TC not reported |
| 3 | Mask register (write 0x0A: bit=1) | trigger DREQ | masked channel ignores DREQ | Mask ignored |
| 4 | Mode register: decrement mode | transfer | address decrements | Address always increments |
| 5 | Cascade mode (slave chained to master ch4) | trigger slave DREQ | master DREQ4 fires | Cascade broken |
| 6 | Flip-flop (0x0C: clear flip-flop) | write address | LSB first then MSB | Byte order wrong |

### 6.4 VGA — stateful traps

The VGA has more flip-flops and index registers than any other device.

| # | Setup | Action | Expected | Bug this catches |
|---|-------|--------|----------|------------------|
| 1 | AC index write (0x3C0) without resetting flip-flop | write two values | first=index, second=data | Flip-flop not toggling |
| 2 | Reset flip-flop (IN 0x3DA) then write 0x3C0 | write index+data | correct reg set | Flip-flop reset broken |
| 3 | Sequencer (0x3C4) / graphics (0x3CE) index/data pairs | write then read | data round-trips | Index ignored |
| 4 | CRT controller (0x3D4) index > 0x18 | write index 0x19 | ignored or wraps | Out-of-range index accepted |
| 5 | DAC (0x3C8/0x3C9) write 3 bytes | read back | 6-bit RGB round-trips | 8-bit truncation wrong |
| 6 | Read AC reg via 0x3C1 (after IN 0x3DA) | IN 0x3C1 | last written value | Read path wrong |
| 7 | Video memory plane enable (map mask 0x3C5) | write VRAM | only enabled planes change | Plane mask ignored |
| 8 | Set/Reset mode (graphics 0x3CE reg 0-1) | write VRAM | fill pattern per set/reset | Set/reset logic broken |

**Row 1–2 (AC flip-flop)** is the most common VGA bug.  The address/data
flip-flop on port 0x3C0 toggles on every write; if the core doesn't track it,
every other AC register write lands in the wrong slot.

### 6.5 KBC, RTC, Serial — abbreviated

| Device | Key test cases |
|--------|----------------|
| KBC (8042) | Command byte readback; output buffer full flag; input buffer full flag; self-test (0xAA); interface test (0xAB) |
| RTC (MC146818) | NMI disable via port 0x70 bit7; UIP (update-in-progress) read; binary/BCD mode; alarm interrupt |
| Serial (16550) | Divisor latch access (DLAB bit); FIFO enable/disable; line-status register; THR-empty interrupt |

### 6.6 KBC, RTC, Serial — abbreviated

| Device | Key test cases |
|--------|----------------|
| KBC (8042) | Command byte readback; output buffer full flag; input buffer full flag; self-test (0xAA); interface test (0xAB) |
| RTC (MC146818) | NMI disable via port 0x70 bit7; UIP (update-in-progress) read; binary/BCD mode; alarm interrupt |
| Serial (16550) | Divisor latch access (DLAB bit); FIFO enable/disable; line-status register; THR-empty interrupt |

---

## 7. TSS Task Switch Matrix

Expands coverage-matrix §6.3 and implementation-plan Phase 5 TSS rows.
Every row is one test case that must be deliberately triggered and verified.

### 7.1 Task switch trigger types

| # | Trigger | Via | What happens |
|---|---------|-----|--------------|
| 1 | JMP to TSS selector | GDT TSS descriptor | CPU saves current state to old TSS, loads new TSS, sets NT=0 |
| 2 | CALL to TSS selector | GDT TSS descriptor | Same as JMP + sets NT=1 in new EFLAGS, back-link in new TSS = old TSS sel |
| 3 | CALL/IRET via task gate | IDT/GDT task gate | Indirect task switch through a gate descriptor |
| 4 | IRET with NT=1 | EFLAGS.NT | Returns to the task pointed to by the back-link field in current TSS |
| 5 | Interrupt via task gate | IDT task gate | HW IRQ can trigger a task switch if the IDT entry is a task gate |

### 7.2 State saved/restored during switch

The CPU saves the **entire** context to the old TSS and loads from the new:

| Field | 286 (16-bit TSS) | 386+ (32-bit TSS) | Offset (386) |
|-------|-------------------|-------------------|-------------|
| LINK (back-link) | 16-bit | 32-bit | +0 |
| ESP0 / SS0 | SP0 / SS0 | 32-bit each | +4 / +8 |
| ESP1 / SS1 | — | 32-bit each | +12 / +16 |
| ESP2 / SS2 | — | 32-bit each | +20 / +24 |
| CR3 | — | 32-bit (PDBR) | +28 |
| EIP | IP | 32-bit | +32 |
| EFLAGS | FLAGS | 32-bit | +36 |
| EAX–EDI | AX–DI | 32-bit each | +40 to +60 |
| ES/CS/SS/DS/FS/GS | 16-bit each | 16-bit each | +64 to +72 |
| LDTR | — | 16-bit | +76 |
| I/O map base | — | 16-bit | +102 |

**286 TSS minimum size:** 44 bytes (limit ≥ 0x002B).
**386 TSS minimum size:** 104 bytes (limit ≥ 0x0067).
If the TSS limit is too small → **#TS**.

### 7.3 TSS validation checks

| # | TSS setup | Action | Expected |
|---|-----------|--------|----------|
| 1 | TSS descriptor type = "busy 386 TSS" (type=0xB) | JMP to it | #GP (can't switch to a busy task) |
| 2 | TSS descriptor P=0 (not present) | JMP/CALL to it | #NP |
| 3 | TSS limit < 0x0067 (386) | JMP to it | #TS (with error code = TSS selector) |
| 4 | TSS limit < 0x002B (286) | JMP to it | #TS |
| 5 | SS0 in new TSS is not present | task switch | #TS (new TSS's SS0 selector in error code) |
| 6 | CS in new TSS is a data descriptor | task switch completes, then #GP on first instruction | CS loaded from TSS is validated |
| 7 | Nested task (NT=1) IRET to task with no back-link | IRET | #GP or loads TSS from LINK=0 (undefined) |
| 8 | Switch to same task (self) | JMP to currently running TSS | #GP (busy bit set) |

**Key trap (row 5):** during a task switch, the CPU loads all segment registers from
the new TSS. If any (SS0, CS, etc.) is invalid, the exception fires **after** the
switch has partially completed, with the error code pointing to the offending
selector from the new TSS — not the instruction that triggered the switch.

## 8. V86 Mode & IOPL Sensitivity Matrix

Expands coverage-matrix §7 V86 rows.  V86 mode is entered via IRET with VM=1
in EFLAGS (only works from CPL=0).  Once in V86, many instructions become
IOPL-sensitive — they either trap to the monitor (ring-0 handler) or execute
directly, depending on IOPL.

### 8.1 Entering/exiting V86

| # | Method | From | To | Notes |
|---|--------|------|----|-------|
| 1 | IRET with VM=1 on stack | ring-0 PM | V86 | EFLAGS.VM loaded from stack image; must be CPL=0 |
| 2 | Task switch to V86 task | PM task | V86 | If saved EFLAGS in TSS has VM=1 |
| 3 | IRET from V86 monitor | V86 | ring-0 PM | Clears VM bit |
| 4 | PUSHF in V86 pushes VM=1 | V86 | — | Verifies VM is set |
| 5 | POPF in V86: VM bit | V86 | — | IOPL-sensitive: POPF can't clear VM in V86 |

**Cannot enter V86 from real mode.** V86 requires PM (CR0.PE=1) + paging.

### 8.2 IOPL-sensitive instructions in V86

| Instruction | IOPL < 3 (traps to monitor) | IOPL = 3 (executes) |
|-------------|:---------------------------:|:-------------------:|
| CLI | ✓ #GP | executes (clears IF) |
| STI | ✓ #GP | executes (sets IF) |
| PUSHF | ✓ pushes with IOPL, not real flags | executes normally |
| POPF | ✓ #GP (can't change IF) | executes normally |
| INT *n* | ✓ reflects to monitor | — (always reflects in V86) |
| IRET | ✓ (POP SS-like shadow) | — (always reflects in V86) |
| IN/OUT | depends on I/O bitmap | depends on I/O bitmap |

**Critical:** INT *n* in V86 **always** traps to the monitor regardless of IOPL.
The monitor sees the interrupt as a #GP (vector 13) with error code = INT number.

### 8.3 V86 segment behavior

In V86 mode, segment registers are treated as real-mode segment bases
(base = selector × 16). The CPU does **not** perform descriptor loads or
limit/type checks. But the hidden part of the segment register is still loaded.

| # | Behavior | Expected |
|---|----------|----------|
| 1 | `MOV DS, AX` in V86 | base = AX × 16; no descriptor load; no limit check |
| 2 | `PUSH ES` in V86 | pushes 16-bit selector (not descriptor) |
| 3 | Address size override (67h) | 32-bit addressing usable in V86 (ESP, etc.) |
| 4 | Operand size override (66h) | 32-bit operands usable in V86 |

### 8.4 I/O permission bitmap (386+)

When CPL=3 or V86, `IN`/`OUT` check the I/O permission bitmap in the TSS:

| # | I/O bitmap setup | IN/OUT port | Expected |
|---|-----------------|-------------|----------|
| 1 | bit for port = 0 (allowed) | IN AL, port | executes |
| 2 | bit for port = 1 (denied) | IN AL, port | #GP |
| 3 | port beyond bitmap (I/O map base > TSS limit) | IN AL, port | #GP (no permission) |
| 4 | word at last byte of bitmap | IN AX, port | checks both bits; if either set → #GP |

## 9. Exception Priority Matrix

When multiple exception conditions are true simultaneously on a single
instruction, the CPU resolves them in a **fixed priority order**. This is
difficult to trigger from guest software (most combinations require co-sim),
but the most common ones are testable.

### 9.1 Priority order (highest first)

| Priority | Exception class | Example trigger |
|----------|----------------|-----------------|
| 1 | **#DF** (double fault) | Already in a fault handler, second fault occurs |
| 2 | Internal machine check / abort | (not architecturally testable from G) |
| 3 | **Trap from previous instruction** | TF=1 from prior insn → #DB delivered first |
| 4 | **External hardware interrupt / NMI** | IRQ or NMI pending at instruction boundary |
| 5 | **Code-fetch #PF / #GP** | Page not present or limit violation for the instruction bytes |
| 6 | **Operand #SS** | Stack fault (SS limit) on the instruction's operands |
| 7 | **Operand #GP / #PF / #NP** | Segment/privilege/page fault on data operand |
| 8 | **Instruction-specific fault** | #DE (div by zero), #UD, #NM, etc. |
| 9 | **#DB data breakpoint** | DR match on operand address (after insn completes) |
| 10 | **Single-step #DB** | TF=1 on this instruction → delivered after instruction |

### 9.2 Common testable priority cases

| # | Setup | Two conditions | Winner | Testable from G? |
|---|-------|---------------|--------|:---:|
| 1 | Div-by-zero with SS limit violation | #DE + #SS | #SS (priority 6 > 8) | ✓ (if SS can be crafted) |
| 2 | #UD insn at page-not-present | #PF + #UD | #PF (fetch, priority 5 > 8) | ✓ |
| 3 | Operand access to absent page with TF=1 | #PF + #DB(TF) | #PF (priority 7 > 10) | ✓ |
| 4 | INT *n* with gate-DPL violation + CPL mismatch | #GP | #GP only (single fault) | ✓ |
| 5 | Nested faults: #GP handler → #GP | #DF | #DF fires | ✓ (see §3.3) |

> Rows 1–4 are constructible guest-side by deliberately creating two fault
> conditions on one instruction. Row 5 is the double-fault chain already
> documented in §3.3. Full exhaustive priority testing is **venue C**.
## 10. FPU State Image Format (FSAVE/FSTENV/FRSTOR/FLDENV)

Expands coverage-matrix §4.7. The FPU environment and state image size/layout
differs by CPU mode and generation. A save/restore round-trip must preserve
the exact bit image.

### 10.1 FSTENV/FLDENV (environment only)

| Mode | Size | Layout (offsets) |
|------|------|-----------------|
| **Real mode (8086/286/386/486)** | 14 bytes | FCW(0) FSW(2) FTW(4) IP(6) CS(8) OP(10) DS(12) |
| **16-bit PM (286/386/486)** | 28 bytes | FCW(0) FSW(2) FTW(4) IP(6) CSsel(8) OP(10) DSsel(12) DS(14) |
| **32-bit PM (386/486)** | 28 bytes | FCW(0) FSW(2) FTW(4) IP(6) CSsel(10) OP(14) DSsel(18) DS(22) |

> **286 vs 386 IP/OP fields:** The 286 stores 20-bit IP/OP (padded to 24);
> the 386+ stores 32-bit IP/OP with a separate segment/opcode field.

### 10.2 FSAVE/FRSTOR (full state)

| Mode | Size | Layout |
|------|------|--------|
| **Real mode** | 94 bytes | env(14) + 8× 10-byte regs (80) |
| **16-bit PM** | 94 bytes | env(14) + 8× 10-byte regs |
| **32-bit PM** | 108 bytes | env(28) + 8× 10-byte regs |

### 10.3 Tag word (FTW) format

| FTW bits | Meaning | 387+ code |
|----------|---------|-----------|
| 00 | Valid | 0 |
| 01 | Zero | 1 |
| 10 | Special (NaN/Inf/denormal) | 2 |
| 11 | Empty | 3 |

The 287 stores 2-bit tags per register (16 bits total).
The 387+ uses the same 2-bit encoding but the "special" category sub-encodes
NaN vs Infinity vs Denormal internally.

### 10.4 Test cases

| # | Test | Expected |
|---|------|----------|
| 1 | FNINIT → FNSAVE → verify FTW = all-empty (0xFFFF) | all 8 regs empty |
| 2 | Load values → FNSAVE → verify FTW matches loaded types | tag word correct |
| 3 | FNSAVE → FRSTOR → FNSAVE → second image == first | round-trip preserves state |
| 4 | FNSAVE masks all exceptions | FCW = 0x037F after FNSAVE |
| 5 | FNSAVE in real mode → 14-byte env | layout matches §10.1 |
| 6 | FNSAVE in 32-bit PM → 28-byte env | layout matches §10.1 |

## 11. IDE/ATA Stateful Behavior Matrix

Expands coverage-matrix §9.6. IDE tests are HW-tier and must use scratch
media only (no writes to real disks without explicit opt-in flag).

### 11.1 Status register protocol

| # | Setup | Action | Expected | Bug this catches |
|---|-------|--------|----------|------------------|
| 1 | Drive idle, DRDY=1 | Write command to CMD reg | BSY set briefly, then clears | BSY never set (command lost) |
| 2 | BSY=1 | Read status (0x1F7) | Always returns with BSY=1; DRQ reflects state | Status read ignores BSY |
| 3 | BSY=1 | Read alt-status (0x3F6) | Same bits, but **does NOT clear IRQ** | Alt-status clears IRQ (wrong) |
| 4 | Read status (0x1F7) after IRQ | — | **Clears pending IRQ** for this drive | Status read doesn't clear IRQ |
| 5 | DRQ=1 after IDENTIFY | Read 256 words from data port | Data flows; DRQ clears after last word | DRQ stuck set |

**Row 3–4 is the signature IDE test.** Reading the primary status register
(0x1F7) has the side effect of clearing the IRQ; reading the alternate status
(0x3F6) does not. An emulator that doesn't model this will break interrupt-
driven drivers.

### 11.2 Device selection & 400ns settle

| # | Setup | Action | Expected |
|---|-------|--------|----------|
| 1 | Select drive 0 → read | DEV bit=0 in head reg | IDENTIFY returns drive-0 data |
| 2 | Select drive 1 → read | DEV bit=1 | IDENTIFY returns drive-1 data |
| 3 | Switch drive → immediate status read | — | May need 400ns settle; DRDY may be stale |

### 11.3 IDENTIFY DEVICE layout

| Word | Content | Test action |
|------|---------|-------------|
| 0 | General config (0x00A0 = ATA, non-removable) | Verify expected value |
| 49 | Capabilities (bit 9 = LBA supported) | Check LBA bit |
| 53 | Field validity (bit 0 = words 54-58 valid) | Check before reading 54-58 |
| 60-61 | Max LBA28 sector count (48-bit) | Verify ≥ scratch media size |
| 83 | Command sets (bit 10 = LBA48 supported) | Check LBA48 bit |

### 11.4 Non-destructive test constraints

- **No WRITE SECTOR** without explicit `/ide-write:allow` flag.
- **READ SECTOR** to scratch media only (predetermined scratch LBA range).
- **IDENTIFY** is always safe (read-only, no media access).
- Always restore the previously selected drive after testing.
