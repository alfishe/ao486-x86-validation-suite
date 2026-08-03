# External Test Suite Integration Analysis

Analysis of what we can bring from test386.asm and SingleStepTests_80386_protected,
and how to extend our test suite based on their approaches.

---

## 1. Source Overview

### 1.1 test386.asm (barotto)
- **URL:** https://github.com/barotto/test386.asm
- **What it is:** A bare-metal x86 diagnostic that runs as a BIOS replacement
- **Coverage:** 80386 real + protected mode, paging, ring transitions, V86, TSS
- **Build:** NASM to raw binary ROM image
- **Output:** POST codes + serial/parallel text
- **Unique value:** Documents **undocumented CPU behaviors** with precise i386 results

### 1.2 SingleStepTests_80386_protected (nand2mario)
- **URL:** https://github.com/nand2mario/SingleStepTests_80386_protected
- **What it is:** 122 JSON test vector files for 386 protected-mode operations
- **Coverage:** Gates, privilege transitions, paging, IOPL, V86, segment loads
- **Generated from:** 86Box (reference emulator)
- **Format:** Full CPU state (regs + segment caches + descriptor tables + RAM) → instruction → final state delta
- **Unique value:** Pre-built vectors for **call gates, cross-privilege, paging faults, V86 IOPL**

> **⚠ CIRCULAR-PROVENANCE WARNING (prep-phase §B):**
> SST386PM vectors are generated from **86Box**. If 86Box is *also* one of the
> emulators we validate ao486 against, using its vectors as the oracle is
> **circular** — we'd be testing "does ao486 match 86Box?" not "is ao486
> correct?".
>
> **Mitigation:**
> 1. Treat SST386PM as a **convenience oracle** (`ORACLE: xsuite`), not
>    ground truth.  Tests using it should report divergence but **not
>    hard-fail** until corroborated.
> 2. The tie-breaker is **real silicon** (golden vectors) or a **second
>    independent emulator** (e.g. QEMU/Bochs).
> 3. See coverage-matrix §14.1 for the full oracle-trust hierarchy.

---

## 2. test386.asm — What to Bring

### 2.1 Test Structure (Adoptable Patterns)

**Macro-driven test definition:**
```nasm
; Their pattern: defOp macro generates test + metadata in one declaration
%macro defOp 6
    db  %%end-%%beg, %6, size   ; length, type, operand-size
%%name: db %1,' ',0             ; name string
%%beg:
    %2  %3, %4                  ; the actual instruction
    ret
%%end:
%endmacro

defOp "ADD al,dl", add, al, dl, none, TYPE_ARITH
defOp "ADD ax,dx", add, ax, dx, none, TYPE_ARITH
defOp "ADC al,dl", adc, al, dl, none, TYPE_ARITH
```

**Our adaptation:** adopt this table-driven approach for the arith/logic modules —
a macro emits both the test code and metadata (name, operand size, type) in one
declaration, making coverage auditing trivial.

**Reference output format (POST 0xEE):**
```
; opcode | mnemonic | size | reg-before | reg-after | flags
03       | ADD      |    8 | 00 00      | 00 00     | PZ
03       | ADD      |    8 | 01 01      | 02 00     | P
03       | ADD      |    8 | 7F 01      | 80 00     | SO
03       | ADD      |    8 | FF 01      | 00 00     | CPAZO
```
This format is excellent for **diff-based regression** — we should emit similar
machine-comparable output for our UNIVERSAL tests.

### 2.2 Undocumented Behavior Documentation

test386.asm documents these with actual observed values (from real i386):

| Behavior | Details |
|----------|---------|
| PUSH with 16-bit selector in 32-bit | SP-=4, but only low 16 bits written, high 16 undefined |
| POPAD ESP handling | Loaded ESP ignored, SP = SP + 32 |
| SHL/SHR OF flag for count > 1 | OF undefined, but i386 produces specific patterns |
| AAA/AAS/DAA/DAS flags | Undefined but deterministic flag patterns |
| PUSH SP (8086 vs 286+) | 8086 pushes decremented, 286+ pushes original |

**Our action:** import these as golden-vector tests tagged `ORACLE: golden-test386`.

### 2.3 Test Modules to Import/Adapt

| test386 file | Coverage | Our action |
|--------------|----------|------------|
| `arith-logic_d.asm` | ADD/ADC/SUB/SBB/CMP/AND/OR/XOR/TEST/NEG/NOT/INC/DEC with flag reference | **Import** macro structure + reference values |
| `shift_m.asm` | SHL/SHR/SAR/ROL/ROR/RCL/RCR with OF undefined behavior | **Import** shift-by-1 vs by-N OF patterns |
| `bcd_m.asm` | AAA/AAS/AAM/AAD/DAA/DAS flag behavior | **Import** — we lack this detail |
| `bit_m.asm` | BT/BTS/BTR/BTC/BSF/BSR | **Import** BSF/BSR src=0 undefined dest |
| `enter_m.asm` / `leave_m.asm` | ENTER nesting, LEAVE | **Import** — stack frame edge cases |
| `paging_m.asm` / `paging_p.asm` | PDE/PTE flag tests, TLB, A/D bits | **Adapt** — translate to our paging test |
| `ver_p.asm` | VERR/VERW | **Import** — complete descriptor checks |
| `protected_rings_p.asm` | Ring 0↔3 transitions | **Adapt** — merge with our privilege tests |
| `protected_tss*.asm` | TSS task switch | **Import** — we have a gap here |

### 2.4 Build System Insight

test386 builds as a raw BIOS ROM (64K or 128K). We don't need this for ao486 (we
boot DOS), but the **configuration.asm** pattern is useful: all port addresses and
output destinations are #defines at the top, making the same source build for
different targets. Adopt for our multi-target shim.

---

## 3. SingleStepTests_80386_protected — What to Bring

### 3.1 Test Vector Format

Each JSON file is an array of test cases:
```json
{
  "name": "CALL_GATE_gate_cross_1 CALL FAR 0x0030:0x00000000",
  "category": "call_gate",
  "description": "Call gate, cross privilege (ring 3 -> ring 0, stack switch)",
  "bytes": [154, 0, 0, 0, 0, 48, 0],
  "initial": {
    "regs": {"eax": ..., "ecx": ..., "edx": ..., "ebx": ..., "esp": ..., "ebp": ..., "esi": ..., "edi": ..., "eip": ..., "eflags": ...},
    "segs": {
      "cs": {"sel": 27, "base": 0, "limit": 1048575, "flags": 49120},
      "ds": {...}, "es": {...}, "ss": {...}, "fs": {...}, "gs": {...}
    },
    "cr0": 1,
    "cr3": 5242880,
    "dtables": {
      "gdt": {"base": 65536, "limit": 255},
      "idt": {"base": 8192, "limit": 2047},
      "ldt": {...}
    },
    "tr": {"sel": 40, "base": 16384, "limit": 103, "flags": 37152},
    "ram": [[addr, byte], [addr, byte], ...]
  },
  "final": {
    "regs": {"esp": 2097136, "eip": 4194304},
    "segs": {"cs": {...}, "ss": {...}},
    "ram": [[addr, byte], ...]
  }
}
```

**Key fields:**
- `bytes`: raw instruction encoding
- `initial.segs.*.flags`: full segment descriptor flags (access + type + DPL + P + G + D/B)
- `initial.ram`: pre-set memory including GDT, IDT, TSS, page tables as `[address, byte]` pairs
- `final`: only changed state (delta) — unchanged regs/segs omitted

### 3.2 Coverage Analysis (122 files, ~1000+ vectors)

| Category | Files | What they test |
|----------|-------|----------------|
| **Call gates** | CALL_GATE, CALL_GATE_M, CALL_PRIV | Same-priv, cross-priv, parameter copy, stack switch |
| **Jump gates** | JMP_GATE, JMP_GATE_M, JMP_PRIV | Gate jumps without stack switch |
| **Far call/ret** | CALL_FAR, CALL_FAR_M, RETF, RETF_IMM, JMP_FAR, JMP_FAR_M | Segment transitions |
| **Interrupts** | INT_SAMEP, INT_CROSSP, INT_CONFORM, INT_GATEDPL, INT_LESSPRIV, IRETD | All int/iret privilege combinations |
| **Segment loads** | MOV_DS/ES/FS/GS/SS, LDS/LES/LFS/LGS/LSS, POP_DS/ES/FS/GS/SS | Descriptor loading, null selectors |
| **Privileged ops** | CLTS_R3, HLT_R3, LGDT_R3, LIDT_R3, LTR_R3, MOV_CR0_R3 | #GP from ring 3 |
| **IOPL-sensitive** | CLI_IOPL, STI_IOPL, PUSHF_IOPL, POPF_IOPL, IN/OUT variants | IOPL checks |
| **Paging** | MOV_*_PG, PTE_WB_*, MOV_*_PF_US, MOV_*_PF_WP | Page faults, U/S, W/R, A/D writeback |
| **V86 mode** | V86_CLI/STI/HLT/INT/PUSHF/POPF_IOPL* | V86 IOPL-sensitive behavior |
| **Segment limits** | MOV_*_SEGLIM, PUSH_SEGLIM, MOVSB_SEGLIM | Limit violations → #GP/#SS |
| **Descriptor ops** | LAR, LSL, VERR, VERW, ARPL | Descriptor queries |

### 3.3 Gaps Identified (what they DON'T cover)

| Missing | Notes |
|---------|-------|
| TSS task switch | No CALL/JMP to TSS selector; test386 has this |
| LDT switching | No LLDT or LDT-relative segment loads |
| #DF double fault | No contributory exception chains |
| Conforming code full matrix | Limited conforming-segment tests |
| Exception error codes | Error codes not verified in final state |
| Debug registers | No DR0-7 tests |
| 486-specific | No BSWAP, XADD, CMPXCHG, INVLPG, CPUID, #AC |

### 3.4 Importability to Guest-Side (RING0 tests)

The vectors specify complete state including GDT/IDT/TSS/page tables in RAM.
To use them guest-side:

1. **Partial import:** extract the *expected outcomes* (final register + flag values)
   as golden assertions; we set up our own descriptor tables.
   
2. **Full replay (complex):** reconstruct the exact memory layout and execute.
   Challenges:
   - RAM addresses are absolute; must match our memory map or relocate
   - GDT/IDT entries are byte-serialized; must parse and rebuild
   - Page tables are sparse byte arrays; must assemble
   
3. **Recommended approach:**
   - Import the *test scenarios* (privilege levels, gate types, selector values)
   - Generate our own descriptor tables matching the scenario
   - Use their final-state as the oracle
   - Tag these tests `ORACLE: xsuite-sst386pm`

### 3.5 Importer Tool Spec

`tools/import_singlestep_pm.py`:
```
Input:  SingleStepTests_80386_protected/v1/*.json
Output: tests/sst386pm/<category>.inc  (NASM include with test data)
        tests/sst386pm/<category>.json (machine-readable for oracle)

For each test case:
  - Extract: name, description, instruction bytes, initial CPL/DPL/RPL, expected EIP/ESP/FLAGS
  - Categorize: gate, segment, paging, iopl, v86, privileged
  - Generate: NASM data block with expected values
  - Skip: tests requiring memory layouts we can't reconstruct
```

---

## 4. Synthesis — How These Extend Our Coverage Matrix

### 4.1 New Test Areas Enabled

| Area | Source | Our coverage-matrix section | Action |
|------|--------|----------------------------|--------|
| Call gates (same-priv, cross-priv, param copy) | SST386PM | §6.3 | **Add** comprehensive gate tests |
| Task switch via TSS | test386 | §6 (gap) | **Add** TSS section |
| V86 IOPL behavior | SST386PM | §7 | **Extend** with all IOPL combos |
| Paging A/D writeback | SST386PM | §7.1 | **Extend** with writeback verification |
| #PF U/S and W/P combinations | SST386PM | §7.1 | **Complete** the error-code matrix |
| Segment limit violations | SST386PM | §6.2 | **Add** explicit limit tests |
| BCD flags (undocumented) | test386 | §3.2 | **Add** golden AAA/AAS/DAA/DAS |
| Shift OF undefined | test386 | §3.1 | **Extend** with multi-bit shift OF |
| BSF/BSR src=0 | test386 | §3.1 | **Add** undefined-dest test |
| VERR/VERW full | test386 | §6.1 | **Add** complete verification |

### 4.2 Updated Priority List

Insert after existing coverage-matrix §14 priorities:

| Pri | New item | Source |
|-----|----------|--------|
| 1.5 | Call/jump gates (same/cross privilege, parameter copy) | SST386PM |
| 2.5 | TSS task switch | test386 |
| 3.5 | V86 IOPL-sensitive ops | SST386PM |
| 4 | BCD flag golden vectors | test386 |
| 4 | Shift OF multi-bit golden | test386 |

### 4.3 Test Module Additions

```
src/cpu/80386/
  gates.asm         <- NEW: call/jump gates from SST386PM
  tss.asm           <- NEW: task switch from test386
  
src/cpu/8086/
  bcd.asm           <- EXTEND: import test386 BCD flag goldens
  shift.asm         <- EXTEND: import multi-bit OF patterns
```

---

## 5. Concrete Integration Plan

### Phase 1: Import Reference Data (no code yet)

1. Clone both repos locally:
   ```bash
   git clone https://github.com/barotto/test386.asm external/test386
   git clone https://github.com/nand2mario/SingleStepTests_80386_protected external/sst386pm
   ```

2. Run importer to extract:
   ```bash
   python3 tools/import_test386_arith.py external/test386/src/tests/ tests/test386/
   python3 tools/import_singlestep_pm.py external/sst386pm/v1/ tests/sst386pm/
   ```

3. Generated files:
   - `tests/test386/arith_golden.json` — ADD/SUB/etc flag expectations
   - `tests/test386/bcd_golden.json` — AAA/AAS/etc undocumented flags
   - `tests/test386/shift_golden.json` — OF patterns
   - `tests/sst386pm/gates.json` — call/jump gate expected outcomes
   - `tests/sst386pm/paging.json` — PF error codes and A/D bits
   - `tests/sst386pm/v86.json` — V86 IOPL behavior

### Phase 2: Implement Test Modules

1. **8086 arith/bcd/shift:** load golden JSON, iterate cases, compare
2. **80386 gates:** set up minimal GDT/IDT, execute gate calls, verify
3. **80386 paging:** already in our matrix, extend with SST386PM error codes
4. **80386 v86:** set up V86 mode, test IOPL-sensitive ops
5. **TSS:** implement task switch tests from test386 patterns

### Phase 3: Oracle Cross-Check

1. Run our tests on 86Box (the SST386PM reference) — should match vectors
2. Run on ao486 — report discrepancies
3. Run on real hardware — validate both sources

---

## 6. Licensing

| Project | License | Our use |
|---------|---------|---------|
| test386.asm | GPL-3.0 | Import as reference/inspiration; for direct code, GPL-3.0 applies |
| SingleStepTests_80386_protected | MIT | Freely import vectors |

**Recommendation:** keep our project MIT; import test386 *patterns and data* (not
verbatim code), import SST386PM vectors directly (MIT-compatible).

---

## 7. References to Add to references.md

```markdown
### External Test Suites (Direct Integration)

| Project | URL | Integration |
|---------|-----|-------------|
| test386.asm | https://github.com/barotto/test386.asm | Arith/BCD/shift flag goldens, TSS patterns |
| SingleStepTests_80386_protected | https://github.com/nand2mario/SingleStepTests_80386_protected | PM gate/paging/V86 vectors |
```
