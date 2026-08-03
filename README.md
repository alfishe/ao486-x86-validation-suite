# x86 Validation Suite

Comprehensive test suite for validating x86 CPU implementations from 8086 through 80486.

**Target platforms**: FPGA cores (ao486), software emulators (DOSBox, 86Box, PCem), real hardware

## Quick Start

```bash
# Build the test suite
make

# Run on DOS or emulator
C:\> X86VAL.EXE              # All tests
C:\> X86VAL.EXE /cpu:8086    # 8086 tests only
C:\> X86VAL.EXE /fpu         # FPU tests only
C:\> X86VAL.EXE /log:COM1    # Output to serial port
```

## What This Tests

| Component | Coverage |
|-----------|----------|
| **8086/88** | All instructions, FLAGS, addressing modes |
| **80186** | ENTER, LEAVE, BOUND, INS, OUTS, etc. |
| **80286** | Protected mode, descriptors, exceptions |
| **80386** | 32-bit ops, paging, V86 mode, debug regs |
| **80486** | BSWAP, XADD, CMPXCHG, INVD, WBINVD, cache |
| **FPU** | 8087/287/387/486 FPU complete coverage |
| **Peripherals** | PIC, PIT, DMA, KBC, RTC, IDE, VGA, Sound |

## Why Another Test Suite?

Existing tools like 486TEST are **misleading** - they claim to test the CPU but actually only stress the FPU. This suite provides:

- **Real instruction coverage** - every opcode tested
- **FLAGS verification** - not just results, but all flag states
- **Exception testing** - triggers and verifies CPU exceptions
- **Detailed failure reporting** - not just pass/fail
- **Timing validation** - cycle count verification
- **Peripheral integration** - complete system validation

## Documentation

- [AGENTS.md](AGENTS.md) - **Rules for building & maintaining the suite (start here to contribute)**
- [Implementation Plan](doc/implementation-plan.md) - **Master checklist with all phases and tasks**
- [Detailed Test Specs](doc/specs/index.md) - **59 per-module specifications with exact inputs, expected outputs, flags, and divergences**
- [Test Output Guide](doc/test-output-guide.md) - **How to capture results (MiSTer UART, DOSBox-X, automation)**
- [Product Requirements](doc/prd.md) - Full requirements specification
- [Technical Design](doc/technical-design.md) - Architecture and implementation
- [Test Venues](doc/test-venues.md) - Guest vs host vs co-sim vs bench delimitation
- [Coverage Matrix](doc/coverage-matrix.md) - Per-area coverage, hard-case catalog, venue mapping
- [External Integration](doc/external-integration.md) - test386.asm & SingleStepTests import analysis
- [References](doc/references.md) - External resources and specifications
- [Adding Tests](doc/adding-tests.md) - How to contribute tests

## Project Structure

```
x86-validation-suite/
├── doc/                # Documentation
├── src/                # Source code
│   ├── core/           # Framework core
│   ├── cpu/            # CPU test modules
│   ├── fpu/            # FPU test modules
│   ├── peripheral/     # Peripheral tests
│   └── timing/         # Timing validation
├── tests/              # Test vectors and data
├── include/            # NASM include files
├── tools/              # Build and analysis tools
└── build/              # Build output
```

## Requirements

- **Assembler**: NASM 2.x
- **Target**: MS-DOS 3.3+ (or compatible emulator)
- **Memory**: < 256KB conventional

## Building

```bash
make              # Build all
make cpu-8086     # Build 8086 tests only
make boot         # Create bootable image
make clean        # Clean build artifacts
```

## Output Options

```
/log:CON          Console output (default)
/log:COM1         Serial port (COM1/2/3/4)
/log:FILE.TXT     Log to file
/log:CON,COM1     Multiple outputs

/verbose:0        Summary only
/verbose:1        Normal (default)
/verbose:2        Detailed
/verbose:3        Debug

/format:text      Human readable (default)
/format:json      Machine readable JSON
/format:csv       Spreadsheet CSV
```

## Integration with Other Projects

This project builds on two complementary verification approaches:

### ZXALL (Guest-Side Methodology)

We adopt the [ZXALL](https://github.com/SingleStepTests/ZXALL) approach for guest-side
compatibility testing. Tests run natively inside the emulator/FPGA as DOS programs,
catching real-world issues that co-simulation might miss.

### SingleStepTests (Co-Simulation Vectors)

[SingleStepTests](https://github.com/SingleStepTests) provides exhaustive per-instruction
test vectors designed for HDL co-simulation (Verilator). We import applicable vectors
for guest-side validation:

```bash
python3 tools/import_singlestep.py <vectors.json> tests/
```

### Cross-Validation Workflow

```bash
# 1. Run on real hardware, save results
C:\> X86VAL.EXE /format:json /log:REAL_HW.JSON

# 2. Run on emulator
C:\> X86VAL.EXE /format:json /log:EMULATOR.JSON

# 3. Compare results
python3 tools/compare.py REAL_HW.JSON EMULATOR.JSON

# 4. Cross-check with SingleStepTests co-simulation results
python3 tools/compare.py EMULATOR.JSON singlestep_results.json
```

## License

Open source - see [LICENSE](LICENSE)

## Contributing

1. Read [Adding Tests](doc/adding-tests.md)
2. Follow the coding standards
3. Test on real hardware if possible
4. Submit PR with test results

## References

See [doc/references.md](doc/references.md) for complete list of specifications and resources.
