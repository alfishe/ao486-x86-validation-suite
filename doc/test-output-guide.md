# Test Output & Automation Guide

How to capture, stream, and automate test results across all target environments.

---

## 1. Output Methods Summary

| Method | Real-time | Persistent | Best for |
|--------|:---------:|:----------:|----------|
| **Screen (CON)** | ✓ | — | Quick visual check, demos |
| **Serial (COM1)** | ✓ | ✓ | MiSTer UART, automated capture |
| **File (disk)** | — | ✓ | Batch runs, later analysis |
| **POST codes** | ✓ | — | Bare-metal, no OS |

Our suite supports all simultaneously: `/log:CON,COM1,RESULTS.TXT`

---

## 2. Screen Output

### What you see
```
x86-validate v1.0
==================
CPU: 80486DX   FPU: Integrated

[8086.arith] ............................ PASS (256/256)
[8086.shift] .......................X.... FAIL (253/256)
  FAIL: SHL AL,0 - flags changed (expected 0x0002, got 0x0046)
[8086.string] ........................... PASS (128/128)

Summary: 637/640 passed, 3 failed, 0 skipped
```

### Limitations
- Scrolls away on long runs
- Can't capture programmatically from MiSTer
- Good for: quick sanity check, debugging single tests

### Usage
```
X86VAL.EXE /log:CON /verbose:2
```

---

## 3. Serial Output (Primary Method for MiSTer)

Serial is the **recommended method** for MiSTer ao486 development because:
- Real-time streaming to host
- Capturable and parseable
- Works even if video is broken
- Survives crashes (partial output captured)

### 3.1 MiSTer ao486 UART Setup

ao486 exposes UART to the MiSTer's USER I/O port directly:

```
USER I/O connector pinout:
  Pin 1: TX (ao486 → host)
  Pin 2: RX (host → ao486)  
  Pin 3: GND
  3.3V TTL levels
```

**Option A: USB-to-Serial adapter**
```bash
# Connect USB-serial adapter to USER I/O
# On MiSTer Linux or your PC:
screen /dev/ttyUSB0 115200
# or capture to file:
cat /dev/ttyUSB0 > ao486_test.log &
```

**Option B: MiSTer's built-in serial bridge**
ao486 MiSTer core can bridge UART to a TCP socket:

1. Edit `ao486.cfg` or use OSD:
   ```
   uart_mode=1  ; Enable UART bridge to Linux
   ```

2. On MiSTer Linux:
   ```bash
   # Serial appears as /dev/ttyS1 or similar
   cat /dev/ttyS1 > /media/fat/ao486_test.log &
   ```

3. Or via network from your dev machine:
   ```bash
   ssh root@mister "cat /dev/ttyS1" > ao486_test.log
   ```

### 3.2 Running Tests with Serial Output

In DOS on ao486:
```
X86VAL.EXE /log:COM1 /format:text /verbose:2
```

Or machine-readable:
```
X86VAL.EXE /log:COM1 /format:json
```

### 3.3 Serial Baud Rate

Default: **115200 8N1** (matches most ao486 setups)

To change (if needed):
```
X86VAL.EXE /log:COM1 /baud:9600
```

---

## 4. DOSBox-X Host Streaming

DOSBox-X can redirect serial output directly to the host — no USB adapter needed.

### 4.1 Serial to TCP Socket

In `dosbox-x.conf`:
```ini
[serial]
serial1=nullmodem server:127.0.0.1 port:5555
```

On host, before running DOSBox-X:
```bash
# Listen and capture
nc -l 5555 > test_output.log &
# Or real-time:
nc -l 5555 | tee test_output.log
```

Then in DOS:
```
X86VAL.EXE /log:COM1
```

### 4.2 Serial to File (Direct)

In `dosbox-x.conf`:
```ini
[serial]
serial1=file:test_output.txt
```

All COM1 output goes directly to `test_output.txt` on the host.

### 4.3 Console Capture

Redirect DOSBox-X console to file:
```bash
dosbox-x -c "mount c build/bin" -c "c:" -c "X86VAL.EXE" 2>&1 | tee console.log
```

### 4.4 Headless / Automated

Run without GUI:
```bash
# Use null video driver
SDL_VIDEODRIVER=dummy dosbox-x -conf ci.conf -c "X86VAL.EXE /log:COM1" -c "exit"
```

With `ci.conf`:
```ini
[sdl]
output=surface
fullscreen=false

[serial]
serial1=file:results.txt

[autoexec]
mount c build/bin
c:
X86VAL.EXE /log:COM1 /format:json
exit
```

---

## 5. 86Box Serial Capture

86Box also supports serial redirection (better PM/peripheral fidelity than DOSBox-X).

In 86Box settings:
- Serial Port 1 → "TCP server" or "Named pipe"

```bash
# TCP capture
nc localhost 8086 > 86box_results.log
```

---

## 6. File Output

Write results to disk for later transfer.

```
X86VAL.EXE /log:RESULTS.TXT /format:json
```

### 6.1 Retrieving from MiSTer

ao486 typically uses a VHD image mounted on the MiSTer's SD card:

```bash
# SSH into MiSTer
ssh root@mister

# Mount the ao486 VHD (if not auto-mounted)
mkdir -p /tmp/ao486
mount -o loop /media/fat/games/ao486/DOS.vhd /tmp/ao486

# Copy results
cp /tmp/ao486/RESULTS.TXT /media/fat/

# Or directly via network
scp root@mister:/tmp/ao486/RESULTS.TXT .
```

### 6.2 Network Share

MiSTer can expose shares via Samba. Copy results to a shared location for easy access.

---

## 7. Output Formats

### 7.1 Text (Human-Readable)

```
[8086.shift] SHL AL,CL with CL=0
  Case: AL=0x55, CL=0, FLAGS=0x0002
  Expected: AL=0x55, FLAGS=0x0002 (unchanged)
  Got:      AL=0x55, FLAGS=0x0046
  FAIL: flags changed on count=0 shift
```

### 7.2 JSON (Machine-Parseable)

```json
{
  "suite": "x86-validate",
  "version": "1.0",
  "timestamp": "1992-01-15T14:30:00",
  "cpu": "80486DX",
  "fpu": "integrated",
  "results": [
    {
      "module": "8086.shift",
      "test": "shl_al_cl_count0",
      "status": "FAIL",
      "expected": {"al": 85, "flags": 2},
      "actual": {"al": 85, "flags": 70},
      "message": "flags changed on count=0 shift"
    }
  ],
  "summary": {"pass": 637, "fail": 3, "skip": 0}
}
```

### 7.3 CSV (Spreadsheet)

```csv
module,test,status,expected,actual,message
8086.shift,shl_al_cl_count0,FAIL,"al=55 flags=0002","al=55 flags=0046","flags changed"
```

---

## 8. MiSTer Automation

### 8.1 Scripted Test Run

Create a shell script on MiSTer (`/media/fat/Scripts/run_ao486_tests.sh`):

```bash
#!/bin/bash
# Run ao486 validation suite and capture results

RESULTS=/media/fat/ao486_results_$(date +%Y%m%d_%H%M%S).json
VHD=/media/fat/games/ao486/DOS.vhd

# Start serial capture in background
cat /dev/ttyS1 > $RESULTS &
CAPTURE_PID=$!

# Launch ao486 core (via MiSTer command interface)
echo "load_core ao486" > /dev/MiSTer_cmd

# Wait for tests to complete (or timeout)
sleep 300  # 5 minute timeout

# Stop capture
kill $CAPTURE_PID 2>/dev/null

echo "Results saved to $RESULTS"
```

### 8.2 Remote Trigger via SSH

From your dev machine:
```bash
#!/bin/bash
# remote_test.sh - Run tests on MiSTer remotely

MISTER=root@mister
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# Start capture
ssh $MISTER "cat /dev/ttyS1 > /media/fat/results_$TIMESTAMP.json &"

# Boot ao486 and wait
ssh $MISTER "echo 'load_core ao486' > /dev/MiSTer_cmd"
echo "Waiting for tests (Ctrl+C to stop early)..."
sleep 300

# Retrieve results
scp $MISTER:/media/fat/results_$TIMESTAMP.json ./

# Parse and report
python3 tools/report.py results_$TIMESTAMP.json
```

### 8.3 Autoexec.bat Automation

On the ao486 DOS disk, edit `AUTOEXEC.BAT`:
```batch
@ECHO OFF
C:\TESTS\X86VAL.EXE /log:COM1 /format:json /verbose:1
REM Optional: signal completion
ECHO ===TEST_COMPLETE=== > COM1
```

This runs tests automatically on every boot.

### 8.4 Detecting Test Completion

Parse serial stream for completion marker:
```bash
# Wait for completion marker
timeout 300 grep -m 1 "===TEST_COMPLETE===" /dev/ttyS1

if [ $? -eq 0 ]; then
    echo "Tests completed successfully"
else
    echo "Timeout or error"
fi
```

---

## 9. CI/CD Integration

### 9.1 GitHub Actions with DOSBox-X

```yaml
name: x86 Validation Tests

on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      
      - name: Install DOSBox-X
        run: |
          sudo apt-get update
          sudo apt-get install -y dosbox-x
      
      - name: Build test suite
        run: make dos
      
      - name: Run tests
        run: |
          timeout 300 dosbox-x -conf ci/dosbox.conf \
            -c "mount c build/bin" \
            -c "c:" \
            -c "X86VAL.EXE /log:COM1 /format:json" \
            -c "exit" || true
      
      - name: Check results
        run: python3 tools/check_results.py results.json
      
      - name: Upload results
        uses: actions/upload-artifact@v3
        with:
          name: test-results
          path: results.json
```

### 9.2 Local CI Script

```bash
#!/bin/bash
# ci/run_tests.sh

set -e

echo "Building..."
make clean
make dos

echo "Running in DOSBox-X..."
SDL_VIDEODRIVER=dummy timeout 120 dosbox-x -conf ci/dosbox.conf

echo "Checking results..."
python3 tools/check_results.py ci/results.json

FAILURES=$(jq '.summary.fail' ci/results.json)
if [ "$FAILURES" -gt 0 ]; then
    echo "FAILED: $FAILURES test(s) failed"
    jq '.results[] | select(.status == "FAIL")' ci/results.json
    exit 1
fi

echo "PASSED: All tests passed"
```

---

## 10. Debugging Failed Tests

### 10.1 Verbose Mode

Get detailed per-case output:
```
X86VAL.EXE /log:COM1 /verbose:3 /module:8086.shift
```

Output includes:
- Input values
- Expected output
- Actual output
- Individual flag states
- Hex dumps where relevant

### 10.2 Single Test Mode

Run just one specific test:
```
X86VAL.EXE /test:8086.shift.shl_count0
```

### 10.3 Breakpoint on Failure

With DEBUG version (future):
```
X86VAL.EXE /break-on-fail
```
Halts and dumps registers when a test fails.

### 10.4 Comparing Results

```bash
# Generate reference on known-good emulator
dosbox-x ... > reference.json

# Run on ao486
... > ao486.json

# Diff
python3 tools/compare.py reference.json ao486.json
```

Output:
```
MISMATCH: 8086.shift.shl_count0
  86Box:  flags=0x0002 (correct)
  ao486:  flags=0x0046 (wrong - PF/ZF spuriously set)

MISMATCH: 8086.arith.inc_cf_preserve
  86Box:  CF=1 preserved
  ao486:  CF=0 (cleared - BUG)

Summary: 3 mismatches found
```

---

## 11. Quick Reference

### MiSTer ao486 (Recommended Setup)

```bash
# On MiSTer, start capture
ssh root@mister "cat /dev/ttyS1 | tee /media/fat/test.log" &

# Boot ao486, in DOS run:
X86VAL.EXE /log:COM1 /format:json

# Retrieve results
scp root@mister:/media/fat/test.log .
```

### DOSBox-X Development Loop

```bash
# dosbox-x.conf
[serial]
serial1=file:results.txt

# Run
make dos && dosbox-x -c "mount c build/bin" -c "c:" -c "X86VAL.EXE /log:COM1"

# Check
cat results.txt | jq '.summary'
```

### Full CI Pipeline

```bash
make dos linux           # Build both
make oracle              # Run Linux, generate expected values
./ci/run_tests.sh        # Run DOS in DOSBox-X, compare
```
