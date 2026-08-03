# x86 Validation Suite - Master Makefile
# ========================================

# Tools
NASM = nasm
PYTHON = python3
DOSBOX = dosbox-x

# Directories
SRC = src
INCLUDE = include
BUILD = build
BIN = $(BUILD)/bin
OBJ = $(BUILD)/obj
TESTS = tests
TOOLS = tools
DOC = doc

# NASM flags
NASMFLAGS = -f obj -I$(INCLUDE)/

# Output
TARGET = $(BIN)/x86val.exe

# ============================================================================
# Source files
# ============================================================================

# Core framework
CORE_SRCS = \
    $(SRC)/core/runner.asm \
    $(SRC)/core/output.asm \
    $(SRC)/core/config.asm \
    $(SRC)/core/detect.asm \
    $(SRC)/core/memory.asm \
    $(SRC)/core/timing.asm

# CPU 8086 tests
CPU_8086_SRCS = \
    $(SRC)/cpu/8086/arith.asm \
    $(SRC)/cpu/8086/logic.asm \
    $(SRC)/cpu/8086/shift.asm \
    $(SRC)/cpu/8086/string.asm \
    $(SRC)/cpu/8086/control.asm \
    $(SRC)/cpu/8086/flags.asm \
    $(SRC)/cpu/8086/segment.asm \
    $(SRC)/cpu/8086/stack.asm \
    $(SRC)/cpu/8086/bcd.asm \
    $(SRC)/cpu/8086/misc.asm

# CPU 80186 tests
CPU_186_SRCS = \
    $(SRC)/cpu/80186/new_insns.asm \
    $(SRC)/cpu/80186/enhanced.asm

# CPU 80286 tests
CPU_286_SRCS = \
    $(SRC)/cpu/80286/real.asm \
    $(SRC)/cpu/80286/protected.asm \
    $(SRC)/cpu/80286/descriptors.asm \
    $(SRC)/cpu/80286/exceptions.asm

# CPU 80386 tests
CPU_386_SRCS = \
    $(SRC)/cpu/80386/32bit.asm \
    $(SRC)/cpu/80386/new_insns.asm \
    $(SRC)/cpu/80386/paging.asm \
    $(SRC)/cpu/80386/v86.asm \
    $(SRC)/cpu/80386/debug.asm

# CPU 80486 tests
CPU_486_SRCS = \
    $(SRC)/cpu/80486/new_insns.asm \
    $(SRC)/cpu/80486/cache.asm \
    $(SRC)/cpu/80486/cpuid.asm

# FPU tests
FPU_SRCS = \
    $(SRC)/fpu/detect.asm \
    $(SRC)/fpu/8087/basic.asm \
    $(SRC)/fpu/8087/arith.asm \
    $(SRC)/fpu/8087/compare.asm \
    $(SRC)/fpu/8087/transcend.asm \
    $(SRC)/fpu/8087/control.asm \
    $(SRC)/fpu/8087/exception.asm \
    $(SRC)/fpu/80387/new_insns.asm

# Peripheral tests
PERIPH_SRCS = \
    $(SRC)/peripheral/pic/8259.asm \
    $(SRC)/peripheral/pit/8254.asm \
    $(SRC)/peripheral/dma/8237.asm \
    $(SRC)/peripheral/kbc/8042.asm \
    $(SRC)/peripheral/rtc/mc146818.asm \
    $(SRC)/peripheral/ide/ata.asm \
    $(SRC)/peripheral/vga/vga.asm \
    $(SRC)/peripheral/sound/speaker.asm \
    $(SRC)/peripheral/sound/adlib.asm \
    $(SRC)/peripheral/sound/sb.asm \
    $(SRC)/peripheral/serial/uart.asm

# Timing tests
TIMING_SRCS = \
    $(SRC)/timing/cycles.asm \
    $(SRC)/timing/memory.asm \
    $(SRC)/timing/interrupt.asm

# Main entry
MAIN_SRC = $(SRC)/main.asm

# All sources
ALL_SRCS = $(CORE_SRCS) $(CPU_8086_SRCS) $(CPU_186_SRCS) $(CPU_286_SRCS) \
           $(CPU_386_SRCS) $(CPU_486_SRCS) $(FPU_SRCS) $(PERIPH_SRCS) \
           $(TIMING_SRCS) $(MAIN_SRC)

# Object files
ALL_OBJS = $(patsubst $(SRC)/%.asm,$(OBJ)/%.obj,$(ALL_SRCS))

# ============================================================================
# Targets
# ============================================================================

.PHONY: all clean run boot test help dirs dos linux win32 oracle

all: dirs $(TARGET)
	@echo "Build complete: $(TARGET)"

# Create directories
dirs:
	@mkdir -p $(BIN) $(OBJ)/core $(OBJ)/cpu/8086 $(OBJ)/cpu/80186 \
	          $(OBJ)/cpu/80286 $(OBJ)/cpu/80386 $(OBJ)/cpu/80486 \
	          $(OBJ)/fpu/8087 $(OBJ)/fpu/80387 \
	          $(OBJ)/peripheral/pic $(OBJ)/peripheral/pit \
	          $(OBJ)/peripheral/dma $(OBJ)/peripheral/kbc \
	          $(OBJ)/peripheral/rtc $(OBJ)/peripheral/ide \
	          $(OBJ)/peripheral/vga $(OBJ)/peripheral/sound \
	          $(OBJ)/peripheral/serial $(OBJ)/timing

# Main target (placeholder - actual linking depends on toolchain)
$(TARGET): $(ALL_OBJS)
	@echo "Linking $(TARGET)..."
	@echo "Note: Actual linking requires DOS toolchain (WLINK, TLINK, or MS LINK)"
	@echo "Object files ready in $(OBJ)/"

# Pattern rule for assembly
$(OBJ)/%.obj: $(SRC)/%.asm
	@mkdir -p $(dir $@)
	$(NASM) $(NASMFLAGS) -o $@ $<

# ============================================================================
# Subset builds
# ============================================================================

.PHONY: core cpu-8086 cpu-186 cpu-286 cpu-386 cpu-486 fpu peripheral timing

core: dirs $(patsubst $(SRC)/%.asm,$(OBJ)/%.obj,$(CORE_SRCS))
	@echo "Core framework built"

cpu-8086: dirs $(patsubst $(SRC)/%.asm,$(OBJ)/%.obj,$(CPU_8086_SRCS))
	@echo "8086 tests built"

cpu-186: dirs $(patsubst $(SRC)/%.asm,$(OBJ)/%.obj,$(CPU_186_SRCS))
	@echo "80186 tests built"

cpu-286: dirs $(patsubst $(SRC)/%.asm,$(OBJ)/%.obj,$(CPU_286_SRCS))
	@echo "80286 tests built"

cpu-386: dirs $(patsubst $(SRC)/%.asm,$(OBJ)/%.obj,$(CPU_386_SRCS))
	@echo "80386 tests built"

cpu-486: dirs $(patsubst $(SRC)/%.asm,$(OBJ)/%.obj,$(CPU_486_SRCS))
	@echo "80486 tests built"

fpu: dirs $(patsubst $(SRC)/%.asm,$(OBJ)/%.obj,$(FPU_SRCS))
	@echo "FPU tests built"

peripheral: dirs $(patsubst $(SRC)/%.asm,$(OBJ)/%.obj,$(PERIPH_SRCS))
	@echo "Peripheral tests built"

timing: dirs $(patsubst $(SRC)/%.asm,$(OBJ)/%.obj,$(TIMING_SRCS))
	@echo "Timing tests built"

# ============================================================================
# Testing and running
# ============================================================================

run: $(TARGET)
	$(DOSBOX) -c "mount c $(BIN)" -c "c:" -c "x86val.exe"

# Create bootable image
boot: $(TARGET)
	$(PYTHON) $(TOOLS)/bootimg.py $(TARGET) $(BUILD)/boot/x86val.img

# Run tests in emulator
test: $(TARGET)
	$(PYTHON) $(TOOLS)/run_tests.py

# ============================================================================
# Tools
# ============================================================================

# Import SingleStep test vectors (real-mode 8086)
import-singlestep:
	$(PYTHON) $(TOOLS)/import_singlestep.py

# Import SingleStepTests_80386_protected vectors (PM gates/paging/V86)
import-singlestep-pm:
	$(PYTHON) $(TOOLS)/import_singlestep_pm.py

# Import test386.asm golden flag values
import-test386:
	$(PYTHON) $(TOOLS)/import_test386_arith.py

# Compare results
compare:
	$(PYTHON) $(TOOLS)/compare.py

# Generate test statistics
stats:
	$(PYTHON) $(TOOLS)/stats.py

# ============================================================================
# Maintenance
# ============================================================================

clean:
	rm -rf $(BUILD)

distclean: clean
	rm -f *~ $(SRC)/*~ $(INCLUDE)/*~

# Generate documentation
docs:
	@echo "Documentation is in $(DOC)/"

# ============================================================================
# Help
# ============================================================================

help:
	@echo "x86 Validation Suite - Build System"
	@echo ""
	@echo "Targets:"
	@echo "  all          - Build everything (default)"
	@echo "  clean        - Remove build artifacts"
	@echo "  run          - Run in DOSBox"
	@echo "  boot         - Create bootable image"
	@echo "  test         - Run automated tests"
	@echo ""
	@echo "Subset builds:"
	@echo "  core         - Build framework only"
	@echo "  cpu-8086     - Build 8086 tests"
	@echo "  cpu-186      - Build 80186 tests"
	@echo "  cpu-286      - Build 80286 tests"
	@echo "  cpu-386      - Build 80386 tests"
	@echo "  cpu-486      - Build 80486 tests"
	@echo "  fpu          - Build FPU tests"
	@echo "  peripheral   - Build peripheral tests"
	@echo "  timing       - Build timing tests"
	@echo ""
	@echo "Tools:"
	@echo "  import-singlestep     - Import SingleStep vectors (real-mode)"
	@echo "  import-singlestep-pm  - Import SST386PM vectors (protected-mode)"
	@echo "  import-test386        - Import test386.asm golden flags"
	@echo "  compare               - Compare test results"
	@echo "  stats                 - Show test statistics"
