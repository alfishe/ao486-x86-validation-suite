# Coverage Matrix — Project-Specific

The master, self-contained specification of what this suite covers, area by area:
the enumeration (matrix tables), the **hard cases and rationale** (the subtle,
undocumented, error-prone behavior where cores actually diverge), the **test venue**
([test-venues.md](test-venues.md)), and the **priority**. Nothing is deferred to a
separate analysis document — the detail lives here where it is actionable.

## How To Read

- **Venue**: `G` guest-testable · `G⁺` guest-partial (band/side-effect only) · `H`
  also host-oracle (UNIVERSAL) · `→C` deferred to co-sim · `→T` deferred to bench.
  Only `G`/`G⁺`/`H` rows are implemented here; `→C`/`→T` rows are listed so the
  boundary is explicit, not forgotten. See [test-venues.md](test-venues.md).
- **Pri**: 1 (highest bug-yield) … 5. The prioritized cross-area list is §14.
- **Dim**: the test *dimensions* — the axes we vary. Case count = product of sampled
  points per axis (§2), not a raw operand sweep.

Each entry in the behavioral catalogs answers: **what it is**, **why it's hard**,
**how emulators get it wrong**, and **how we test it**.

> **DETAILED SPECS (prep-phase D2):** Each area in the matrix tables below has a
> corresponding detailed specification in [doc/specs/](specs/index.md). The spec
> files contain exact test-case tables (input, expected result, expected flags),
> oracle source per case, state save/restore contracts, known per-generation
> divergences, and pass/fail criteria. **Read the spec before implementing.**
> See [specs/index.md](specs/index.md) for the full enumeration.

---

## 1. Why This Matrix Looks The Way It Does (Project Rationale)

This is **not** a generic x86 checklist. Three project facts shape every scoping call:

1. **The consumer is ao486 (a from-scratch FPGA 486 core), tested by booting DOS.**
   That makes **venue G the default and MS-DOS-all-modes priority #1.** Anything not
   observable from a DOS program is out of *our* scope by construction (it lives in the
   ao486 HDL testbenches or SingleStepTests co-sim).

2. **ao486 is a *reimplementation*, so its risk profile is not "does ADD work" — it is
   the corners a clean-room RTL author under-specifies:** flag edge-cases, PM descriptor
   checks, paging error codes, FPU rounding/specials, and **peripheral stateful
   behavior** (ao486 integrates its own PIC/PIT/DMA/VGA/IDE). Peripheral integration is
   where we have the least overlap with any existing suite — so we weight it heavily.

3. **A guest program cannot enumerate 2^32 operands or inject arbitrary state.** So the
   matrix commits to **structured equivalence-class sampling** (§2), and explicitly
   hands exhaustive per-instruction vectoring to co-sim. We aim for *behavioral*
   completeness (every documented + known-undocumented behavior exercised at its
   boundaries), not *combinatorial* completeness.

**Where this suite is uniquely valuable** (low/zero overlap with SingleStepTests, host
oracle, or HDL testbenches): PM/paging *functional outcomes*, mode transitions, A20,
FPU save/restore image formats, and the **entire peripheral + system-integration
layer**. That is the spine of the matrix.

---


> **TERMINOLOGY DECISION (prep-phase E1):** The "Tier" column in the
> tables below refers to **execution Wave** (0–3) — the fail-fast ordering
> *within* a CPU scope.  It is distinct from the **build-target TIER**
> (`UNIVERSAL`/`REALMODE`/`RING0`/`HARDWARE`/`TIMING`) defined in
> AGENTS.md §3, which controls *which executables include a module*.  The
> two are orthogonal: a `RING0` module can run in Wave 2; a `UNIVERSAL`
> module can run in any Wave.

### Priority vs. Wave
- **Priority (1-5)**: Dictates the *build order* and *development focus*. Areas with high emulator bug-yield are Priority 1.
- **Wave (0-3)**: Dictates the *execution order* per CPU scope. Waves ensure we fail-fast on basic instructions (Smoke/Wave 0) before running multi-hour edge-case permutations (Wave 3), as defined in `technical-design.md` §2.2.

## 2. Sampling Methodology (How "Cases" Are Chosen)

Exhaustive is impossible from G; random is unreproducible. We sample by **equivalence
classes** per axis, then take the cross-product.

**Operand value classes** (per width): `0`, `1`, `-1/all-ones`, `MAX_signed`,
`MIN_signed`, `MAX_unsigned`, a mid "random-but-fixed" value, and **boundary pairs**
that force each flag transition (carry-out, half-carry/AF, signed overflow, zero
result, sign flip, even/odd parity).

**Flag-seed matrix**: run each case with incoming FLAGS = {all-clear, all-set, CF-only,
DF-only, AF-only} to catch instructions that (wrongly) depend on or (wrongly) preserve
flags.  The AF-only seed is critical for BCD-adjust (DAA/DAS/AAA/AAS) and
multi-precision ADC/SBB chains whose internal logic branches on the incoming
half-carry — without it, the AF-dependent path is never exercised.

**Count classes** (shifts/rotates): `0, 1, 2, 7, 8, 15, 16, 17, 31, 32, 33, 255` to
straddle width and the 8086-vs-286 masking boundary.

**Addressing-mode classes**: reg, `[disp]`, `[base]`, `[base+idx]`, `[base+idx+disp]`,
segment-overridden, and (386+) each SIB scale — applied to a representative op per
group rather than every op.

**Memory-alignment classes**: aligned, off-by-one, width-straddling a
dword/segment/page boundary.

All seeds are fixed constants (no live RNG). Golden/undefined values are pinned from a
period-correct reference and tagged `ORACLE: golden`.

Rationale: this yields ~10³–10⁴ high-value cases (tractable in a DOS run) that hit
every documented boundary and every known-undocumented behavior, while co-sim carries
the 10⁶⁺ exhaustive load.

---

## 3. CPU — 8086/8088 (Pri 1 foundation)

| Area | Dim | Venue | Pri | Wave | Notes |
|------|-----|:----:|:--:|:---:|-----------------|
| Basic execution / CPU presence | direct | G | 1 | 0 | minimum viability (smoke) |
| ADD/ADC/SUB/SBB/CMP/NEG | operand×flag-seed×width×addr | G,H | 1 | 1 | flag corners incl. AF; carry chains |
| INC/DEC | operand×flag-seed | G,H | 1 | 1 | must preserve CF (§3.1) |
| MUL/IMUL | operand classes×width | G,H | 1 | 1 | undefined SF/ZF/AF/PF pinned golden (§3.1) |
| DIV/IDIV | operand + fault cases | G,H | 1 | 2 | #DE conditions; 8086-vs-286 return CS:IP (§3.2) |
| AND/OR/XOR/TEST/NOT | operand×flag-seed | G,H | 1 | 1 | AF undefined→golden; CF/OF cleared |
| SHL/SHR/SAR | value×count-classes×flag-seed | G,H | 1 | 1 | count-0 no-op, mask, OF-by-1 only (§3.1) |
| ROL/ROR/RCL/RCR | value×count×CF-seed | G,H | 2 | 1 | RCL/RCR carry threading; OF>1 undefined |
| String MOVS/STOS/LODS/CMPS/SCAS | dir×rep×seg-override×width | G,H | 1 | 1 | DF save/restore; REP+override combinatorics |
| Jcc / JMP / LOOP / JCXZ | condition×flag-seed×disp-size | G,H | 2 | 1 | all 16 Jcc; near/short |
| CALL/RET (near/far) | depth×far/near×imm-pop | G | 2 | 1 | stack integrity; far CS:IP |
| PUSH/POP/PUSHF/POPF | reg×mem×flag round-trip | G,H | 2 | 1 | reserved FLAGS bits (§3.1); PUSH SP 8086 quirk |
| Segment load MOV/LES/LDS | seg reg × source | G | 2 | 1 | real-mode load; base recompute |
| BCD AAA/AAS/AAM/AAD/DAA/DAS | operand×AF/CF-seed | G,H | 2 | 1 | AAM/AAD non-10 imm (§3.2); undefined flags golden |
| XCHG/XLAT/LEA | operands×addr | G,H | 3 | 1 | LEA addr math incl. odd forms |
| Flag ops STC/CLC/CMC/STD/CLD/STI/CLI | direct | G | 3 | 1 | STI 1-insn delay (→ §10.2) |
| NOP/HLT/WAIT/LOCK/ESC | presence/effect | G⁺ | 3 | 0 | HLT wake on IRQ; LOCK on bad target |
| Encoding/undocumented | SALC, POP CS(8086), F1/ICEBP, 82 alias, 60-6F alias, redundant prefixes | G | 2 | 2 | §3.3 — generation-gated |
| Addressing modes | all 16-bit ModR/M forms | G,H | 2 | 1 | per representative op (§2) |
| Prefetch queue (SMC) | write-ahead-of-IP | G⁺ | 3 | 3 | stale-vs-fresh yes/no only; depth →C (§3.3) |
| Segment/offset wrap | offset 0xFFFF word access | G | 2 | 2 | real-mode wrap vs 286 #GP |

*8086 exact cycle counts / prefetch depth / bus timing → C/T (not here).*

### 3.1 Hard cases — Flag semantics

The single largest source of emulation bugs. Many corners are "undefined" per Intel —
which means real silicon still produces *deterministic* values software depended on.

**Officially undefined flags (still deterministic on real HW):**

| Instruction | Undefined flags | Real-hardware behavior | Emulator risk | Pri |
|-------------|-----------------|------------------------|---------------|:---:|
| `MUL`/`IMUL` | SF, ZF, AF, PF | Set from internal result; varies 8086↔386↔486 | High — often left unchanged | 1 |
| `DIV`/`IDIV` | CF, OF, SF, ZF, AF, PF | Non-deterministic across steppings | High | 1 |
| `SHL/SHR/SAR` by >1 | OF | Defined only for count==1; multi-bit OF varies | High | 1 |
| `SHL/SHR` by 0 | (none change) | **All flags unchanged** — masked count | Very high — commonly wrong | 1 |
| `ROL/ROR/RCL/RCR` by >1 | OF | Undefined; real value varies | Medium | 1 |
| `AAM`/`AAD` | OF, CF, AF | Set from internal DAA-like logic | Medium | 1 |
| `AAA`/`AAS` | OF, SF, ZF, PF | Undefined but deterministic | Medium | 1 |
| `DAA`/`DAS` | OF | Undefined | Medium | 1 |
| `AND/OR/XOR/TEST` | AF | **Undefined** — real HW leaves a specific value | Medium | 1 |
| `NEG` | AF, CF rules | CF = (operand != 0) | Medium | 1 |
| `BT/BTS/BTR/BTC` (386+) | OF,SF,AF,PF | Only CF defined; **memory form with bit offset ≥ operand size crosses into adjacent bytes** (Intel SDM) | Medium | 1 |
| `BSF/BSR` (386+) | ZF defined; others undefined | dest unchanged if src==0 | High | 1 |

*Test strategy:* capture the *actual* flag value on reference hardware/known-good
emulator into a golden vector, then assert byte-exact FLAGS match. We do NOT assume the
manual's "undefined" — we pin the observed silicon value and flag any core that
deviates (tag `undefined-flag-divergence`; informational but reported).

**Shift/rotate count masking:**
- 8086/8088/80186: count is **NOT masked** — `SHL AX,CL` with CL=255 shifts 255 times.
- 80286+: count masked to 5 bits (`count & 0x1F`), including 286 real mode. **Genuine
  architectural difference and a common emulator bug.**
- Test `SHL AX,CL` with CL ∈ {0,1,15,16,17,31,32,33,255}, verify result+flags,
  generation-gated.

**Other flag rules:**
- **Parity** reflects the **low 8 bits only**, even for 16/32-bit results.
- **INC/DEC do not affect CF** (only OF/SF/ZF/AF/PF) — relied on in multi-precision loops.
- **Reserved FLAGS bits:** bit1=1, bits3/5=0; on 8086/88 bits12-15 always set; on 286
  they gate CPU detection. Test raw PUSHF/POPF round-trip and the detection algorithm.

### 3.2 Hard cases — Arithmetic edge cases

**Division faults:**

| Case | Expected |
|------|----------|
| `DIV`/`IDIV` by 0 | #DE (INT 0) |
| `DIV` quotient > max (e.g. 0xFFFF/1 in 8-bit) | #DE |
| `IDIV` 0x8000 / 0xFFFF (INT_MIN / −1) | #DE (overflow) |
| Return address pushed on #DE | **8086 pushes NEXT-instruction address; 286+ push the DIV's own address** |

The #DE return-address difference between 8086 and 286+ is a classic divergence — test
the actual pushed CS:IP in the handler.

**AAM/AAD with non-10 immediate (undocumented):** `AAM` is `D4 0A`; the `0A` is an
**immediate divisor**. `D4 08` = base-8 adjust; same for `AAD` (`D5 imm`). Real HW
honors the immediate; many emulators hardcode base-10. Test `D4 10`, `D5 02`, etc.

**Multi-precision/BCD chains:** realistic ADC/SBB chains and DAA/DAS after ADD/ADC,
including the AF-dependent paths (which the "undefined" AF from prior ops feeds).

### 3.3 Hard cases — Encoding & decoding

**Undocumented / aliased opcodes:**

| Opcode | Meaning | Notes |
|--------|---------|-------|
| `D6` | `SALC` (Set AL from Carry) | Undocumented, all generations |
| `0F` on 8086 | `POP CS` | 8086/88 ONLY; becomes 2-byte prefix on 286+ |
| `F1` | `ICEBP`/`INT1` | Undocumented single-byte INT1 |
| `82` | Alias of `80` (group1 r/m8,imm8) | Redundant, valid all gens |
| `60-6F` on 8086 | Aliases of `70-7F` (Jcc) | 8086 only; 186+ = PUSHA/POPA/etc |
| REP on non-string | Ignored / quirky | Test REP prefix on non-string op |
| Multiple/redundant prefixes | Last-wins for segment; length effects | Prefix-count / length limits |

**Redundant prefix behavior:** which segment prefix wins; LOCK on invalid target → #UD
on 286+ vs ignored on 8086; operand/address-size prefix stacking (386+); 386+ effective
instruction-length limits (long prefix chains → #GP/#UD).

**ModR/M & SIB corners (386+):** SIB no-base (`base==5`,mod==0)→disp32 absolute;
ESP-as-index illegal encoding; 16-bit vs 32-bit addressing tables differ entirely
(address-size prefix) — a frequent decoder bug.

**8086/8088 prefetch queue:** 6-byte (8086) / 4-byte (8088). **Self-modifying code**:
writing to an instruction already queued executes the *old* bytes — observable, and the
basis of the classic 8086-vs-8088 queue-length detector. Guest test writes ahead of IP
and checks stale-vs-fresh; exact depth is co-sim territory.

---

## 4. FPU — 8087 / 287 / 387 / 486 (Pri 1; a domain of its own)

| Area | Dim | Venue | Pri | Wave | Notes |
|------|-----|:----:|:--:|:---:|-----------------|
| FPU presence / basic init | direct | G | 1 | 0 | FNINIT / FSTSW smoke |
| Load/store FLD/FST/FSTP/FILD/FIST/FBLD/FBSTP | type×value-class | G,H | 1 | 1 | 32/64/80-bit + int + BCD round-trip |
| Arith FADD/FSUB(R)/FMUL/FDIV(R)/FSQRT | value×RC×PC | G,H | 1 | 1 | rounding/precision control (§4.2) |
| Special values | NaN(S/Q)/±Inf/±0/denormal propagation | G,H | 1 | 1 | which NaN survives; ∞−∞→indefinite (§4.1) |
| Compare FCOM/FUCOM/FTST/FXAM | value pairs incl. NaN/±0 | G,H | 1 | 1 | C0–C3; FUCOM vs FCOM on QNaN (§4.4) |
| Stack/tag FLD dup/FXCH/FINCSTP/FDECSTP/FFREE | fill states | G,H | 1 | 1 | overflow/underflow→#IS; tag word (§4.3) |
| Control FLDCW/FSTCW/FCLEX/FSTSW/FNINIT | cw/sw round-trip | G,H | 1 | 2 | default 0x037F; SW TOP field |
| Exceptions IE/DE/ZE/OE/UE/PE | masked/unmasked triggers | G,H | 1 | 2 | deferred #MF model; FWAIT (§4.7) |
| Save/restore FSAVE/FRSTOR/FSTENV/FLDENV | mode×gen image format | G,H | 1 | 1 | 14/28/94/108-byte layouts differ (§4.7) |
| Transcendentals (387+) FSIN/FCOS/FSINCOS/FPTAN/FPATAN/F2XM1/FYL2X/FYL2XP1 | domain+range | G,H | 2 | 2 | C2 out-of-range; π-reduction ULP vs host (§4.5) |
| FPREM/FPREM1 (387+) | dividend/divisor + partial loop | G,H | 2 | 1 | trunc vs round; C0/C1/C3 quotient bits (§4.6) |
| FRNDINT/FSCALE/FXTRACT/FABS/FCHS | value×RC | G,H | 2 | 1 | rounding-mode dependence |
| Constants FLD1/FLDZ/FLDPI/FLDL2E/… | direct | G,H | 3 | 1 | exact 80-bit values |
| Detection / 287-vs-387 | infinity affine/projective | G | 2 | 0 | real detection code |
| CPU-FPU sync (WAIT/FWAIT) | pending-exception delivery | G,H | 1 | 2 | IRQ13 vs #MF per config (§4.7) |

*FPU internal guard/round/sticky & 68-bit datapath → C (not observable).*

The FPU is where "it mostly works" hides the most bugs; IEEE-754 corners are vast.

### 4.1 Special values & propagation
Signaling vs quiet NaN; NaN propagation (which operand's NaN survives); QNaN indefinite
(`0xFFC0…`). Infinity arithmetic: ∞−∞→invalid→indefinite; ∞/∞; 0×∞. Signed zero: −0 vs
+0, `FCOM` treats equal but `FXAM` distinguishes. Denormals: creation, denormal-operand
exception (#D). Pseudo-denormals/-NaN/-infinity (80-bit unnormals) — 387 vs 486 differ.

### 4.2 Precision & rounding control
PC field (24/53/64-bit) affects **only** ADD/SUB/MUL/DIV/SQRT rounding, not load/store.
RC field: nearest/down/up/truncate — test each with values that round differently.
Double-rounding artifacts when PC=53 but internal is 64. FLDCW effects and delayed apply.

### 4.3 Stack & tag word
8-deep stack, TOP field in status word. Overflow (push to full)/underflow (pop empty) →
#IS (C1 indicates which). Tag word valid/zero/special/empty per register (FSTENV/FSAVE
format). FXCH with empty register. FINCSTP/FDECSTP move TOP without exception.

### 4.4 Condition codes (C0–C3)
FCOM/FUCOM/FTST set C0/C2/C3 like flags; FXAM sets C0–C3 to classify operand. FSTSW AX +
SAHF pattern. FUCOM (387+) vs FCOM difference on QNaN (unordered without #IA).

### 4.5 Transcendentals & argument reduction
FSIN/FCOS/FPTAN/FSINCOS (387+): valid range |x|<2^63, C2 "operand out of range" when
exceeded. **Argument reduction accuracy** near multiples of π/2 — the 387's 66-bit π
approximation causes large ULP errors for huge arguments. Emulators using host `sin()`
**disagree with real 387/486** — a real, testable divergence. FYL2X/FYL2XP1/F2XM1
domains; FPATAN quadrants.

### 4.6 FPREM vs FPREM1
FPREM (8087-compat) truncates; FPREM1 (387+) rounds-to-nearest (IEEE) — different
results. The partial-remainder loop (C2=incomplete) and the C0/C1/C3 quotient bits.

### 4.7 Exception model & FWAIT
Masked vs unmasked; six flags (IE/DE/ZE/OE/UE/PE). **Deferred reporting:** an unmasked
exception is signaled on the *next* FPU/WAIT instruction (pending-x87 model), not
immediately — via #MF (vector 16, 486) or external IRQ13/FERR (older). 8087 used INT via
8259; 286/387 used #MF or IRQ13; ao486 = integrated #MF. Test delivery per config.
FNSAVE/FNSTENV mask all exceptions as a side effect. Environment/state image format
(14-byte real, 28-byte protected, 94/108-byte FSAVE) differs by mode/generation — test
save/restore round-trips. Detection: FNINIT then FNSTCW/FNSTSW; default CW 0x037F;
287-vs-387 infinity test (projective vs affine).

---

## 5. CPU — 80186 (Pri 3, thin layer)

| Area | Dim | Venue | Pri | Wave | Notes |
|------|-----|:----:|:--:|:---:|-----------------|
| 186 detection / invalid opcode | direct | G | 1 | 0 | 186 presence smoke |
| ENTER/LEAVE | nesting level 0/1/n | G,H | 3 | 1 | frame chain build |
| BOUND | in/out of range | G,H | 3 | 1 | #BR (INT5) |
| PUSHA/POPA | reg set round-trip | G,H | 3 | 1 | order; SP handling |
| PUSH imm / IMUL imm | value classes | G,H | 3 | 1 | new immediate forms |
| Shift/rotate by imm8 | count classes | G,H | 3 | 1 | 8086 had no imm-count |
| INS/OUTS | port×dir×rep | G | 3 | 1 | HW venue for real ports |
| Enhanced opcode gating | 8086-alias vs 186-defined | G | 3 | 1 | 60-6F now defined (§3.3) |

---

## 6. CPU — 80286 (Pri 1 for PM; the first big divergence surface)

| Area | Dim | Venue | Pri | Wave | Notes |
|------|-----|:----:|:--:|:---:|-----------------|
| 286 CPU detection | direct | G | 1 | 0 | 286 presence smoke |
| Real-mode extensions | 186 ISA on 286 | G,H | 3 | 1 | plus shift-count mask now active |
| PM entry (LMSW/MOV CR0) | real→PM | G(RING0) | 1 | 1 | 286 quirks; self-switch |
| Descriptor load checks | null/present/type/DPL/RPL/limit | G(RING0) | 1 | 2 | full check matrix (§6.1) |
| Accessed bit | descriptor RMW on load | G(RING0) | 1 | 2 | must write back (§6.1) |
| Segment limit enforce | last-byte, expand-down | G(RING0) | 1 | 1 | inverted expand-down (§6.2) |
| Call gates / privilege | CPL/DPL/RPL, param copy, stack switch | G(RING0) | 1 | 2 | gate matrix (§6.3) |
| Task switch / TSS | busy bit, SS0:SP0, backlink | G(RING0) | 2 | 1 | 16-bit TSS |
| Exceptions #GP/#NP/#SS/#TS | vector + error code + restart | G(RING0) | 1 | 2 | error-code encoding |
| LOADALL (0F 05) | state-block load | G(RING0)/→C | 3 | 1 | constructible subset only (§6.4) |
| SGDT/SIDT/SLDT/STR/LAR/LSL/VERR/VERW | descriptor queries | G(RING0) | 2 | 2 | 286 high-byte SGDT quirk |
| PM→real escape | reset/KBC/triple-fault path | G⁺/→C | 3 | 2 | post-reset →C |

Segmentation & protected mode is the richest source of subtle bugs; ao486 must
implement the full descriptor model.

### 6.1 Hard cases — Descriptor loading semantics

| Behavior | Detail | Common bug |
|----------|--------|------------|
| Accessed bit | Set on segment load (RMW to descriptor in memory) | Not writing A bit back |
| Null selector | Null into DS/ES/FS/GS legal; **use** faults | Faulting on load |
| Null into SS | #GP immediately | Allowing it |
| Present bit | #NP (or #SS for stack) if P=0 | Wrong vector |
| DPL/RPL/CPL | Privilege math on load | Off-by-one |
| Type checks | Data-into-CS, exec-only-into-DS → #GP | Missing checks |
| Table limit | Selector index beyond GDT/LDT limit → #GP | Not checking table limit |

### 6.2 Hard cases — Segment limit enforcement
**Expand-down segments** (stacks): limit semantics inverted — valid offsets are *above*
the limit (very bug-prone). Byte vs page granularity (G bit, 386+): limit ×4K with low
12 bits set to 1. 16-bit vs 32-bit default (D/B bit) affecting SP vs ESP width
(the big-real/stack-size subtlety). Limit check on the *last byte* of a word/dword
straddling the limit.

### 6.3 Hard cases — Gates & privilege transitions
CALL through a call gate: parameter copying, stack switch, CPL change. The **TSS**
stack-switch (SS0:SP0), busy bit on task gates. RETF/IRET privilege checks and RPL
adjustment. Conforming vs non-conforming code segments. Interrupt gate vs trap gate (IF
handling); gate DPL vs CPL.

### 6.4 Hard cases — Transitions & LOADALL
286 could enter PM but not cleanly leave (needed reset/LOADALL/triple-fault); 386+ clean
via CR0.PE. **Unreal/big real mode:** load a 4G-limit descriptor, drop to real mode,
keep the large limit — a common DOS-extender trick cores frequently break. A20
interaction. **LOADALL** (286 `0F 05`, 386 `0F 07`) loads entire CPU state from a memory
block; used by HIMEM/early extenders, rarely emulated — test the constructible subset.

---

## 7. CPU — 80386 (Pri 1; 32-bit + paging + V86)

| Area | Dim | Venue | Pri | Wave | Notes |
|------|-----|:----:|:--:|:---:|-----------------|
| 386 CPU detection | direct | G | 1 | 0 | ✓ core detection (`detect_cpu`) |
| 32-bit ALU (ADD/SUB/ADC/SBB/MUL/DIV/INC/DEC/NEG) | as §3 at 32-bit | G,H | 1 | 1 | ✓ `src/cpu/80386/arith32.asm` (35 sub-tests) |
| 32-bit string ops (MOVSD/STOSD/LODSD/CMPSD/SCASD + REP) | dir×rep×width | G,H | 1 | 1 | ✓ `src/cpu/80386/strings32.asm` (12 sub-tests) |
| MOVSX/MOVZX/SETcc | value×flag | G,H | 1 | 1 | ✓ `src/cpu/80386/new_insns.asm` (29 sub-tests) |
| BT/BTS/BTR/BTC | reg×mem×bit-index | G,H | 1 | 1 | ✓ `src/cpu/80386/bitops.asm` (25 sub-tests). **Gap:** bit-offset ≥32 address crossing untested — DOSBox-X core=normal does not implement; TODO: 86Box/real HW |
| BSF/BSR (src=0 dest-unchanged) | value | G,H | 1 | 1 | ✓ `src/cpu/80386/bitops.asm` (§3.1) |
| SHLD/SHRD (count masking, OF count=1) | value×count×flag | G,H | 1 | 1 | ✓ `src/cpu/80386/shifts32.asm` (24 sub-tests) |
| LFS/LGS/LSS + PUSHFD/POPFD + PUSH imm32 | far ptr×flag | G,H | 1 | 1 | ✓ `src/cpu/80386/seg386.asm` (11 sub-tests) |
| 32-bit addressing/SIB (all scales, base, index, disp32) | scale×base×index | G,H | 1 | 1 | ✓ `src/cpu/80386/addr32.asm` (17 sub-tests). ESP-as-index illegal encoding still TODO |
| Paging translate | 4K PDE/PTE walk | G(RING0) | 1 | 1 | ✓ `src/cpu/80386/ring0.asm` test 9 (identity map + PG enable) |
| #PF error code | P/W/U combinations | G(RING0) | 1 | 1 | ✓ `src/cpu/80386/ring0.asm` test 10 (unmapped page → #PF + CR2) |
| A/D bits | set on access/write | G(RING0) | 2 | 1 | ✓ `src/cpu/80386/ring0.asm` test 11 (read→A only; write→A+D) |
| TLB staleness / MOV CR3 flush | change-without-flush | G(RING0) | 2 | 3 | ✓ `src/cpu/80386/ring0.asm` test 10 (CR3 flush after PTE clear) |
| V86 mode | enter/exit, IOPL-sensitive, IRQ reflect | G(RING0) | 2 | 2 | §10 |
| Debug registers DR0-7 | breakpoints exec/rw, len | G(RING0) | 2 | 2 | #DB on match; GD bit |
| Control regs CR0/2/3 | bit semantics | G(RING0) | 2 | 1 | ✓ `src/cpu/80386/ring0.asm` tests 1-2 (PE bit, CR3 R/W); **Gap:** reserved-bit behavior untested |
| Unreal/big-real mode | large limit persists to real | G(RING0) | 2 | 1 | extender trick (§6.4) |
| CR/DR/TR reserved bits | write/read-back | G(RING0)/→C | 3 | 1 | some combos →C |

### 7.1 Hard cases — Paging
**#PF error code** encodes P/W/U (RSVD, I/D on later): bit0 P (0=not-present/1=protection),
bit1 W/R, bit2 U/S. Deliberately fault each combination and decode the pushed code.
**A/D bits:** A set on any access, D on write; test final values (timing/atomicity →C);
whether A/D update the PDE too. **TLB:** `INVLPG` (486) invalidates one entry; MOV CR3
flushes all; change a PTE without flush and confirm the old translation persists until
flush (a legitimate, testable behavior). **Write-protect (486 CR0.WP):** WP=0 supervisor
can write R/O user pages; WP=1 supervisor write to R/O → #PF (COW support; 386 lacked
enforcement on some steppings).

---

## 8. CPU — 80387 & 80486 (Pri 1–2)

| Area | Dim | Venue | Pri | Wave | Notes |
|------|-----|:----:|:--:|:---:|-----------------|
| 486 CPU detection | direct | G | 1 | 0 | 486 presence smoke. ✓ `src/cpu/80486/new486.asm` (capability gate + CPUID) |
| 387 new insns / IEEE FPREM1 / FUCOM | see §4 | G,H | 2 | 1 | ✓ `src/fpu/80387/new387.asm` (15 sub-tests: FPREM1, FUCOM/FUCOMP/FUCOMPP, FSIN/FCOS/FSINCOS, 387 CW default) |
| 387 detection & init handshake | 386+387 vs 486 | G | 2 | 0 | CW default test in new387. **Gap:** 287-vs-387 infinity test needs 287 HW |
| 486 BSWAP | 32-bit; 16-bit undefined | G,H | 2 | 1 | ✓ `src/cpu/80486/new486.asm` (7 BSWAP tests). **Gap:** 16-bit undefined result needs golden vector |
| 486 XADD/CMPXCHG | value×flag×LOCK | G,H | 1 | 1 | ✓ `src/cpu/80486/new486.asm` (8 tests: value+flags+LOCK variants) |
| 486 INVD/WBINVD | effect | G⁺(RING0) | 3 | 1 | ✓ `src/cpu/80486/ring0_486.asm` tests 1-2 (instruction recognition, no #UD) |
| 486 INVLPG | single-entry flush | G(RING0) | 2 | 1 | ✓ `src/cpu/80486/ring0_486.asm` test 3 (instruction recognition). **Gap:** TLB-invalidation verification needs 86Box (DOSBox-X may not flush single-page entries) |
| 486 cache coherence (SMC) | write to cached code line | G⁺(RING0) | 1 | 3 | fetched-bytes result G; fill →C (§8.2) |
| 486 #AC alignment | AM×AC×CPL3×misalign | G(RING0) | 2 | 1 | ✓ `src/cpu/80486/ring0_486.asm` test 5 (CR0.AM + EFLAGS.AC bit set/readback). **Gap:** #AC delivery needs 86Box (DOSBox-X may not implement) |
| 486 CPUID | ID-bit toggle, leaf 0/1 | G,H | 2 | 1 | ✓ `src/cpu/80486/new486.asm` (ID toggle, leaf 0 vendor, leaf 1 features) |
| 486 cache enable CR0.CD/NW, PCD/PWT | timing band | G⁺(RING0) | 3 | 3 | ✓ `src/cpu/80486/ring0_486.asm` test 6 (CD/NW set/clear/readback). **Gap:** PCD/PWT + timing bands →C/T |

### 8.1 Hard cases — 486 new instructions
`BSWAP` is 32-bit; behavior on a 16-bit operand is documented **undefined** — pin the
actual result. `XADD` atomic exchange-add + flags + LOCK variant. `CMPXCHG` ZF/accumulator
semantics (compare against AL/AX/EAX) + LOCK. `INVD` invalidates cache **without**
writeback (destructive); `WBINVD` writes back then invalidates; `INVLPG` single-page.

### 8.2 Hard cases — Cache behavior
On-chip 8K unified L1 (write-through on stock 486). **Self-modifying code coherence:** a
write to a cached code line must be reflected in the next i-fetch — a key ao486
correctness test (functional result is G; fill/LRU structure →C/T). Cache-disable via
CR0.CD/NW and PCD/PWT; cacheability timing (cached vs uncached loop) is a measurable band.

### 8.3 Hard cases — Alignment check (#AC)
CR0.AM + EFLAGS.AC + CPL==3 → misaligned access faults #AC (vector 17), user mode only.
Test word at odd address, dword crossing alignment, with/without AM/AC.

### 8.4 Hard cases — CPUID
Not on early 486; EFLAGS.ID toggle detects presence. Leaf 0 (vendor string), leaf 1
(family/model/features). **Clones differ** (AMD/Cyrix/UMC) — record, don't hard-fail on
vendor string.

---

## 9. Peripherals (Pri 1–2 — the project's least-duplicated coverage)

ao486 integrates these; register R/W is table-stakes, **stateful** behavior is the value.

| Device | Dim | Venue | Pri | Wave | Notes |
|--------|-----|:----:|:--:|:---:|-----------------|
| Peripheral basic presence | direct | G(HW) | 1 | 0 | peripheral smoke |
| **8259 PIC** | ICW1-4 init, EOI (specific/non/rotating), IRR/ISR read, cascade order, spurious IRQ7/15, special mask, poll, edge/level | G(HW) | 1 | 3 | §9.1 — spurious IRQ is signature test |
| **8254 PIT** | modes 0-5, latch vs read-back+status, null-count flag, count=0→65536, BCD, access lo/hi/lohi flip-flop, GATE, ch2+speaker | G(HW) | 1 | 2 | §9.2 |
| **8237 DMA** | single/block/demand, autoinit, TC+status, byte flip-flop, page reg, 64K boundary, incr/decr, cascade ch4 | G(HW) | 2 | 3 | §9.3; no destructive real DMA |
| **8042 KBC** | cmd/data IBF/OBF seq, A20 via output port, self-test AA→55, port2/mouse | G(HW) | 2 | 1 | §9.4 |
| **MC146818 RTC** | UIP flag, BCD/bin, 12/24h+PM, alarm don't-care, Status C read-clears | G(HW) | 2 | 1 | §9.5; non-destructive |
| **IDE/ATA(PI)** | BSY/DRQ/DRDY protocol, 400ns settle, IDENTIFY layout, LBA/CHS, READ MULTIPLE, alt-status, ATAPI packet | G(HW) | 2 | 1 | §9.6; scratch media only |
| **VGA** | AC index/data flip-flop, latches+write modes 0-3/read 0-1, map/bit mask, set/reset, CRTC protect, DAC 3-write+auto-inc, chain-4/mode-X | G(HW) | 2 | 1 | §9.7 — flip-flop is signature |
| **PC speaker** | PIT ch2 gate + port 61 | G(HW) | 3 | 0 | tone gen presence |
| **AdLib/OPL2** | reg write, timer status read-back | G(HW) | 3 | 1 | timer1/2 expiry flags |
| **OPL3** | 4-op enable, dual-bank | G(HW) | 3 | 0 | detection via timer |
| **Sound Blaster DSP** | reset handshake, version, DMA playback | G(HW) | 3 | 1 | DMA path |
| **Gravis GUS** | RAM peek/poke, voice regs | G(HW) | 4 | 0 | detection + RAM; *scope TBD — see note below* |
| **MPU-401** | UART mode, cmd ack | G(HW) | 4 | 1 | *scope TBD — see note below* |
| **8250/16550 UART** | DLAB, loopback self-test, FIFO+IIR, scratch-reg chip ID, MSR delta | G(HW) | 2 | 1 | §9.8; loopback avoids wiring |
| **Parallel LPT** | data/status/control loop | G(HW) | 4 | 1 | *scope TBD — see note below* |

*Bus/pin timing, DMA cycle-steal exact timing → T (not here).*

Register R/W tests are table-stakes; the gaps are in **stateful** behavior.

> **Peripheral scope note (prep-phase A2):** ao486 integrates PIC, PIT, DMA,
> KBC, RTC, IDE, VGA, and Sound Blaster/OPL.  **GUS, MPU-401, and LPT**
> are *not confirmed* as integrated peripherals on the ao486 core.  They are
> listed here as Pri-4 stretch goals but are **deferred to Phase 2+** and
> may move to §16 (out of matrix) if ao486 lacks the hardware.  OPL3 and
> SB-mixer are kept in-scope (ao486 audio path) but at reduced Pri.

### 9.1 8259A PIC
Cascade EOI ordering (slave then master); specific vs non-specific EOI; rotating priority
(auto + specific); special mask mode; poll mode (read ISR via poll); IRR vs ISR (OCW3
select); **spurious IRQ7/IRQ15** — IRQ dropped before INTA returns the lowest-priority
vector with no ISR bit set (genuine, testable, often missed); edge vs level; ICW4 auto-EOI.

### 9.2 8254 PIT
Count==0 means 65536; BCD counting; latch vs read-back (status+count); mode transitions
mid-count (reload); GATE effect per mode (esp. 1/5 retriggerable); the **null-count flag**
in read-back status; access LSB-only/MSB-only/LSB-then-MSB and the flip-flop state; channel
2 + speaker port (0x61) gating.

### 9.3 8237 DMA
64K/128K boundary limit (can't cross page-register boundary); page register + 16-bit
address composition (16-bit channels word-shift); auto-init reload; terminal count + status
read (clears TC); byte-pointer flip-flop; cascade channel 4; address increment vs decrement.
No destructive real DMA — scratch buffers only.

### 9.4 8042 KBC
Command/data sequencing via IBF/OBF; A20 via output-port bit 1; self-test (0xAA→0x55);
output-buffer-full IRQ1 timing; multiplexed mouse (port 2, 0xD4 prefix).

### 9.5 MC146818 RTC
Update-in-progress (UIP) — don't read time while set; BCD vs binary (Status B bit 2);
12/24-hour and the PM bit; alarm "don't care" (0xC0) bytes; periodic/alarm/update flags in
Status C (read clears); century-byte ambiguity. Non-destructive (save/restore).

### 9.6 IDE/ATA
BSY/DRQ/DRDY protocol and the 400ns post-command delay; IDENTIFY word layout (word 0, 49
caps, 60/61 LBA sectors, 83 command sets); LBA vs CHS; READ MULTIPLE block factor; alternate
status (no side effects) vs status (clears IRQ); ATAPI packet protocol and byte-count limit;
device selection (drive bit) + 400ns settle.

### 9.7 VGA
Attribute-controller **flip-flop** (shared index/data at 0x3C0, reset by reading 0x3DA) —
notorious; latch registers (4 planes) and read/write-mode matrix (write 0-3, read 0-1);
plane/map mask, bit mask, set/reset; CRTC protect (index 0x11 bit 7) locking 0x00-0x07; DAC
read/write index auto-increment and the 3-write RGB sequence; sequencer reset and chain-4
(mode 13h); mode-X unchained planar.

### 9.8 UART 8250/16550
DLAB gating DLL/DLH vs data/IER; scratch-register presence (8250 lacks it → chip-ID); FIFO
enable + trigger levels (16550A) and IIR FIFO-status bits; loopback mode (MCR bit 4) for
self-test without a wire; modem-status delta bits; 16550-vs-16550A FIFO-bug detection.

---

## 10. System Integration (Pri 1 — uniquely guest-observable)

| Area | Dim | Venue | Pri | Wave | Notes |
|------|-----|:----:|:--:|:---:|-----------------|
| A20 gate + 1MB wrap | on/off × KBC/fast-A20 | G(HW) | 1 | 2 | FFFF:0010 wrap (§10.1) |
| Interrupt boundaries | MOV SS shadow, STI 1-insn delay, TF interplay | G(RING0) | 1 | 1 | §10.2 |
| Exception taxonomy | fault/trap/abort restart, error-code-push set | G(RING0) | 1 | 2 | §10.2 |
| Double fault | contributory vs benign | G(RING0) | 2 | 2 | triple→reset is →C |
| Nested IRQ + IF | INT gate clears IF, IRET restores | G(HW) | 2 | 2 | §10.2 |
| Mode transitions | real↔PM↔V86, unreal persistence | G(RING0) | 1 | 2 | functional only |
| Memory map/aliasing | conv/UMA/HMA, video B000/B800/A000 | G | 3 | 1 | shadow RAM chipset-dep note |
| BIOS data area / INT services | INT 10/13/16/1A sanity | G(HW) | 3 | 0 | integration smoke |

### 10.1 Hard cases — A20 & address space
A20 off → line 20 forced 0, 1MB wraparound (HMA / `FFFF:0010` wrap). Enable paths: KBC
(0xD1 / output-port bit 1), fast A20 (port 0x92 bit 1). Test the wrap: read `FFFF:0010`
returns `0000:0000` when A20 off. Also: word/dword at segment-limit wrap (real-mode wrap on
8086 vs #GP on 286+); stack wrap (SP=0xFFFF push). Memory-type regions: conventional (0-640K),
UMA/ROM/video holes, HMA, extended; video aliasing (A000/B000/B800); shadow-RAM behavior is
chipset-dependent (note only).

### 10.2 Hard cases — Interrupts & exceptions
**Classification:** faults (restart, CS:IP = faulting insn) vs traps (CS:IP = next) vs aborts;
#DB/#BP/#OF are traps, #DE is a fault; which vectors push an error code; simultaneous-exception
priority (precise ordering →C). **Double/triple fault:** #DF (vector 8) contributory-vs-benign;
triple → reset (observable only in sim). **Nested IRQ & IF:** interrupt gate clears IF, trap
gate doesn't; IRET restores IF from stacked FLAGS; NMI masking latch. **Boundaries:** interrupts
checked at instruction boundaries *except* after `MOV SS`/`POP SS` (interrupts and single-step
inhibited for one following instruction, making `MOV SS`/`MOV SP` atomic) and `STI` (IF-enable
delayed one instruction) — genuine and frequently missed. **TF:** set → #DB after each
instruction; the `MOV SS` shadow also masks TF; POPF/IRET setting TF steps the *next* instruction.

---

## 11. Timing Constellations (Pri 4 — bands, never hard-fail)

| Area | Dim | Venue | Pri | Wave | Notes |
|------|-----|:----:|:--:|:---:|-----------------|
| Cached vs uncached loop | delta band | G⁺ | 4 | 3 | proves cache active; structure →C/T |
| Branch taken/not-taken | ratio | G⁺ | 4 | 1 | |
| Interrupt latency | INT→handler coarse | G⁺ | 4 | 1 | exact →C |
| FDIV/transcendental latency | band | G⁺ | 4 | 2 | |
| DMA throughput | aggregate | G⁺ | 4 | 2 | cycle-steal exact →T |

These are measurements compared against a **per-target reference band** (e.g. 486DX-33, 0
wait states), reported as deviation, never a binary fail. Cycle-exact numbers are
co-sim/bench territory. Measured via PIT ch2 (~838ns) or TSC (late 486+).

---

## 12. Coverage Accounting (estimated, guest-implementable only)

| Block | Est. high-value cases | Venue split |
|-------|----------------------:|-------------|
| 8086/88 CPU | ~4,500 | G,H |
| 80186 | ~400 | G,H |
| 80286 PM | ~2,000 | G(RING0) |
| 80386 (32b+paging+V86+debug) | ~4,500 | G(RING0),H |
| 80486 (insns+cache+#AC+CPUID) | ~800 | G(RING0),H |
| FPU 8087/287/387/486 | ~4,000 | G,H |
| Peripherals | ~1,500 | G(HW) |
| System integration | ~600 | G(RING0/HW) |
| Timing (bands) | ~150 | G⁺ |
| **Total (guest)** | **~18,500** | — |

Exhaustive per-instruction vectoring (10⁶⁺) is **out of guest scope** and owned by
SingleStepTests co-sim; we import a curated subset for constructible edge cases.

---

## 13. Cross-Cutting Requirements (apply to every test)

| Requirement | Why it matters |
|-------------|----------------|
| **State non-corruption** | A test that leaves FPU stack/descriptor tables/DF/PIC masks dirty poisons later tests. Snapshot/restore everything touched. |
| **CPU-generation gating** | A 386 test on a 286 must SKIP cleanly, not #UD-crash. Central detect + capability table before any suite runs. |
| **Determinism** | RTC/timer-seeded tests log the seed. No live RNG. |
| **Handler safety** | Exception-triggering tests install handlers; a spurious real interrupt mid-test must be distinguishable. |
| **Target the unexercised** | Games hit a narrow path; our value is the corners games DON'T hit — prioritize accordingly. |
| **Vendor divergence** | AMD/Cyrix/UMC/NEC V20/V30 differ (V20/V30 add 80186 ISA + 8080 mode). Tag, don't fail. |

---

## 14. Prioritized Build Order (max bug-yield first)

Ranked by (bug frequency in emulators) × (guest-side testability):

1. **Flag semantics** — shifts by 0/masked-count, undefined-but-deterministic flags,
   INC/DEC carry preservation (§3.1). *Highest yield, easy guest-side.*
2. **Division faults** — #DE conditions and the 8086-vs-286 return-address (§3.2).
3. **String ops + REP + segment override + DF** — combinatorial, heavily used.
4. **PM descriptor loading** — accessed bit, null selector, limit/type/privilege (§6.1).
5. **FPU special values + rounding/precision control** — NaN/Inf/denormal, RC/PC (§4).
6. **Interrupt boundaries** — MOV SS shadow, STI delay, TF interactions (§10.2).
7. **8259 spurious IRQ + EOI ordering, 8254 read-back/latch, VGA AC flip-flop** (§9).
8. **Paging fault error codes + A/D bits + TLB staleness** (§7.1).
9. **A20 wrap + unreal mode** (§10.1, §6.4).
10. **486 self-modifying-code cache coherence + #AC alignment** (§8.2, §8.3).
11. **Timing constellations** (separate measurement track, §11).

MS-DOS all-modes coverage leads every milestone; Linux/Win32 oracle follows for the
`UNIVERSAL` subset only.

### 14.1 Priority → Milestone → Oracle mapping

For each priority item above, this table pins the **milestone** (from the
implementation-plan) and the **authoritative oracle source** — resolving
prep-phase §B (oracle provenance).  The golden-vector bootstrap is front-loaded
as a Phase-1.5 prerequisite (see implementation-plan) so that items 1 and 4–5
have authoritative data *before* their test modules are written.

| # | Priority item | Milestone | Oracle source | Notes |
|---|---------------|----------|---------------|-------|
| 1 | Flag semantics (undefined-but-deterministic) | M1/Phase 2 | **golden** (real-486 capture) | Host CPU is *wrong* for undefined flags (AGENTS §4.4). Must pin from period-correct silicon. |
| 2 | Division faults (#DE, return-address) | M1/Phase 2 | **manual** (Intel SDM) + golden for return-addr quirk | #DE conditions are architecturally defined; the 8086-vs-286 CS:IP is a golden pin. |
| 3 | String ops + REP + DF | M1/Phase 2 | **manual** + **diff** (host oracle) | Defined behavior — host CPU is reliable here. |
| 4 | PM descriptor loading | M2/Phase 4 | **golden** + **xsuite** (SST386PM) | Descriptor checks are fiddly; SST386PM vectors (from 86Box) are a *convenience* oracle, not ground truth. |
| 5 | FPU special values + RC/PC | M2/Phase 3 | **golden** (real-387/486) | NaN/Inf/denormal handling varies across FPU gens; must pin from real silicon. |
| 6 | Interrupt boundaries (MOV SS/STI/TF) | M3/Phase 8 | **manual** + golden | Architecturally defined; TF-precision is golden. |
| 7 | PIC spurious IRQ / PIT read-back / VGA flip-flop | M4/Phase 7 | **golden** (real-HW or 86Box) | Stateful device behavior — no architectural manual covers every corner. |
| 8 | Paging error codes + A/D + TLB staleness | M3/Phase 5 | **xsuite** (SST386PM) + **manual** | SST386PM generated from 86Box — convenience oracle. |
| 9 | A20 wrap + unreal mode | M3/Phase 8 | **golden** | No manual; observed-behavior only. |
| 10 | 486 SMC cache coherence + #AC | M4/Phase 6 | **golden** + **diff** | SMC result is golden; #AC is manual+golden. |
| 11 | Timing constellations | M7/Phase 9 | **golden band** (per-target reference) | Never hard-fail; deviation reporting only. |

> **Oracle trust hierarchy:** manual (Intel SDM) > golden (real silicon) >
> xsuite (SST386PM, from 86Box — convenience, not ground truth) > diff
> (modern host CPU — reliable for *defined* behavior only).  Where two
> sources disagree, real silicon wins; document the divergence.
>
> **Circular-provenance warning:** SST386PM vectors are generated from 86Box.
> If 86Box is *also* one of the emulators we validate ao486 against, using
> its vectors as the oracle is circular.  Treat SST386PM as a *convenience*
> oracle; the tie-breaker is real silicon or a second independent emulator.

---

## 15. ao486-Specific Risk Weighting

Where a clean-room 486 RTL core most plausibly diverges, and why the G-suite catches it —
the reason the priorities above skew as they do.

| Risk area | Why ao486 is likely to diverge | Our catch |
|-----------|-------------------------------|-----------|
| Undefined-but-deterministic flags | RTL author implements only "defined" flags | golden-vector flag asserts (§3.1,§4) |
| Shift-count masking 8086↔286 | easy to hardcode one rule | count-class sweep (§3.1) |
| PM descriptor check matrix | huge, easy to miss a check | full null/present/type/DPL/limit matrix (§6.1) |
| #PF / exception error codes | encoding is fiddly | decode-pushed-code tests (§7.1,§10.2) |
| Expand-down / big-real limits | inverted logic, extender tricks | limit + unreal tests (§6) |
| FPU rounding/precision + specials + save-image | vast IEEE surface, format-by-mode | RC/PC + special + FSAVE round-trip (§4) |
| Interrupt boundary (MOV SS/STI) | subtle 1-insn shadow | boundary tests (§10.2) |
| Integrated peripheral **state machines** | reimplemented from scratch, thinly specified | stateful device tests (§9) — strongest edge |
| SMC cache coherence | i/d coherence is a known FPGA-core pitfall | SMC functional test (§8.2) |
| BT/BTS/BTR/BTC large bit offset | memory form with bit offset ≥ operand size crosses into adjacent bytes — easy to skip in RTL | bit-offset address crossing test — **currently untested** (DOSBox-X `core=normal` limitation; see §7 note and [specs/80386/new.md](specs/80386/new.md#known-gap) Known Gap) |
| A20 / mode transitions | glue logic, easy to get wrong | wrap + transition tests (§10) |

**Bottom line:** the guest suite's comparative advantage for ao486 is (a) the flag/PM/
paging/FPU *behavioral corners* and (b) the *peripheral + integration* layer that neither
SingleStepTests (CPU-only) nor the HDL testbenches (pin-level, rarely full system) cover
well. The matrix is weighted accordingly.

---

## 16. Explicitly Out of This Matrix (venue-routed)

Listed only so the boundary is visible; **not** implemented as guest tests. See
[test-venues.md](test-venues.md) for placement rules.

| Item | Venue | Owner | Why not guest |
|------|-------|-------|---------------|
| Per-instruction cycle counts | →C | SingleStepTests co-sim | guest timing polluted by prefetch/refresh/IRQ |
| Prefetch depth, cache fill/LRU, internal datapath | →C | ao486 co-sim | internal, not software-visible |
| Bus/pin protocol, wait states, arbitration timing | →T | ao486 HDL testbenches | electrical |
| Exhaustive 2^n operand sweeps | →C | co-sim vectors | combinatorially impossible from a program |
| Simultaneous-exception priority (precise) | →C | co-sim | can't force two faults on one instruction from SW |
| Post-triple-fault / reset / power-on state | →C/→T | co-sim / bench | guest is dead / no SW has run |
| FPU internal guard/round/sticky, 68-bit datapath | →C | co-sim | only rounded result surfaces |
| BT/BTS/BTR/BTC large bit offset (≥32) on memory | G⁺→C | this suite (86Box/real HW) | architecturally guest-testable but DOSBox-X `core=normal` does not implement the cross-dword address adjustment; **must re-test on 86Box or real HW** — see [§7](#7-cpu--80386-pri-1-32-bit--paging--v86) and [specs/80386/new.md](specs/80386/new.md#known-gap) |
