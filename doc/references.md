# x86 Validation Suite - References

## Official Intel Documentation

### Processor Manuals

| Document | CPU | Description | Archive |
|----------|-----|-------------|---------|
| 8086 Family User's Manual | 8086/88 | Original reference | [bitsavers](http://bitsavers.org/components/intel/8086/) |
| iAPX 286 Programmer's Reference Manual | 80286 | Protected mode introduction | Intel 1983 |
| 80386 Programmer's Reference Manual | 80386 | 32-bit, paging, V86 | Intel 1986 |
| i486 Processor Programmer's Reference | 80486 | Cache, new instructions | Intel 1990 |
| Intel Architecture Software Developer's Manual | All | Canonical modern reference | [Intel](https://software.intel.com/en-us/articles/intel-sdm) |

### Datasheets

| Chip | Document | Notes |
|------|----------|-------|
| 8086/8088 | Intel 8086/8088 Data Sheet | Pinout, timing |
| 80186/80188 | Intel 80186/80188 Data Sheet | Integrated peripherals |
| 80286 | Intel 80286 Data Sheet | Protected mode HW |
| 80386DX | Intel 80386DX Data Sheet | Full 32-bit |
| 80386SX | Intel 80386SX Data Sheet | 16-bit bus |
| 80486DX | Intel 80486DX Data Sheet | Integrated FPU, cache |
| 80486SX | Intel 80486SX Data Sheet | No FPU |
| 80487SX | Intel 80487SX Data Sheet | Math coprocessor |

### FPU Documentation

| Document | FPU | Description |
|----------|-----|-------------|
| 8087 Numeric Data Processor | 8087 | Original x87 |
| 80287 Numeric Coprocessor | 80287 | Protected mode |
| 80387 Programmer's Reference | 80387 | New instructions |
| Floating-Point Unit Programmer's Reference | General | IEEE 754 implementation |

## Peripheral Chip Documentation

### Interrupt Controller

| Document | Description |
|----------|-------------|
| 8259A Datasheet | Programmable Interrupt Controller |
| Intel Application Note AP-59 | 8259A design guide |
| IBM PC/AT Technical Reference | Cascade configuration |

### Timer

| Document | Description |
|----------|-------------|
| 8254 Datasheet | Programmable Interval Timer |
| Intel Application Note AP-74 | 8254 applications |

### DMA Controller

| Document | Description |
|----------|-------------|
| 8237A Datasheet | DMA Controller |
| Intel Application Note AP-86 | DMA design guide |
| IBM PC/AT Technical Reference | PC DMA setup |

### Keyboard Controller

| Document | Description |
|----------|-------------|
| 8042 Datasheet | Universal Peripheral Interface |
| IBM PS/2 Technical Reference | PS/2 protocol |
| Adam Chapweske Keyboard FAQ | Comprehensive resource |

### RTC/CMOS

| Document | Description |
|----------|-------------|
| MC146818 Datasheet | Real-Time Clock |
| IBM PC/AT Technical Reference | CMOS memory map |

### Storage

| Document | Description |
|----------|-------------|
| ATA/ATAPI-4 Specification | T13 standard |
| ATA/ATAPI-5 Specification | T13 standard |
| Western Digital Programming Guide | Early IDE reference |

### Video

| Document | Description |
|----------|-------------|
| IBM VGA Technical Reference | VGA programming |
| VESA VBE 2.0 Specification | SVGA standard |
| FreeVGA Project | Comprehensive VGA reference |

### Sound

| Document | Description |
|----------|-------------|
| AdLib Programming Guide | OPL2 FM synthesis |
| Yamaha YMF262 (OPL3) Manual | OPL3 programming |
| Sound Blaster Developer Kit | DSP, mixer programming |
| Gravis Ultrasound SDK | GUS programming |
| MPU-401 Technical Reference | MIDI interface |

### Serial/Parallel

| Document | Description |
|----------|-------------|
| 8250/16450 Datasheet | Basic UART |
| 16550A Datasheet | FIFO UART |
| IEEE 1284 | Parallel port standard |

## Existing Test Suites

### CPU Tests

| Project | URL | Description |
|---------|-----|-------------|
| **ZXALL** | https://github.com/SingleStepTests/ZXALL | Guest-side x86 compatibility tests |
| **SingleStepTests** | https://github.com/SingleStepTests | Per-instruction test vectors |
| **test386.asm** | https://github.com/barotto/test386.asm | Bare-metal 386 PM/paging/TSS diagnostics |
| **SingleStepTests_80386_protected** | https://github.com/nand2mario/SingleStepTests_80386_protected | 122 PM gate/paging/V86 test vectors |
| CPU test | https://github.com/barotto/cpu_test | 8088 validation |
| 8088MPH | Mindcandy | Timing tests |

### Direct Integration Sources

See [external-integration.md](external-integration.md) for detailed analysis. Summary:

| Project | What we import | Format |
|---------|----------------|--------|
| **test386.asm** | Arith/BCD/shift flag golden values, TSS task switch patterns, undocumented behavior | NASM macros + reference output |
| **SingleStepTests_80386_protected** | Call/jump gates, privilege transitions, paging faults, V86 IOPL | JSON vectors (initial→final state) |

### ZXALL (Guest-Side Testing)

ZXALL provides a methodology for running compatibility tests directly on the guest
(inside the emulator/FPGA). This is valuable because:

- Tests run in the actual execution environment
- No external tooling required during test
- Can catch issues that co-simulation misses (memory-mapped I/O, timing)
- Results are directly comparable between real hardware and emulation

**Integration approach:**
- Adapt ZXALL test patterns for our framework
- Use similar result reporting format
- Cross-validate results with SingleStepTests vectors

### SingleStepTests (Co-Simulation / Verilator)

SingleStepTests provides exhaustive per-instruction test vectors primarily designed
for HDL co-simulation (Verilator, Icarus Verilog). Each test case specifies:

- Initial CPU state (all registers, FLAGS, memory)
- Instruction bytes
- Expected final state

**Use cases for this project:**

1. **Vector Import**: Convert SingleStepTests JSON to our guest-side test format
2. **Reference Results**: Use as ground truth for expected behavior
3. **Coverage Analysis**: Identify gaps in our test coverage
4. **Cross-Validation**: Run same vectors in both modes to find discrepancies

**Limitations for guest-side use:**
- Designed for single-instruction stepping (not native guest execution)
- Some tests require precise cycle timing (better suited for HDL sim)
- Memory setup may be complex for guest environment

**Recommended hybrid approach:**
```
┌─────────────────────────────────────────────────────────────┐
│                    Verification Strategy                    │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  ┌──────────────┐         ┌──────────────┐                  │
│  │ SingleStep   │         │    ZXALL     │                  │
│  │   Vectors    │         │   Approach   │                  │
│  └──────┬───────┘         └──────┬───────┘                  │
│         │                        │                          │
│         ▼                        ▼                          │
│  ┌──────────────┐         ┌──────────────┐                  │
│  │  Verilator   │         │  Guest-Side  │                  │
│  │ Co-Simulation│         │    Tests     │                  │
│  │  (HDL level) │         │  (DOS/bare)  │                  │
│  └──────┬───────┘         └──────┬───────┘                  │
│         │                        │                          │
│         └────────┬───────────────┘                          │
│                  ▼                                          │
│         ┌──────────────┐                                    │
│         │   Compare    │                                    │
│         │   Results    │                                    │
│         └──────────────┘                                    │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### FPU Tests

| Project | Description |
|---------|-------------|
| Paranoia | Classic FPU accuracy test |
| ELEFUNT | Elementary function tests |
| TestFloat | IEEE 754 compliance |

### System Tests

| Project | Description |
|---------|-------------|
| Diagnostic ROM | Various | POST-style tests |
| CheckIt | Commercial | System diagnostics |
| QAPlus | Commercial | System diagnostics |

## Emulator Projects

### Active Development

| Emulator | Focus | URL |
|----------|-------|-----|
| ao486 | FPGA 486 | [MiSTer](https://github.com/MiSTer-devel/ao486_MiSTer) |
| DOSBox-X | Feature-rich | https://dosbox-x.com |
| 86Box | Accuracy | https://86box.net |
| PCem | Cycle-accurate | https://pcem-emulator.co.uk |
| MartyPC | 8088 accuracy | https://github.com/dbalsom/martypc |
| VirtualXT | 8088/86 | https://github.com/virtualxt |
| Fake86 | Simple | https://github.com/rubbermallet/fake86 |

### Historical/Reference

| Emulator | Notes |
|----------|-------|
| Bochs | Extensive documentation |
| QEMU | TCG implementation |
| DOSEMU | Linux DOS emulation |
| MAME | Multiple PC implementations |

## Books

### Architecture

| Title | Author | Year | Notes |
|-------|--------|------|-------|
| "Intel Microprocessors" | Brey | Various | Textbook reference |
| "Programming the 80386" | Crawford & Gelsinger | 1987 | Intel engineers |
| "Protected Mode Software Architecture" | Shanley | 1996 | Detailed PM |

### Undocumented Features

| Title | Author | Year | Notes |
|-------|--------|------|-------|
| "Undocumented PC" | van Gilluwe | 1994 | Hardware details |
| "Undocumented DOS" | Schulman | 1993 | DOS internals |
| "PC Interrupts" | Brown & Kyle | 1994 | Comprehensive |

### Hardware

| Title | Author | Notes |
|-------|--------|-------|
| "ISA System Architecture" | Shanley | ISA bus |
| "PCI System Architecture" | Shanley | PCI bus |
| "Pentium Processor System Architecture" | Shanley | Modern reference |

## Online Resources

### Technical References

| Resource | URL | Description |
|----------|-----|-------------|
| OSDev Wiki | https://wiki.osdev.org | OS development |
| FreeVGA | http://www.osdever.net/FreeVGA | VGA programming |
| Ralf Brown's Interrupt List | http://www.ctyme.com/rbrown.htm | Comprehensive |
| Bochs Developer Documentation | http://bochs.sourceforge.net | Emulation details |
| x86 Instruction Reference | https://www.felixcloutier.com/x86/ | Extracted from Intel |

### Archives

| Resource | URL | Description |
|----------|-----|-------------|
| Bitsavers | http://bitsavers.org | Historical documentation |
| Archive.org | https://archive.org | Software archives |
| VETUSWARE | https://vetusware.com | DOS software |

### Communities

| Resource | Description |
|----------|-------------|
| Vogons Forums | Vintage computing |
| MiSTer FPGA Discord | FPGA development |
| DOSBox Forums | Emulation discussion |
| /r/retrobattlestations | Vintage hardware |

## Standards

### IEEE

| Standard | Description |
|----------|-------------|
| IEEE 754-1985 | Floating-point arithmetic |
| IEEE 754-2008 | Updated floating-point |
| IEEE 1284 | Parallel port |

### Industry

| Standard | Description |
|----------|-------------|
| ATA/ATAPI | Storage interface (T13) |
| VESA VBE | Video BIOS extensions |
| MPC Level 1/2/3 | Multimedia PC specs |

## Research Papers

### CPU Behavior

| Paper | Topic |
|-------|-------|
| "A Survey of x86 Verification" | Various | Verification approaches |
| Various Intel errata documents | Known bugs per stepping |

### Emulation

| Paper | Topic |
|-------|-------|
| Bellard, "QEMU" | Dynamic translation |
| Various cycle-counting papers | Timing accuracy |

## Errata and Undocumented Behavior

### Intel Errata

| CPU | Document |
|-----|----------|
| 80386 | 80386 Errata Sheet |
| 80486 | i486 Specification Update |

### Undocumented Instructions

| Instruction | CPU | Documentation |
|-------------|-----|---------------|
| LOADALL | 286/386 | Various reverse engineering |
| SALC | 8086+ | Set AL from Carry |
| ICEBP | 386+ | In-Circuit Emulator breakpoint |
| Various | All | Robert Collins' resources |

### Behavioral Quirks

| Topic | Source |
|-------|--------|
| AAM/AAD with non-10 operand | Undocumented |
| FLAGS bits 1, 3, 5 | Various |
| Prefetch queue effects | Timing-dependent |
| A20 gate quirks | Various |
