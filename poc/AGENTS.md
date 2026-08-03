# POC Development Rules

Guidelines for creating and maintaining proof-of-concept implementations.

---

## Temporary Files

**All temporary files MUST go to `scratch/` in the project root.**

```
x86-validation-suite/
├── scratch/           # ← ALL temp files here (gitignored)
│   ├── poc01_results_*.txt
│   ├── dosbox-temp.conf
│   └── ...
├── poc/
│   └── poc-01/        # Source code only, no temp files
└── ...
```

Rules:
- `scratch/` is gitignored - never commit temp files
- Use `$PROJECT_ROOT/scratch/` in scripts, not local directories
- Clean up old temp files periodically
- Name temp files with POC prefix: `poc01_results_*.txt`

Example in shell scripts:
```bash
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SCRATCH_DIR="$PROJECT_ROOT/scratch"
mkdir -p "$SCRATCH_DIR"
RESULT_FILE="$SCRATCH_DIR/poc01_results_$(date +%Y%m%d_%H%M%S).txt"
```

---

## POC Philosophy

POCs exist to **validate assumptions** before committing to full implementation.
They are disposable experiments, not production code.

### POC vs Production

| Aspect | POC | Production |
|--------|-----|------------|
| Scope | One specific question | Complete feature |
| Code quality | Functional, readable | Robust, maintainable |
| Error handling | Minimal (crash is OK) | Comprehensive |
| Documentation | Heavy (explain everything) | Standard |
| Tests | Manual verification | Automated |
| Lifespan | Days to weeks | Months to years |

---

## POC Structure

Each POC lives in its own directory under `poc/`:

```
poc/
├── AGENTS.md           # This file - POC rules
├── poc-01/             # First POC
│   ├── README.md       # Comprehensive documentation (required)
│   ├── Makefile        # Build system
│   ├── *.asm           # Source code
│   └── *.sh            # Run scripts
├── poc-02/
│   └── ...
```

### Naming

- Use `poc-NN` format (zero-padded two digits)
- Keep names sequential regardless of topic
- Topic goes in README title, not folder name

---

## Required Documentation

Every POC **must** have a README.md with these sections:

### 1. Goal (Required)

One paragraph stating what question this POC answers.

Bad: "Test serial port"  
Good: "Validate that DOSBox-X can run DOS executables non-interactively with serial output captured to host filesystem, enabling CI/CD automation without user interaction."

### 2. Success Criteria (Required)

Numbered list of specific, measurable outcomes.

| # | Criterion | How to Verify |
|---|-----------|---------------|
| 1 | Specific behavior | Command or observation |
| 2 | Another behavior | How to check it |

### 3. Architecture (Required for non-trivial POCs)

Diagram showing components and data flow. ASCII art is fine:

```
┌─────────┐       ┌─────────┐
│  Part A │──────►│  Part B │
└─────────┘       └─────────┘
```

### 4. Implementation Details (Required)

Explain **how** it works, not just what it does:
- Protocols and data formats
- Key configuration values
- Non-obvious design decisions

### 5. Building (Required)

Prerequisites and build commands:
```bash
# Prerequisites
brew install nasm dosbox-x

# Build
make
```

### 6. Running (Required)

Step-by-step instructions to execute the POC:
```bash
./run.sh
# Expected output:
# ...
```

### 7. Files (Required)

Table of all files with purpose:

| File | Purpose |
|------|---------|
| `main.asm` | Entry point, does X |

### 8. Troubleshooting (Recommended)

Common problems and solutions.

### 9. Next Steps (Recommended)

What to do if the POC succeeds.

---

## Code Guidelines

### Simplicity Over Elegance

POC code should be **obvious**, not clever:

```asm
; Good: clear and direct
mov al, 0x7F
add al, 0x01
pushf
pop bx
cmp al, 0x80
jne fail

; Avoid: optimized but obscure
; (save the cleverness for production)
```

### Comments Liberally

POC code is teaching material. Explain what and why:

```asm
; Initialize COM1 for 115200 baud
; Divisor = 115200 / 115200 = 1
mov dx, COM1_DLL
mov al, 1
out dx, al
```

### No Abstractions

Don't create frameworks or libraries in POCs. Inline everything.
If you need the same code twice, copy-paste it.

### Hardcode Values

Magic numbers are fine in POCs. Document them, don't parameterize:

```asm
COM1_BASE equ 0x3F8  ; Standard PC COM1 address
```

---

## Build System

### Use Make

Simple Makefile, no autotools/cmake:

```makefile
NASM := nasm
NASM_FLAGS := -f bin

all: program.com

program.com: program.asm
	$(NASM) $(NASM_FLAGS) -o $@ $<

clean:
	rm -f *.com
```

### Provide Run Scripts

Shell scripts that handle:
1. Building (if needed)
2. Checking prerequisites
3. Setting up environment
4. Running the POC
5. Showing results

```bash
#!/bin/bash
set -e

# Build
make

# Check prereqs
command -v dosbox-x >/dev/null || { echo "Install dosbox-x"; exit 1; }

# Run
dosbox-x -conf poc.conf
```

---

## Success and Failure

### When POC Succeeds

1. Document findings in README
2. Update main project docs if approach is adopted
3. Consider whether POC code should become production code
4. Archive or delete POC after knowledge is transferred

### When POC Fails

1. Document **why** it failed
2. Record what was tried
3. Note alternative approaches to try
4. Keep the POC for reference (failed experiments have value)

---

## Review Checklist

Before considering a POC complete:

- [ ] README has all required sections
- [ ] Success criteria are clearly stated
- [ ] Build instructions work on clean machine
- [ ] Run instructions produce documented output
- [ ] All files are listed and explained
- [ ] Code is commented enough to understand without context
- [ ] No dependencies on untracked files
- [ ] Clean way to verify success/failure

---

## Anti-Patterns

### Scope Creep

POC should answer ONE question. If you find yourself adding features, stop.
Create a new POC for the new question.

### Production Quality

Don't waste time on:
- Comprehensive error handling
- Edge case coverage
- Performance optimization
- Code reuse/abstraction
- Multiple platform support (unless that's the POC goal)

### Missing Documentation

An undocumented POC is worthless. The code is the least important part.
A future reader should understand the POC from README alone.

### Abandoned State

Either:
- Complete the POC and document results
- Explicitly mark as abandoned with reason

Never leave POCs in "work in progress" state indefinitely.
