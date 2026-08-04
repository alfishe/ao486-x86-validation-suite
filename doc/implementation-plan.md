# Implementation Plan

Master checklist for implementing the x86 Validation Suite.

**Legend:**
- **Phase**: recommended order (0=foundation → 10=polish)
- **Type**: `INFRA` infrastructure/tooling, `TEST` test implementation
- **Pri**: 1=critical path, 2=important, 3=nice-to-have
- **Status**: ` ` pending, `~` in progress, `✓` done, `—` skipped

> **SEQUENCING RULE (prep-phase A3):** Within each Phase, implement tasks in
> [coverage-matrix.md](coverage-matrix.md) §14 priority order (max bug-yield
> first), NOT in table order.  The table groups by area for readability; the
> §14 list is the *actual* recommended order.  For example, in Phase 2,
> flag-semantics and division-fault tests (§14 items 1–2) must land before
> the Pri-2/3 control/stack/segment/misc cleanup.
>
> **ORACLE ANNOTATIONS (prep-phase §B):** Each TEST row should carry an
> `ORACLE:` tag in its Purpose column matching the source hierarchy in
> coverage-matrix §14.1.  The authoritative oracle per priority is pinned
> there to resolve provenance before implementation.
>
> **DETAILED SPECS (prep-phase D2):** Every `Area` in the table below has a
> corresponding detailed spec file in [doc/specs/](specs/index.md). The spec
> provides exact input/expected-output tables, flag-seed classes, state
> save/restore contracts, known divergences, and pass/fail criteria. **Consult
> the spec before implementing any test.** See [specs/index.md](specs/index.md)
> for the full enumeration (59 files across 8 phases).

---

| Ph | Type | Area | Pri | Task | Tests / Purpose | Status |
|:--:|:----:|------|:---:|------|-----------------|:------:|
| 0 | INFRA | Setup | 1 | Initialize git repository | — | |
| 0 | INFRA | Setup | 1 | Create `.gitignore` | — | |
| 0 | INFRA | Setup | 2 | Verify directory structure matches Makefile | — | |
| 0 | INFRA | Setup | 2 | Add GitHub Actions CI for build verification | — | |
| 0 | INFRA | Build | 1 | Install NASM 2.14+ on dev host | — | |
| 0 | INFRA | Build | 1 | Install OpenWatcom wlink (or jwlink) | — | |
| 0 | INFRA | Build | 1 | Verify `make dirs` creates directories | — | |
| 0 | INFRA | Build | 1 | Create minimal `src/main.asm` stub | — | |
| 0 | INFRA | Build | 1 | Verify `nasm -f obj` produces .obj | — | |
| 0 | INFRA | Build | 1 | Verify far-pointer OMF encoding | `dd` fields in MODULE_HEADER must encode as seg:off pair, not flat offset (prep-phase E2 decision). Test: dump .obj, confirm 4-byte far ptr layout. Check wlink resolves symbol+segment correctly. | |
| 0 | INFRA | Build | 2 | Document wlink command in Makefile | — | |
| 0 | INFRA | Build | 1 | Test full DOS build → X86VAL.EXE | — | |
| 0 | INFRA | Shim | 1 | Create `src/arch/dos/startup.asm` | MZ entry point, PSP parsing, INT 21h exit | |
| 0 | INFRA | Shim | 1 | Create `src/arch/dos/output.asm` | Console via INT 21h/09, serial via ports, file output | |
| 0 | INFRA | Shim | 2 | Create `src/arch/linux/startup.asm` | ELF entry, syscall exit — for oracle builds | |
| 0 | INFRA | Shim | 2 | Create `src/arch/linux/output.asm` | write(1,...) syscall — for oracle builds | |
| 0 | INFRA | Shim | 3 | Create `src/arch/win32/startup.asm` | PE entry, ExitProcess — for oracle builds | |
| 0 | INFRA | Shim | 3 | Create `src/arch/win32/output.asm` | WriteFile — for oracle builds | |
| 0 | INFRA | Shim | 1 | Verify `make dos` produces working EXE | — | |
| 0 | INFRA | Shim | 2 | Verify `make linux` produces working ELF | — | |
| 0 | INFRA | Shim | 3 | Verify `make win32` produces working PE | — | |
| 0 | INFRA | Shim | 1 | Test DOS build in DOSBox-X | Boots, prints banner, exits cleanly | |
| 0 | INFRA | Import | 1 | Clone test386.asm to `external/test386/` | Source for arith/BCD/shift golden values, TSS patterns | |
| 0 | INFRA | Import | 1 | Clone SST_80386_protected to `external/sst386pm/` | Source for PM gate/paging/V86 vectors | |
| 0 | INFRA | Import | 2 | Create `tools/import_test386_arith.py` | Extracts flag golden values from test386 reference output | |
| 0 | INFRA | Import | 2 | Create `tools/import_singlestep_pm.py` | Converts SST JSON to our test data format | |
| 0 | INFRA | Import | 3 | Document import process in tools/README.md | — | |
| 1 | INFRA | Core | 1 | Implement `detect_cpu` | Returns CPU_8086/186/286/386/486 for test gating | |
| 1 | INFRA | Core | 1 | Implement FLAGS bit 12-15 test | Distinguishes 8086 (bits set) from 286+ (bits clear) | |
| 1 | INFRA | Core | 1 | Implement EFLAGS.AC toggle | Distinguishes 386 (no AC) from 486 (AC toggles) | |
| 1 | INFRA | Core | 2 | Implement CPUID presence check | EFLAGS.ID toggle → CPUID available (late 486+) | |
| 1 | INFRA | Core | 1 | Implement `detect_fpu` | Returns FPU_NONE/8087/287/387/486 for FPU test gating | |
| 1 | INFRA | Core | 1 | Store in `g_cpu_type`, `g_fpu_type` | Global state for all modules to query | |
| 1 | TEST | Core | 1 | Test detection on DOSBox-X 8086/286/386/486 | **Verify:** detection matches configured CPU | |
| 1 | INFRA | Runner | 1 | Define MODULE_HEADER structure | Magic, version, init/run/cleanup, test table pointer | |
| 1 | INFRA | Runner | 1 | Implement `runner_init` | Parse command line, populate config struct | |
| 1 | INFRA | Runner | 1 | Implement dynamic module loading | Overlay/dynamic load for constrained < 256KB memory | |
| 1 | INFRA | Runner | 1 | Implement `runner_load_module` | Call module init, check return | |
| 1 | INFRA | Runner | 1 | Implement CPU-Scoped Router | Group execution by detected HW scope (8086, 286, etc) | |
| 1 | INFRA | Runner | 1 | Implement Wave-based Fail-Fast Logic | Parse flags, halt scope execution if lower Wave fails | |
| 1 | INFRA | Runner | 1 | Implement `runner_exec_tests` | Iterate test table, call each, record pass/fail/skip | |
| 1 | INFRA | Runner | 1 | Implement SKIP logic | Check g_cpu_type >= module's GEN requirement | |
| 1 | INFRA | Runner | 1 | Implement pass/fail/skip counters | Aggregate results for summary | |
| 1 | INFRA | Runner | 2 | Implement timeout watchdog | PIT-based, prevents infinite loops | |
| 1 | TEST | Runner | 1 | Test with dummy module | **3 tests:** always-pass, always-fail, always-skip | |
| 1 | INFRA | Output | 1 | Implement `output_init` | Parse /log:X, open file/serial handles | |
| 1 | INFRA | Output | 1 | Implement output primitives | `output_char`, `output_string`, `output_hex`, `output_decimal` | |
| 1 | INFRA | Output | 1 | Implement multi-target output | CON + COM1 simultaneously | |
| 1 | INFRA | Output | 2 | Implement verbosity levels | 0=summary, 1=normal, 2=detailed, 3=debug | |
| 1 | INFRA | Output | 2 | Implement JSON output mode | /format:json for machine parsing | |
| 1 | TEST | Output | 1 | Test output in DOSBox-X | **Verify:** console and serial both receive output | |
| 1 | INFRA | Config | 1 | Parse `/cpu:XXXX` filter | Run only tests for specified CPU generation | |
| 1 | INFRA | Config | 1 | Parse `/module:name` filter | Run only named module | |
| 1 | INFRA | Config | 2 | Parse `/verbose:N`, `/format:X` | Output control | |
| 1 | INFRA | Config | 2 | Parse `/log:target[,target]` | Output destination(s) | |
| 1 | INFRA | Timing | 2 | Implement PIT channel 2 timing | One-shot mode for microsecond measurement | |
| 1 | INFRA | Timing | 2 | Implement timing API | `timing_start`, `timing_stop`, `timing_read_us` | |
| 1 | INFRA | Timing | 3 | Implement TSC read | 486+ with CPUID check, for finer timing | |
| 1 | INFRA | Memory | 2 | Implement memory utilities | `mem_zero`, `mem_copy`, `mem_compare` | |
| 1 | INFRA | State | 1 | Implement SAVE_STATE / RESTORE_STATE macros | Save/restore all GPRs, FLAGS, DF, segment regs (DS/ES/SS). Required by AGENTS §6.3 for all test modules. Place in `src/core/state.asm`; expose via `include/test.inc`. Must be re-entrant (uses stack, not fixed globals). | |
| 1 | INFRA | State | 1 | Implement FPU save/restore wrapper | `fpu_save` / `fpu_restore`: 108-byte buffer for FSAVE/FRSTOR. Called by SAVE_STATE when FPU detected. Restore CW exactly. | |
| 1 | INFRA | State | 2 | Document state-save contract | Which registers + flags are saved/restored by default; how to extend for peripheral-specific save (PIC/PIT/VGA use their own `*_save`/`*_restore`) | |
| 1.5 | INFRA | Oracle | 1 | **Golden-vector bootstrap (PREREQUISITE)** | Capture undefined-but-deterministic flag values from period-correct real silicon BEFORE Phase 2 golden-flag tests. See §B below. | |
| 1.5 | INFRA | Oracle | 1 | Capture MUL/IMUL undefined flags (SF/ZF/AF/PF) | Pin from real 486 (or designated golden source). ORACLE: golden | |
| 1.5 | INFRA | Oracle | 1 | Capture multi-bit shift/rotate OF golden | Pin OF for count>1 per width. ORACLE: golden | |
| 1.5 | INFRA | Oracle | 1 | Capture BCD-adjust undefined flags | DAA/DAS/AAA/AAS flag patterns. ORACLE: golden | |
| 1.5 | INFRA | Oracle | 1 | Capture logic-op AF golden | AND/OR/XOR/TEST undefined AF value. ORACLE: golden | |
| 1.5 | INFRA | Oracle | 2 | Designate golden source if no real-HW | If real 486 unavailable: document which emulator-of-record (86Box) is provisional golden, tag `ORACLE: provisional-golden` | |
| 2 | INFRA | Import | 1 | Run import_test386 → arith_golden.json | ADD/SUB/etc with expected result + flags | |
| 2 | INFRA | Import | 1 | Run import_test386 → bcd_golden.json | AAA/AAS/AAM/AAD/DAA/DAS flag patterns | |
| 2 | INFRA | Import | 1 | Run import_test386 → shift_golden.json | SHL/SHR/SAR/ROL/ROR multi-bit OF values | |
| 2 | TEST | Import | 1 | Verify JSON integrity | **~500+ cases** parse correctly | |
| 2 | TEST | 8086-Smoke | 1 | Basic CPU state & NOP/HLT | **Purpose:** Wave 0 minimum viability execution | |
| 2 | TEST | 8086-Arith | 1 | ADD r8,r8 / r16,r16 / r8,m8 / r8,imm8 | **Purpose:** verify result + all 6 arithmetic flags (CF,PF,AF,ZF,SF,OF) | |
| 2 | TEST | 8086-Arith | 1 | ADC with CF=0 and CF=1 pre-seed | **Purpose:** verify carry-in affects result and flags | |
| 2 | TEST | 8086-Arith | 1 | SUB/SBB/CMP full flag matrix | **Purpose:** verify borrow semantics, CMP sets flags only | |
| 2 | TEST | 8086-Arith | 1 | NEG with CF rule | **Purpose:** CF=(operand!=0), catches NEG 0 edge case | |
| 2 | TEST | 8086-Arith | 1 | INC/DEC CF-preservation | **Purpose:** CF must NOT change (critical for multi-precision) | |
| 2 | TEST | 8086-Arith | 1 | MUL/IMUL undefined flags | **Purpose:** pin SF/ZF/AF/PF to golden values (varies by CPU) | |
| 2 | TEST | 8086-Arith | 1 | DIV/IDIV including #DE | **Purpose:** verify fault on div-by-0 and quotient overflow | |
| 2 | TEST | 8086-Arith | 1 | DIV #DE return address | **Purpose:** 8086 pushes next-insn, 286+ pushes DIV addr | |
| 2 | TEST | 8086-Logic | 1 | AND/OR/XOR/TEST/NOT | **Purpose:** verify CF=OF=0, result correct, PF/ZF/SF set | |
| 2 | TEST | 8086-Logic | 1 | AF undefined values | **Purpose:** pin AF to golden (undefined but deterministic) | |
| 2 | TEST | 8086-Shift | 1 | SHL/SHR/SAR count classes | **Counts:** {0,1,7,8,15,16,17,31,32,255} to hit all boundaries | |
| 2 | TEST | 8086-Shift | 1 | count=0 no-op | **Purpose:** ALL flags unchanged (critical, often wrong in emulators) | |
| 2 | TEST | 8086-Shift | 1 | OF defined only for count=1 | **Purpose:** OF undefined for count>1, pin to golden | |
| 2 | TEST | 8086-Shift | 1 | Multi-bit OF golden | **Purpose:** import test386 patterns for undefined OF | |
| 2 | TEST | 8086-Shift | 1 | ROL/ROR/RCL/RCR CF threading | **Purpose:** verify CF rotates through operand correctly | |
| 2 | TEST | 8086-Shift | 1 | 8086-vs-286 count masking | **Purpose:** 8086 no mask, 286+ masks &0x1F (generation-gated) | |
| 2 | TEST | 8086-BCD | 2 | AAA/AAS with AF/CF | **Purpose:** verify BCD adjust sets AF/CF correctly | |
| 2 | TEST | 8086-BCD | 2 | AAM/AAD non-10 immediate | **Purpose:** undocumented D4/D5 imm8 (base != 10) | |
| 2 | TEST | 8086-BCD | 2 | DAA/DAS | **Purpose:** verify packed BCD adjust | |
| 2 | TEST | 8086-BCD | 2 | BCD undefined flags golden | **Purpose:** pin SF/ZF/PF/OF to test386 values | |
| 2 | TEST | 8086-String | 1 | MOVS/STOS/LODS/CMPS/SCAS | **Purpose:** verify string ops move/compare data correctly | |
| 2 | TEST | 8086-String | 1 | REP with CX=0, 1, N | **Purpose:** CX=0 does nothing, CX=1 executes once | |
| 2 | TEST | 8086-String | 1 | REPZ/REPNZ early termination | **Purpose:** verify ZF condition stops loop | |
| 2 | TEST | 8086-String | 1 | DF=0 and DF=1 | **Purpose:** verify direction affects SI/DI increment | |
| 2 | TEST | 8086-String | 1 | Segment override | **Purpose:** DS: override on ES:-default ops | |
| 2 | TEST | 8086-Ctrl | 2 | All 16 Jcc conditions | **Purpose:** verify each condition code branch logic | |
| 2 | TEST | 8086-Ctrl | 2 | Near/short displacement | **Purpose:** verify sign-extension and IP-relative | |
| 2 | TEST | 8086-Ctrl | 2 | JMP/CALL/RET near and far | **Purpose:** verify stack push/pop and segment load | |
| 2 | TEST | 8086-Ctrl | 2 | LOOP/LOOPZ/LOOPNZ/JCXZ | **Purpose:** verify CX decrement and condition | |
| 2 | TEST | 8086-Stack | 2 | PUSH/POP all registers | **Purpose:** verify SP adjustment and data integrity | |
| 2 | TEST | 8086-Stack | 1 | PUSH SP (8086 quirk) | **Purpose:** 8086 pushes decremented SP, 286+ pushes original | |
| 2 | TEST | 8086-Stack | 1 | PUSHF/POPF reserved bits | **Purpose:** bit1=1, bits3/5=0, bits12-15 vary by gen | |
| 2 | TEST | 8086-Seg | 2 | MOV to/from segment regs | **Purpose:** verify segment base recomputation | |
| 2 | TEST | 8086-Seg | 2 | LES/LDS | **Purpose:** verify pointer load updates seg + reg | |
| 2 | TEST | 8086-Misc | 3 | XCHG/XLAT/LEA/CBW/CWD | **Purpose:** verify miscellaneous ops | |
| 2 | TEST | 8086-Misc | 2 | SALC (D6 undocumented) | **Purpose:** AL = (CF ? 0xFF : 0x00) | |
| 2 | TEST | 8086-Enc | 2 | Redundant prefix behavior | **Purpose:** segment override last-one-wins | |
| 2 | TEST | 8086-Enc | 2 | 8086 opcode aliases | **Purpose:** 60-6F=Jcc aliases, 82=80, 0F=POP CS | |
| 2 | TEST | 8086-Enc | 2 | ICEBP/INT1 (F1) | **Purpose:** undocumented single-byte INT1 | |
| 2 | TEST | 8086-Flags | 2 | STC/CLC/CMC/STD/CLD/STI/CLI | **Purpose:** direct flag manipulation; STI 1-insn delay (→ Phase 8). ORACLE: manual | |
| 2 | TEST | 8086-Misc | 3 | HLT wake-on-IRQ / WAIT / ESC | **Purpose:** HLT resumes on interrupt; WAIT polls FPU error. ORACLE: manual | |
| 2 | TEST | 8086-Enc | 2 | LOCK on invalid target | **Purpose:** 8086 ignores; 286+ → #UD (gen-gated). ORACLE: manual | |
| 2 | TEST | 8086-Enc | 2 | Long prefix chain limit | **Purpose:** excessive prefixes → #GP/#UD (386+); 8086 no limit. ORACLE: manual | |
| 2 | TEST | 8086-Seg | 2 | Segment/offset wrap (0xFFFF word) | **Purpose:** real-mode wrap vs 286 #GP. ORACLE: manual | |
| 2 | TEST | 8086-SMC | 3 | 8086 prefetch SMC stale-vs-fresh | **Purpose:** write ahead-of-IP, observe old vs new bytes. ORACLE: golden. Depth →C | |
| 2 | INFRA | Oracle | 1 | Build UNIVERSAL for Linux | — | |
| 2 | INFRA | Oracle | 1 | Export oracle_8086.json | Expected values from trusted host CPU | |
| 2 | TEST | Oracle | 1 | Compare DOS vs oracle | **Purpose:** DOS results must match Linux oracle | |
| 3 | TEST | FPU-Detect | 1 | FNINIT + FNSTCW/FNSTSW | **Purpose:** detect FPU presence via control word | |
| 3 | TEST | FPU-Detect | 2 | 287 vs 387 infinity test | **Purpose:** projective (287) vs affine (387) infinity | |
| 3 | TEST | FPU-Gen | 1 | CW default per generation | **Purpose:** 8087/287=0x03FF, 387/486=0x037F. Spec: [x87/generations.md](specs/x87/generations.md). `src/fpu/80387/new387.asm` test 1 | ✓ |
| 3 | TEST | FPU-Gen | 1 | IC bit effectiveness | **Purpose:** 8087/287 use IC; 387+ ignore it | |
| 3 | TEST | FPU-Gen | 2 | FSIN/FCOS availability | **Purpose:** #UD on 8087/287, works on 387+. `src/fpu/80387/new387.asm` (capability gate + tests 9–12) | ✓ |
| 3 | TEST | FPU-Gen | 2 | FPREM vs FPREM1 | **Purpose:** FPREM1 is 387+ only (IEEE remainder). `src/fpu/80387/new387.asm` tests 2–4, 13 | ✓ |
| 3 | TEST | FPU-Gen | 2 | FUCOM availability | **Purpose:** FUCOM/FUCOMP/FUCOMPP 387+ only. `src/fpu/80387/new387.asm` tests 5–8, 14 | ✓ |
| 3 | TEST | FPU-Gen | 2 | C1 round-up indicator | **Purpose:** 387+ sets C1 on round-up; undefined on 287 | |
| 3 | TEST | FPU-Gen | 2 | Denormal handling | **Purpose:** 387+ full denormal; 8087/287 may flush | |
| 3 | TEST | FPU-Gen | 2 | FSAVE format differences | **Purpose:** 94-byte (287) vs 108-byte (387+) | |
| 3 | TEST | FPU-Basic | 1 | FLD/FST/FSTP 32/64/80-bit | **Purpose:** verify load/store precision | |
| 3 | TEST | FPU-Basic | 1 | FILD/FIST/FISTP 16/32/64 | **Purpose:** integer ↔ float conversion | |
| 3 | TEST | FPU-Basic | 2 | FBLD/FBSTP BCD | **Purpose:** packed BCD ↔ float | |
| 3 | TEST | FPU-Arith | 1 | FADD/FSUB/FMUL/FDIV/FSQRT | **Purpose:** verify IEEE 754 arithmetic | |
| 3 | TEST | FPU-Arith | 1 | All RC modes | **Purpose:** nearest/down/up/truncate rounding | |
| 3 | TEST | FPU-Arith | 1 | All PC modes | **Purpose:** 24/53/64-bit precision control | |
| 3 | TEST | FPU-Special | 1 | ±0, ±Inf, SNaN, QNaN | **Purpose:** verify special value handling | |
| 3 | TEST | FPU-Special | 1 | NaN propagation | **Purpose:** which operand's NaN survives | |
| 3 | TEST | FPU-Special | 1 | Inf arithmetic | **Purpose:** Inf-Inf→indefinite, Inf/Inf→indefinite | |
| 3 | TEST | FPU-Special | 2 | Denormals | **Purpose:** gradual underflow handling | |
| 3 | TEST | FPU-Compare | 1 | FCOM/FCOMP/FCOMPP | **Purpose:** verify C0/C2/C3 condition codes | |
| 3 | TEST | FPU-Compare | 1 | FTST/FXAM | **Purpose:** test against 0, classify operand | |
| 3 | TEST | FPU-Compare | 1 | FUCOM (387+) | **Purpose:** unordered compare (no #IA on QNaN). `src/fpu/80387/new387.asm` tests 5–8, 14 | ✓ |
| 3 | TEST | FPU-Stack | 1 | Stack overflow → #IS | **Purpose:** push to full stack raises invalid | |
| 3 | TEST | FPU-Stack | 1 | Stack underflow → #IS | **Purpose:** pop empty stack raises invalid | |
| 3 | TEST | FPU-Stack | 1 | FXCH with empty | **Purpose:** exchange with empty register | |
| 3 | TEST | FPU-Stack | 2 | FINCSTP/FDECSTP | **Purpose:** rotate TOP without exception | |
| 3 | TEST | FPU-Ctrl | 1 | FLDCW/FSTCW round-trip | **Purpose:** control word preserved | |
| 3 | TEST | FPU-Ctrl | 1 | Default CW = 0x037F | **Purpose:** FNINIT sets known default. `src/fpu/80387/new387.asm` test 1 | ✓ |
| 3 | TEST | FPU-Ctrl | 2 | FCLEX/FNCLEX | **Purpose:** clear exception flags | |
| 3 | TEST | FPU-Exc | 1 | All 6 exception types | **Purpose:** IE/DE/ZE/OE/UE/PE triggers | |
| 3 | TEST | FPU-Exc | 1 | Masked vs unmasked | **Purpose:** masked = default result, unmasked = #MF | |
| 3 | TEST | FPU-Exc | 1 | Deferred #MF model | **Purpose:** exception on NEXT FPU/WAIT instruction | |
| 3 | TEST | FPU-Save | 1 | FSAVE/FRSTOR round-trip | **Purpose:** full state preserved | |
| 3 | TEST | FPU-Save | 1 | 14/28/94/108-byte formats | **Purpose:** format varies by mode (real/PM) and gen | |
| 3 | TEST | FPU-Trans | 2 | FSIN/FCOS/FPTAN (387+) | **Purpose:** verify trig functions. `src/fpu/80387/new387.asm` tests 9–11, 15 | ✓ |
| 3 | TEST | FPU-Trans | 2 | Out-of-range (C2 flag) | **Purpose:** |arg| >= 2^63 sets C2. `src/fpu/80387/new387.asm` test 12 | ✓ |
| 3 | TEST | FPU-Trans | 2 | F2XM1/FYL2X/FPATAN | **Purpose:** exponential/log/atan | |
| 3 | TEST | FPU-PREM | 2 | FPREM vs FPREM1 | **Purpose:** truncate (8087) vs IEEE round (387). `src/fpu/80387/new387.asm` tests 2–3 | ✓ |
| 3 | TEST | FPU-PREM | 2 | Partial remainder C2 | **Purpose:** C2=1 means incomplete, iterate | |
| 3 | TEST | FPU-Const | 3 | FLD1/FLDZ/FLDPI/FLDL2E exact 80-bit | **Purpose:** pin exact constant bit patterns. ORACLE: golden | |
| 3 | TEST | FPU-Special | 2 | 80-bit pseudo-denormals / un-NaN / un-∞ | **Purpose:** 387 vs 486 unnormals differ; pin behavior. ORACLE: golden | |
| 3 | TEST | FPU-Exc | 1 | FWAIT/IRQ13-vs-#MF delivery config | **Purpose:** ao486=integrated #MF; test delivery path per config (§4.7). ORACLE: manual+golden | |
| 4 | TEST | 186-Stack | 2 | ENTER nesting 0 (simple frame) | **Purpose:** BP/SP update, locals allocation. Spec: [186-stack.md](specs/80186-286/186-stack.md) | |
| 4 | TEST | 186-Stack | 2 | ENTER nesting 1+ (display copy) | **Purpose:** verify display pointer copying for N>0 | |
| 4 | TEST | 186-Stack | 2 | ENTER nesting 31 (max) | **Purpose:** max nesting level, stack usage | |
| 4 | TEST | 186-Stack | 2 | ENTER nesting >31 (mask) | **Purpose:** only low 5 bits used | |
| 4 | TEST | 186-Stack | 2 | LEAVE | **Purpose:** verify frame teardown SP=BP, pop BP | |
| 4 | TEST | 186-Stack | 2 | ENTER/LEAVE round-trip | **Purpose:** BP/SP restored to original | |
| 4 | TEST | 186-BOUND | 2 | BOUND in-range (no exception) | **Purpose:** signed lower ≤ index ≤ upper. Spec: [186-bound.md](specs/80186-286/186-bound.md) | |
| 4 | TEST | 186-BOUND | 2 | BOUND above upper (#BR) | **Purpose:** index > upper → #BR exception | |
| 4 | TEST | 186-BOUND | 2 | BOUND below lower (#BR) | **Purpose:** index < lower (signed) → #BR | |
| 4 | TEST | 186-BOUND | 2 | BOUND negative range | **Purpose:** negative bounds work correctly (signed) | |
| 4 | TEST | 186-BOUND | 2 | BOUND 32-bit (386+) | **Purpose:** BOUND EAX, m32&32 | |
| 4 | TEST | 186-BOUND | 2 | BOUND #BR return address | **Purpose:** pushed IP = BOUND instruction, not next | |
| 4 | TEST | 186 | 2 | PUSHA/POPA | **Purpose:** all GP regs pushed/popped in order, SP discarded on POPA | |
| 4 | TEST | 186 | 2 | PUSH imm16, PUSH imm8 | **Purpose:** immediate push, sign-extension for imm8 | |
| 4 | TEST | 186 | 2 | IMUL r,r/m,imm | **Purpose:** three-operand IMUL | |
| 4 | TEST | 186-IO | 3 | INSB/INSW (port→mem) | **Purpose:** verify DI update, DF handling. Spec: [186-io-string.md](specs/80186-286/186-io-string.md) | |
| 4 | TEST | 186-IO | 3 | OUTSB/OUTSW (mem→port) | **Purpose:** verify SI update, segment override | |
| 4 | TEST | 186-IO | 3 | REP INS/OUTS | **Purpose:** CX count, direction flag | |
| 4 | TEST | 186-IO | 3 | INS/OUTS segment override | **Purpose:** OUTS allows override, INS does not | |
| 4 | TEST | 186 | 2 | Shift/rotate by imm8 | **Purpose:** 8086 required CL, 186+ allows immediate | |
| 4 | TEST | 286-Real | 2 | 186 ISA on 286 | **Purpose:** verify compatibility | |
| 4 | TEST | 286-Real | 2 | Shift-count masking | **Purpose:** &0x1F now active in real mode too | |
| 4 | INFRA | 286-PM | 1 | Minimal GDT setup | Code/data/stack descriptors | |
| 4 | INFRA | 286-PM | 1 | LGDT, MOV CR0/LMSW | Enable PE bit | |
| 4 | INFRA | 286-PM | 1 | Far JMP to reload CS | Flush prefetch, load PM selector | |
| 4 | INFRA | 286-PM | 1 | PM exit (386+) | Clear PE, reload real-mode segments | |
| 4 | TEST | 286-Desc | 1 | Null selector load vs use | **Purpose:** load into DS/ES legal, use faults | |
| 4 | TEST | 286-Desc | 1 | Null into SS | **Purpose:** immediate #GP | |
| 4 | TEST | 286-Desc | 1 | Present bit = 0 | **Purpose:** #NP (or #SS for stack) | |
| 4 | TEST | 286-Desc | 1 | Type checks | **Purpose:** data→CS, exec-only→DS → #GP | |
| 4 | TEST | 286-Desc | 1 | DPL/RPL/CPL | **Purpose:** privilege violation → #GP | |
| 4 | TEST | 286-Desc | 1 | Selector beyond limit | **Purpose:** index > GDT/LDT limit → #GP | |
| 4 | TEST | 286-Desc | 1 | Accessed bit RMW | **Purpose:** A-bit written to descriptor on load | |
| 4 | TEST | 286-Limit | 1 | Last-byte enforcement | **Purpose:** access at limit succeeds, limit+1 faults | |
| 4 | TEST | 286-Limit | 1 | Expand-down segments | **Purpose:** inverted limit semantics | |
| 4 | TEST | 286-Exc | 1 | #GP/#NP/#SS/#TS + error | **Purpose:** correct vector and error code | |
| 4 | TEST | 286-Exc | 1 | Error code encoding | **Purpose:** selector + ext/idt/ti bits | |
| 4 | TEST | 286-Desc | 2 | LAR/LSL/VERR/VERW/ARPL | **Purpose:** descriptor query insns, full check matrix (§6.1). ORACLE: manual+golden | |
| 4 | TEST | 286-Desc | 2 | Conforming code segment matrix | **Purpose:** conforming vs non-conforming CS load/transfer full matrix (§6.3). ORACLE: manual | |
| 4 | TEST | 286-Desc | 2 | 286 SGDT high-byte quirk | **Purpose:** SGDT returns garbage in high byte on 286. ORACLE: golden | |
| 4 | TEST | 286-Sys | 3 | LOADALL (0F 05/07) constructible subset | **Purpose:** load entire CPU state from memory block; test constructible cases only (§6.4). ORACLE: golden | |
| 4 | TEST | 286-Sys | 2 | LDT switching / LLDT / LDT-relative loads | **Purpose:** LLDT + segment loads relative to LDT (SST386PM gap). ORACLE: manual+xsuite | |
| 4 | TEST | 286-Mode | 3 | PM→real escape (reset/KBC/triple-fault) | **Purpose:** 286 can't cleanly exit PM; test observable path. ORACLE: golden. Post-reset →C | |
| 5 | TEST | 386-32bit | 1 | 32-bit arith/logic/shift | **Purpose:** extend Phase 2 to EAX/EBX/etc. ORACLE: manual. `src/cpu/80386/arith32.asm` (35 sub-tests: ADD/SUB/ADC/SBB carry chains, MUL/DIV 32-bit, INC/DEC/NEG 32-bit) | ✓ |
| 5 | TEST | 386-32bit | 1 | 32-bit string ops (MOVSD/STOSD/LODSD/CMPSD/SCASD + REP) | **Purpose:** 32-bit string instructions with ECX counter, DF direction. ORACLE: manual. `src/cpu/80386/strings32.asm` (12 sub-tests) | ✓ |
| 5 | TEST | 386-32bit | 1 | Operand-size prefix (66h) | **Purpose:** 16↔32 bit toggle. Covered in addr32, seg386, arith32, shifts32 | ✓ |
| 5 | TEST | 386-32bit | 1 | Address-size prefix (67h) | **Purpose:** 16↔32 bit addressing. Covered in addr32 | ✓ |
| 5 | TEST | 386-New | 1 | MOVSX/MOVZX | **Purpose:** sign/zero extend 8→16/32, 16→32 incl memory operands. ORACLE: manual. `src/cpu/80386/new_insns.asm` (29 sub-tests) | ✓ |
| 5 | TEST | 386-New | 1 | SETcc (16 conditions) | **Purpose:** set byte to 0/1 based on flags. `src/cpu/80386/new_insns.asm` | ✓ |
| 5 | TEST | 386-New | 1 | BT/BTS/BTR/BTC | **Purpose:** bit test and modify, CF=bit value, reg+memory forms, register-index. ORACLE: manual. `src/cpu/80386/bitops.asm` (25 sub-tests). **Gap:** large bit offset address crossing (bit≥32 on memory) not tested — DOSBox-X core=normal does not implement this; TODO: test on 86Box/real HW | ✓ |
| 5 | TEST | 386-New-Gap | 2 | **GAP: BT/BTS/BTR/BTC large bit offset address crossing** | **Purpose:** BT m32,r32 with bit index ≥32 must access `mem[base + (index/8)]` (crossing dword boundary). This is a documented 386 architectural feature. **Untested** because DOSBox-X `core=normal` does not implement the address adjustment. **Action:** add test on 86Box (which implements this correctly) and/or real 486 HW. See: [coverage-matrix §16](coverage-matrix.md#16-explicitly-out-of-this-matrix-venue-routed), [specs/80386/new.md Known Gap](specs/80386/new.md#known-gap). ORACLE: manual (Intel SDM 80386) | |
| 5 | TEST | 386-New | 1 | BSF/BSR src=0 | **Purpose:** ZF=1, dest UNCHANGED. `src/cpu/80386/bitops.asm` | ✓ |
| 5 | TEST | 386-New | 1 | SHLD/SHRD | **Purpose:** double-precision shift, count masking (CL&0x1F), OF for count=1. ORACLE: manual. `src/cpu/80386/shifts32.asm` (24 sub-tests) | ✓ |
| 5 | TEST | 386-New | 1 | LFS/LGS/LSS + PUSHFD/POPFD + PUSH imm32 | **Purpose:** segment load far pointers, 32-bit flag ops, 32-bit push. ORACLE: manual. `src/cpu/80386/seg386.asm` (11 sub-tests) | ✓ |
| 5 | TEST | 386-Addr | 1 | 32-bit ModR/M forms | **Purpose:** all [base+idx*scale+disp] combos. ORACLE: manual. `src/cpu/80386/addr32.asm` (17 sub-tests) | ✓ |
| 5 | TEST | 386-Addr | 1 | SIB byte | **Purpose:** scale ×1/×2/×4/×8, index, base fields | ✓ |
| 5 | TEST | 386-Addr | 1 | SIB no-base | **Purpose:** mod=0 base=5 → disp32 absolute. Covered in addr32 | ✓ |
| 5 | TEST | 386-Addr | 2 | ESP as index | **Purpose:** illegal encoding (reserved) | |
| 5 | INFRA | Import | 1 | Run import_singlestep_pm | Generate gates/paging/v86/segments JSON | |
| 5 | TEST | Import | 1 | Verify SST vectors | **~1000+ cases** across 122 files | |
| 5 | INFRA | 386-Gate | 1 | Set up call gate in GDT | Selector 0x30, target = ring 0 code | |
| 5 | TEST | 386-Gate | 1 | CALL gate same privilege | **Purpose:** no stack switch, push CS:EIP | |
| 5 | TEST | 386-Gate | 1 | CALL gate cross privilege | **Purpose:** stack switch via TSS SS0:ESP0 | |
| 5 | TEST | 386-Gate | 1 | CALL gate param copy | **Purpose:** dword count field copies stack params | |
| 5 | TEST | 386-Gate | 1 | JMP through gate | **Purpose:** no return address pushed | |
| 5 | TEST | 386-Gate | 1 | Oracle vs SST386PM | **Purpose:** results must match SST vectors | |
| 5 | INFRA | 386-TSS | 1 | Import test386 TSS patterns | Task switch test structure | |
| 5 | INFRA | 386-TSS | 1 | Set up 2 TSS in GDT | Task A and Task B | |
| 5 | TEST | 386-TSS | 1 | JMP to TSS | **Purpose:** direct task switch | |
| 5 | TEST | 386-TSS | 1 | CALL to TSS | **Purpose:** nested task, backlink set | |
| 5 | TEST | 386-TSS | 1 | IRET from nested | **Purpose:** return via backlink | |
| 5 | TEST | 386-TSS | 1 | TSS busy bit | **Purpose:** set on entry, cleared on exit | |
| 5 | TEST | 386-TSS | 1 | SS0:ESP0 loading | **Purpose:** privilege switch uses TSS stack | |
| 5 | INFRA | 386-Page | 1 | Set up PD and PT | Identity-map first 4MB + test region | |
| 5 | INFRA | 386-Page | 1 | Enable paging (CR0.PG) | — | |
| 5 | TEST | 386-Page | 1 | Linear→physical | **Purpose:** correct address translation | |
| 5 | TEST | 386-Page | 1 | #PF not-present | **Purpose:** P=0 → #PF with error code P=0 | |
| 5 | TEST | 386-Page | 1 | #PF write-to-RO | **Purpose:** W/R=0 write → #PF with W=1 | |
| 5 | TEST | 386-Page | 1 | #PF user-vs-super | **Purpose:** U/S enforcement | |
| 5 | TEST | 386-Page | 1 | #PF error code bits | **Purpose:** P/W/U decoded correctly | |
| 5 | TEST | 386-Page | 1 | A/D bit updates | **Purpose:** A on access, D on write | |
| 5 | TEST | 386-Page | 1 | MOV CR3 TLB flush | **Purpose:** new CR3 invalidates all entries | |
| 5 | TEST | 386-Page | 2 | TLB staleness | **Purpose:** modify PTE w/o flush → old mapping | |
| 5 | TEST | 386-Page | 1 | Oracle vs SST386PM | **Purpose:** results must match SST vectors | |
| 5 | INFRA | 386-V86 | 1 | Enter V86 (IRET VM=1) | Set VM bit in EFLAGS via IRET | |
| 5 | TEST | 386-V86 | 1 | IOPL-sensitive IOPL=0 | **Purpose:** CLI/STI/etc trap to monitor | |
| 5 | TEST | 386-V86 | 1 | IOPL-sensitive IOPL=3 | **Purpose:** CLI/STI/etc execute directly | |
| 5 | TEST | 386-V86 | 1 | PUSHF/POPF in V86 | **Purpose:** VM bit handling | |
| 5 | TEST | 386-V86 | 1 | INT reflection | **Purpose:** software INT handling | |
| 5 | TEST | 386-V86 | 1 | Oracle vs SST386PM | **Purpose:** results must match SST vectors | |
| 5 | TEST | 386-Debug | 2 | DR0-3 breakpoints | **Purpose:** execution and data breakpoints | |
| 5 | TEST | 386-Debug | 2 | #DB on match | **Purpose:** breakpoint triggers trap | |
| 5 | TEST | 386-Debug | 2 | DR7 enable bits | **Purpose:** L0-L3, G0-G3 activation | |
| 5 | TEST | 386-Debug | 2 | DR6 status | **Purpose:** which breakpoint triggered | |
| 5 | TEST | 386-Debug | 2 | GD bit | **Purpose:** debug register protection | |
| 5 | TEST | 386-CR | 2 | CR0/CR2/CR3 | **Purpose:** bit semantics | |
| 5 | TEST | 386-CR | 2 | Reserved bits | **Purpose:** read-back behavior | |
| 5 | TEST | 386-Debug | 2 | TR3–TR7 test registers | **Purpose:** cache test regs (486); read/write back behavior. ORACLE: golden | |
| 5 | TEST | 386-Gate | 2 | INT *n* gate-DPL vs CPL privilege | **Purpose:** software INT gate privilege checks (distinct from HW IRQ). ORACLE: xsuite | |
| 5 | TEST | 386-Limit | 1 | Byte granularity (G=0) limit | **Purpose:** limit field = effective limit. Spec: [386/limits.md](specs/80386/limits.md) | |
| 5 | TEST | 386-Limit | 1 | Page granularity (G=1) limit | **Purpose:** effective = (limit<<12)\|0xFFF, up to 4GB | |
| 5 | TEST | 386-Limit | 1 | Operand size vs limit | **Purpose:** offset + (size-1) ≤ limit | |
| 5 | TEST | 386-Limit | 1 | Expand-down segment (E=1) | **Purpose:** valid range = (limit+1) to max | |
| 5 | TEST | 386-Limit | 1 | Expand-down + G=1 | **Purpose:** page-granular expand-down | |
| 5 | TEST | 386-Limit | 2 | Code segment EIP limit | **Purpose:** #GP when EIP exceeds CS limit | |
| 5 | TEST | 386-Limit | 2 | Stack segment ESP limit | **Purpose:** #SS on PUSH beyond limit | |
| 5 | TEST | 386-Limit | 2 | D/B bit interaction | **Purpose:** 16-bit vs 32-bit default operand/address | |
| 6 | TEST | 486-New | 1 | BSWAP 32-bit | **Purpose:** byte swap EAX→EAX. `src/cpu/80486/new486.asm` tests 1–5, 15 | ✓ |
| 6 | TEST | 486-New | 1 | BSWAP 16-bit | **Purpose:** undefined, pin actual result | |
| 6 | TEST | 486-New | 1 | XADD | **Purpose:** exchange and add, verify flags. `src/cpu/80486/new486.asm` tests 6–9, 16 | ✓ |
| 6 | TEST | 486-New | 1 | CMPXCHG | **Purpose:** ZF semantics, accumulator update. `src/cpu/80486/new486.asm` tests 10–13 | ✓ |
| 6 | TEST | 486-New | 2 | LOCK variants | **Purpose:** LOCK XADD, LOCK CMPXCHG. `src/cpu/80486/new486.asm` tests 18–19 | ✓ |
| 6 | TEST | 486-New | 2 | INVD/WBINVD | **Purpose:** cache invalidate (functional) | |
| 6 | TEST | 486-New | 2 | INVLPG | **Purpose:** single TLB entry invalidate | |
| 6 | TEST | 486-Cache | 1 | SMC coherence | **Purpose:** write to code line → fetches new bytes | |
| 6 | TEST | 486-Cache | 2 | Cached vs uncached band | **Purpose:** timing ratio proves cache active | |
| 6 | TEST | 486-Cache | 3 | CR0.CD/NW, PCD/PWT | **Purpose:** cache control bits | |
| 6 | TEST | 486-CPUID | 2 | EFLAGS.ID toggle | **Purpose:** CPUID present if ID toggles. `src/cpu/80486/new486.asm` test 14 | ✓ |
| 6 | TEST | 486-CPUID | 2 | Leaf 0 vendor | **Purpose:** "GenuineIntel" or AMD/Cyrix. `src/cpu/80486/new486.asm` test 14 | ✓ |
| 6 | TEST | 486-CPUID | 2 | Leaf 1 family/model | **Purpose:** CPU identification. `src/cpu/80486/new486.asm` test 17 | ✓ |
| 6 | TEST | 486-AC | 2 | CR0.AM + EFLAGS.AC | **Purpose:** enable alignment check | |
| 6 | TEST | 486-AC | 2 | Misaligned word → #AC | **Purpose:** word at odd address faults | |
| 6 | TEST | 486-AC | 2 | #AC ring 3 only | **Purpose:** ring 0 no fault, ring 3 faults | |
| 6 | TEST | 486-WP | 2 | CR0.WP=0 | **Purpose:** supervisor writes R/O user page | |
| 6 | TEST | 486-WP | 2 | CR0.WP=1 | **Purpose:** supervisor write → #PF | |
| 7 | TEST | PIC | 1 | ICW1-4 sequence | **Purpose:** proper initialization | |
| 7 | TEST | PIC | 1 | OCW1/OCW2/OCW3 | **Purpose:** mask, EOI, read commands | |
| 7 | TEST | PIC | 1 | Specific vs non-specific EOI | **Purpose:** EOI behavior differs | |
| 7 | TEST | PIC | 2 | Rotating priority | **Purpose:** round-robin IRQ priority | |
| 7 | TEST | PIC | 1 | Cascade EOI order | **Purpose:** slave EOI before master | |
| 7 | TEST | PIC | 1 | Spurious IRQ7/IRQ15 | **Purpose:** IRQ dropped → spurious vector | |
| 7 | TEST | PIC | 2 | Edge vs level | **Purpose:** trigger mode | |
| 7 | INFRA | PIC | 1 | Save/restore state | Preserve system PIC config | |
| 7 | TEST | PIT | 1 | Modes 0-5 | **Purpose:** all timer modes. Spec: [peripheral/pit.md](specs/peripheral/pit.md) | |
| 7 | TEST | PIT | 1 | Count=0 means 65536 | **Purpose:** 0 is max count | |
| 7 | TEST | PIT | 2 | BCD mode | **Purpose:** BCD counting (0-9999) | |
| 7 | TEST | PIT | 1 | Latch command | **Purpose:** freeze count for read | |
| 7 | TEST | PIT | 1 | Latch mid-count | **Purpose:** multiple reads return same latched value | |
| 7 | TEST | PIT | 1 | Read-back status + count | **Purpose:** combined status/count read-back | |
| 7 | TEST | PIT | 1 | Null-count flag | **Purpose:** status bit 6 = count not yet loaded | |
| 7 | TEST | PIT | 1 | Access modes | **Purpose:** LSB/MSB/LSB+MSB flip-flop | |
| 7 | TEST | PIT | 1 | Flip-flop state preservation | **Purpose:** latch resets flip-flop | |
| 7 | TEST | PIT | 2 | Mode 2 rate generator | **Purpose:** N-1 HIGH, 1 LOW per period | |
| 7 | TEST | PIT | 2 | Mode 3 square wave duty | **Purpose:** odd count → extra HIGH cycle | |
| 7 | TEST | PIT | 2 | GATE input effects | **Purpose:** pause/restart on GATE low/edge | |
| 7 | TEST | PIT | 2 | Ch2 + speaker gate | **Purpose:** port 61h gating | |
| 7 | TEST | PIT | 3 | Mode change mid-count | **Purpose:** reprogram while counting | |
| 7 | INFRA | PIT | 1 | Save/restore state | Preserve system PIT config | |
| 7 | INFRA | DMA | 1 | Save/restore state | Preserve system DMA config | |
| 7 | TEST | DMA | 2 | Mode register | **Purpose:** transfer mode setup | |
| 7 | TEST | DMA | 2 | Single/block/demand | **Purpose:** transfer types | |
| 7 | TEST | DMA | 2 | Auto-init | **Purpose:** count reload | |
| 7 | TEST | DMA | 2 | TC + status | **Purpose:** terminal count | |
| 7 | TEST | DMA | 2 | Byte flip-flop | **Purpose:** LSB/MSB toggle | |
| 7 | TEST | DMA | 2 | 64K boundary | **Purpose:** can't cross boundary | |
| 7 | TEST | KBC | 2 | IBF/OBF polling | **Purpose:** buffer status | |
| 7 | TEST | KBC | 2 | Self-test 0xAA→0x55 | **Purpose:** controller OK | |
| 7 | TEST | KBC | 1 | A20 via output port | **Purpose:** bit 1 controls A20 | |
| 7 | TEST | RTC | 2 | UIP polling | **Purpose:** don't read during update. Spec: [peripheral/rtc.md](specs/peripheral/rtc.md) | |
| 7 | TEST | RTC | 2 | UIP timing window | **Purpose:** ~2ms UIP=1, then 244µs safe read | |
| 7 | TEST | RTC | 2 | BCD vs binary mode | **Purpose:** Status B bit 2 (DM) toggles format | |
| 7 | TEST | RTC | 2 | 12/24-hour mode | **Purpose:** Status B bit 1, PM flag in hour | |
| 7 | TEST | RTC | 2 | Alarm don't-care bytes | **Purpose:** 0xC0 = match any | |
| 7 | TEST | RTC | 2 | Alarm interrupt | **Purpose:** AIE + time match → AF + IRQF | |
| 7 | TEST | RTC | 2 | Status C read-clear | **Purpose:** reading clears PF/AF/UF flags | |
| 7 | TEST | RTC | 3 | Periodic interrupt rate | **Purpose:** RS bits select 2-8192 Hz | |
| 7 | TEST | RTC | 3 | NMI gating (port 70h bit 7) | **Purpose:** bit 7 = NMI disable | |
| 7 | TEST | RTC | 3 | VRT bit (Status D) | **Purpose:** battery valid indicator | |
| 7 | TEST | RTC | 3 | Century byte location | **Purpose:** 0x32 typical, report actual | |
| 7 | INFRA | RTC | 1 | Save/restore state | Preserve system RTC config | |
| 7 | TEST | IDE | 2 | BSY/DRQ/DRDY | **Purpose:** status protocol | |
| 7 | TEST | IDE | 2 | IDENTIFY | **Purpose:** drive information | |
| 7 | TEST | IDE | 2 | Alternate status | **Purpose:** no IRQ side effect | |
| 7 | TEST | IDE | 2 | 400ns settle | **Purpose:** device selection timing | |
| 7 | TEST | VGA | 1 | AC flip-flop | **Purpose:** index/data toggle at 0x3C0 | |
| 7 | TEST | VGA | 1 | Read 0x3DA resets | **Purpose:** reset flip-flop | |
| 7 | TEST | VGA | 2 | Sequencer/CRTC/GC | **Purpose:** register access | |
| 7 | TEST | VGA | 2 | DAC auto-increment | **Purpose:** 3-write RGB sequence | |
| 7 | TEST | VGA | 3 | Chain-4 mode 13h | **Purpose:** linear framebuffer mode | |
| 7 | INFRA | VGA | 1 | Save/restore state | Preserve video state | |
| 7 | TEST | Sound | 3 | PC speaker | **Purpose:** PIT ch2 + port 61h | |
| 7 | TEST | Sound | 3 | OPL2 timer | **Purpose:** timer status flags | |
| 7 | TEST | Sound | 3 | OPL3 detect | **Purpose:** 4-op mode available | |
| 7 | TEST | Sound | 3 | SB DSP reset | **Purpose:** version query | |
| 7 | TEST | Sound | 4 | GUS detection | **Purpose:** RAM peek/poke. **DEFERRED** — scope TBD if ao486 lacks GUS HW (§9 note) | |
| 7 | TEST | Sound | 4 | MPU-401 UART mode | **Purpose:** cmd ack. **DEFERRED** — scope TBD (§9 note) | |
| 7 | TEST | UART | 2 | DLAB gating | **Purpose:** DLL/DLH vs data/IER | |
| 7 | TEST | UART | 2 | Scratch register | **Purpose:** 8250 lacks it (chip ID) | |
| 7 | TEST | UART | 2 | Loopback mode | **Purpose:** self-test w/o cable | |
| 7 | TEST | UART | 2 | FIFO (16550A) | **Purpose:** IIR status bits | |
| 7 | INFRA | UART | 1 | Save/restore state | Preserve system UART config | |
| 8 | TEST | A20 | 1 | A20 via KBC | **Purpose:** output port bit 1 | |
| 8 | TEST | A20 | 1 | Fast A20 (0x92) | **Purpose:** port 92h bit 1 | |
| 8 | TEST | A20 | 1 | FFFF:0010 wrap | **Purpose:** A20 off → wraps to 0 | |
| 8 | TEST | IntBound | 1 | MOV SS shadow | **Purpose:** IRQ inhibited for 1 insn after MOV SS | |
| 8 | TEST | IntBound | 1 | STI delay | **Purpose:** IF delayed 1 insn after STI | |
| 8 | TEST | IntBound | 1 | TF + MOV SS | **Purpose:** TF also inhibited | |
| 8 | TEST | IntBound | 1 | POPF setting TF | **Purpose:** #DB on NEXT instruction | |
| 8 | TEST | Except | 1 | Fault vs trap | **Purpose:** faults restart, traps continue | |
| 8 | TEST | Except | 1 | Pushed CS:IP | **Purpose:** fault=faulting insn, trap=next insn | |
| 8 | TEST | Except | 1 | Error code presence | **Purpose:** which vectors push error code | |
| 8 | TEST | Except | 2 | Double fault #DF | **Purpose:** contributory + contributory | |
| 8 | TEST | Mode | 1 | Real → PM | **Purpose:** PE=1 transition | |
| 8 | TEST | Mode | 1 | PM → Real | **Purpose:** PE=0 transition (386+) | |
| 8 | TEST | Mode | 1 | Unreal mode | **Purpose:** big limit persists to real | |
| 8 | TEST | Mode | 2 | PM → V86 | **Purpose:** VM=1 via IRET | |
| 8 | TEST | Memory | 2 | Conventional/UMA/HMA | **Purpose:** memory map regions | |
| 8 | TEST | Memory | 2 | Video aliases | **Purpose:** A000/B000/B800 | |
| 8 | TEST | Except | 2 | #DF classification matrix | **Purpose:** contributory-vs-benign exception pairs → #DF or not. ORACLE: manual | |
| 8 | TEST | BIOS | 3 | INT 10/13/16/1A sanity | **Purpose:** BIOS service integration smoke test. ORACLE: golden | |
| 8 | TEST | Periph | 4 | LPT data/status/control loop | **Purpose:** parallel port R/W. **DEFERRED** — scope TBD (§9 note) | |
| 9 | INFRA | Timing | 2 | timing_measure_loop | Helper for timing measurements | |
| 9 | INFRA | Timing | 2 | Reference bands | Per-target tolerance definitions | |
| 9 | INFRA | Timing | 2 | Band comparison | Within-tolerance check | |
| 9 | TEST | Timing | 3 | Cached vs uncached | **Purpose:** ratio proves cache active. Spec: [timing/timing.md](specs/timing/timing.md) | |
| 9 | TEST | Timing | 3 | Branch taken/not | **Purpose:** branch penalty measurement | |
| 9 | TEST | Timing | 3 | IRQ latency | **Purpose:** coarse interrupt response (50-100 clocks) | |
| 9 | TEST | Timing | 3 | FDIV latency | **Purpose:** ~73 clocks per FDIV (486) | |
| 9 | TEST | Timing | 4 | Integer ALU timing | **Purpose:** ADD/MUL/DIV clock bands | |
| 9 | TEST | Timing | 4 | FPU transcendental timing | **Purpose:** FSIN/FCOS ~250-350 clocks | |
| 9 | TEST | Timing | 4 | Memory access timing | **Purpose:** aligned vs misaligned | |
| 9 | TEST | Timing | 4 | REP MOVSD throughput | **Purpose:** string move bandwidth | |
| 9 | TEST | Timing | 4 | ao486 deviation report | **Purpose:** compare against 486DX-33 baseline | |
| 9 | INFRA | Timing | 2 | Deviation reporting | Report bands, never hard-fail | |
| 10 | TEST | Integr | 1 | All modules run | **Purpose:** no crashes or hangs | |
| 10 | TEST | Integr | 1 | Order independence | **Purpose:** results same in any order | |
| 10 | TEST | Integr | 1 | Idempotent | **Purpose:** twice = same result | |
| 10 | TEST | Integr | 1 | Filter test | **Purpose:** /cpu, /module work | |
| 10 | TEST | ao486 | 1 | Run on MiSTer | **Purpose:** primary validation target | |
| 10 | TEST | ao486 | 1 | Capture serial log | **Purpose:** save results | |
| 10 | TEST | ao486 | 1 | Document divergences | **Purpose:** known issues | |
| 10 | TEST | Emulators | 2 | DOSBox-X/86Box/PCem | **Purpose:** cross-emulator check | |
| 10 | TEST | Emulators | 2 | Compare results | **Purpose:** find common bugs | |
| 10 | TEST | RealHW | 2 | Run on real 486 | **Purpose:** ground truth baseline | |
| 10 | TEST | RealHW | 2 | Capture reference | **Purpose:** authoritative results | |
| 10 | INFRA | Docs | 1 | Update README | Final instructions | |
| 10 | INFRA | Docs | 1 | Update coverage-matrix | Actual test counts | |
| 10 | INFRA | Docs | 2 | Verify doc links | No broken links | |
| 10 | INFRA | Boot | 3 | Bootable image | Standalone, no DOS | |
| 10 | TEST | Boot | 3 | Test bare-metal | **Purpose:** serial-only output works | |

---

## Per-Module Merge Checklist

| Gate | Check |
|------|-------|
| Build DOS | `make dos` zero warnings |
| Build Linux | `make linux` (if UNIVERSAL) |
| DOSBox-X | Runs green |
| 86Box | Runs green (if PM/HW) |
| Oracle | Linux = DOS (UNIVERSAL) |
| State | No leakage |
| Skip | Clean skip on lower CPU |
| Header | TIER/VENUE/GEN/ORACLE/REFS |
| Determinism | No unlogged entropy |

---

## Golden-Vector Bootstrapping (Phase 1.5 Detail)

**Problem:** Priority #1 work (undefined-but-deterministic flags) is only
authoritative from period-correct silicon. The modern host CPU (the only oracle
available via `make oracle`) produces *wrong* values for this class (AGENTS §4.4).
Golden capture is therefore a **hard prerequisite** for Phase 2's flag-golden
tests, not a Phase 10 cleanup task.

**Capture plan:**

| Golden item | Required from | Method | Storage |
|-------------|---------------|--------|--------|
| MUL/IMUL undefined flags (SF/ZF/AF/PF) per width | real 486DX | Run on HW or trusted emulator-of-record, PUSHF after each op | `data/vectors/golden_mul_flags.json` |
| Multi-bit shift/rotate OF per width+count | real 486DX | Same; cover count ∈ {2,7,8,15,16,17,31,32,33,255} | `data/vectors/golden_shift_of.json` |
| BCD-adjust undefined flags | real 486DX | DAA/DAS/AAA/AAS with pre-seeded AF/CF | `data/vectors/golden_bcd_flags.json` |
| Logic-op AF | real 486DX | AND/OR/XOR/TEST result+AF | `data/vectors/golden_logic_af.json` |

**Provenance tagging:** Every golden entry records:
- `source`: the exact chip/stepping (e.g. `i486DX-33-S-stepping`) or emulator+version
- `capture_date`: when captured
- `method`: how the value was obtained (direct PUSHF, or emulator state dump)

**Fallback if no real hardware:** designate 86Box (specific version) as the
*provisional* golden source. Tag all such vectors `ORACLE: provisional-golden`
and document that they are subject to real-silicon validation. This is explicitly
inferior to real-HW capture — it is a bootstrap, not a substitute.

> See [coverage-matrix.md](coverage-matrix.md) §14.1 for the full
> oracle-provenance mapping per priority.

---

## Module Sizing & Overlay Strategy

**Concern (prep-phase §C2):** NFR-7 caps each test module at 64 KB. Golden
data (operand + expected result + expected flags per case) embedded as NASM
data blocks can approach this limit for high-case-count modules.

**Rough sizing estimate** (per case: 2 bytes operand + 2 bytes expected + 2
bytes expected flags = 6 bytes compactly encoded):

| Module | Est. cases | Est. golden data | Headroom (64KB) |
|--------|-----------|-----------------|-----------------|
| 8086 arith (ADD/ADC/SUB/SBB/CMP/NEG) | ~500 | ~3 KB | ample |
| 8086 shift (all ops × count classes × widths) | ~300 | ~2 KB | ample |
| 8086 string (REP × width × DF × seg-override) | ~200 | ~1 KB | ample |
| 8086 BCD golden | ~150 | ~1 KB | ample |
| 286 PM descriptors (full check matrix) | ~400 | ~3 KB | ample |
| FPU special values (NaN/Inf/denormal × RC/PC) | ~500 | ~4 KB | ample |

**Conclusion:** For the planned case counts (~18,500 total, ~500/module avg),
golden data fits comfortably under 64 KB per module. **No overlay/dynamic-load
mechanism is needed for Phase 1–6.** If a module exceeds 64 KB later (e.g., a
full 2^16-entry flag table), split it into sub-modules by operation rather than
implementing overlay loading. The overlay task (Phase 1, row 50) is **deferred**
until a module actually proves too large.

---

## External Dependencies

| Dependency | Required | Status |
|------------|:--------:|:------:|
| NASM 2.14+ | Yes | |
| OpenWatcom wlink | Yes | |
| DOSBox-X | Yes | |
| 86Box | Yes (PM) | |
| Python 3 | Yes | |
| test386.asm | Yes | |
| SST_80386_protected | Yes | |
| Real 486 HW | No | |

---

## Risks

| Risk | Mitigation |
|------|------------|
| wlink unavailable | Use jwlink or ALINK |
| ao486 unavailable | Use 86Box proxy |
| Real HW unavailable | Emulator consensus |
| test386 GPL-3.0 | Data/patterns only |
| DOSBox-X `core=normal` omits some 386 features (BT large bit offset) | Re-test gap items on 86Box or real HW; track in [coverage-matrix §16](coverage-matrix.md#16-explicitly-out-of-this-matrix-venue-routed) |
| SST format change | Pin v1 snapshot |
