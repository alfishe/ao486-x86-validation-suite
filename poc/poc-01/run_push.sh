#!/bin/bash
# POC-01: Run push mode test
# Starts DOSBox-X, captures serial output to scratch/

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SCRATCH_DIR="$PROJECT_ROOT/scratch"
cd "$SCRIPT_DIR"

# Ensure scratch directory exists
mkdir -p "$SCRATCH_DIR"

# Build if needed
if [ ! -f push.com ]; then
    echo "Building push.com..."
    make push.com
fi

# Check for dosbox-x
DOSBOX=$(command -v dosbox-x 2>/dev/null || echo "")
if [ -z "$DOSBOX" ]; then
    echo "ERROR: dosbox-x not found in PATH"
    echo "Install with: brew install dosbox-x (macOS) or apt install dosbox-x (Linux)"
    exit 1
fi

echo "=== POC-01: Push Mode ==="
echo "Starting DOSBox-X with serial output..."
echo ""

# Result file in scratch/
RESULT_FILE="$SCRATCH_DIR/poc01_results_$(date +%Y%m%d_%H%M%S).txt"
TEMP_CONF="$SCRATCH_DIR/dosbox-push-temp.conf"

# Create config with file output
cat > "$TEMP_CONF" << EOF
[sdl]
autolock=false
waitonerror=false

[dosbox]
machine=svga_s3
memsize=16
quit warning=false
fastbioslogo=true

[cpu]
core=auto
cputype=486
cycles=max

[serial]
serial1=file file:$RESULT_FILE

[dos]
automount=true

[autoexec]
@echo off
mount c $SCRIPT_DIR
c:
push.com
exit
EOF

# Run DOSBox-X (non-interactive)
echo "Running tests..."
"$DOSBOX" -conf "$TEMP_CONF" -exit 2>/dev/null || true

# Clean up temp config
rm -f "$TEMP_CONF"

# Show results
echo ""
echo "=== Results ($(basename "$RESULT_FILE")) ==="
if [ -f "$RESULT_FILE" ]; then
    cat "$RESULT_FILE"
    echo ""
    echo "Success: Serial output captured to scratch/"
else
    echo "ERROR: No output file generated"
    exit 1
fi
