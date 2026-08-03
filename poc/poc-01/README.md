# POC-01: DOSBox-X UART Streaming

## Goal

Validate that we can run DOS executables inside DOSBox-X in fully non-interactive mode,
capture diagnostic output via serial port (UART), and implement bidirectional communication
for on-demand test execution.

This POC proves the foundation for automated CI/CD testing of x86 code without requiring
user interaction, display, or manual result collection.

---

## Success Criteria

| # | Criterion | Status |
|---|-----------|:------:|
| 1 | DOSBox-X runs headless without exit confirmation | PASS |
| 2 | DOS executable outputs to COM1 | PASS |
| 3 | Host captures serial output to file | PASS |
| 4 | Bidirectional serial works | PASS |
| 5 | Host can send commands, receive responses | PASS |
| 6 | Clean exit on completion | PASS |

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              HOST SYSTEM                                    │
│                                                                             │
│   ┌─────────────────────────────────────────────────────────────────────┐   │
│   │                          DOSBox-X                                   │   │
│   │                                                                     │   │
│   │   ┌─────────────────────────────────────────────────────────────┐   │   │
│   │   │                    DOS Environment                          │   │   │
│   │   │                                                             │   │   │
│   │   │   ┌─────────────┐         ┌─────────────┐                   │   │   │
│   │   │   │  push.com   │   OR    │ server.com  │                   │   │   │
│   │   │   │ (Scenario 1)│         │ (Scenario 2)│                   │   │   │
│   │   │   └──────┬──────┘         └──────┬──────┘                   │   │   │
│   │   │          │                       │                          │   │   │
│   │   │          │    COM1 (0x3F8)       │                          │   │   │
│   │   │          └───────────┬───────────┘                          │   │   │
│   │   │                      │                                      │   │   │
│   │   └──────────────────────┼──────────────────────────────────────┘   │   │
│   │                          │                                          │   │
│   │            ┌─────────────┴─────────────┐                            │   │
│   │            │      DOSBox-X Serial      │                            │   │
│   │            │        Emulation          │                            │   │
│   │            └─────────────┬─────────────┘                            │   │
│   │                          │                                          │   │
│   └──────────────────────────┼──────────────────────────────────────────┘   │
│                              │                                              │
│              ┌───────────────┴───────────────┐                              │
│              │                               │                              │
│     ┌────────▼────────┐           ┌──────────▼──────────┐                   │
│     │  serial1=file   │           │ serial1=nullmodem   │                   │
│     │  (Scenario 1)   │           │   (Scenario 2)      │                   │
│     │                 │           │                     │                   │
│     │  results.txt    │           │   TCP :5555         │                   │
│     └─────────────────┘           └──────────┬──────────┘                   │
│                                              │                              │
│                                   ┌──────────▼──────────┐                   │
│                                   │     client.py       │                   │
│                                   │   (host listener)   │                   │
│                                   └─────────────────────┘                   │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Scenario 1: Push Mode (DOS → Host)

One-way data flow: DOS runs tests and pushes results to serial port.
Host captures output to a file.

### Flow Diagram

```
┌──────────────────────────────────────────────────────────────────────────┐
│                            PUSH MODE FLOW                                │
├──────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  Host                           DOSBox-X / DOS                           │
│  ────                           ──────────────                           │
│                                                                          │
│  1. run_push.sh                                                          │
│        │                                                                 │
│        ├─────────────────────►  2. Start DOSBox-X                        │
│        │                           dosbox-x -conf dosbox-push.conf       │
│        │                                │                                │
│        │                                ▼                                │
│        │                        3. Mount drive, run push.com             │
│        │                                │                                │
│        │                                ▼                                │
│        │                        4. Initialize COM1 (115200 8N1)          │
│        │                                │                                │
│        │                                ▼                                │
│        │                        5. Run tests:                            │
│        │                           - CPU detection                       │
│        │                           - ADD overflow flags                  │
│        │                           - SUB overflow flags                  │
│        │                           - INC CF preservation                 │
│        │                                │                                │
│        │                                ▼                                │
│        │  ◄─────────────────────  6. Output JSON to COM1                 │
│        │   serial1=file:...            │                                 │
│        │                                ▼                                │
│        │                        7. Exit to DOS, DOSBox-X terminates      │
│        │                                                                 │
│        ▼                                                                 │
│  8. Read results_*.txt                                                   │
│                                                                          │
└──────────────────────────────────────────────────────────────────────────┘
```

### Sequence Diagram

```
     run_push.sh            DOSBox-X              push.com           results.txt
          │                     │                     │                    │
          │─────start──────────►│                     │                    │
          │                     │                     │                    │
          │                     │──────mount c:.─────►│                    │
          │                     │                     │                    │
          │                     │                     │──init COM1─────────┤
          │                     │                     │   115200 8N1       │
          │                     │                     │                    │
          │                     │                     │──run tests────────►│
          │                     │                     │   (JSON output)    │
          │                     │                     │                    │
          │                     │◄─────exit───────────│                    │
          │                     │                     │                    │
          │◄────terminate───────│                     │                    │
          │                     │                     │                    │
          │◄────────────────────────────────────────read─────────────────►│
          │                                                                │
```

### DOSBox-X Configuration (Scenario 1)

```ini
[serial]
serial1=file file:results.txt
```

- `serial1=file` - Use file output mode
- `file:results.txt` - Write all COM1 data to this file

### Output Location

All temporary files go to `scratch/` in the project root (gitignored):

```
x86-validation-suite/
├── scratch/                          # ← Output goes here
│   ├── poc01_results_20260803_*.txt  # Test results
│   └── dosbox-push-temp.conf         # Generated configs
└── poc/poc-01/                       # Source only
```

### Output Format (JSON)

```json
{"suite":"poc-01","version":"1.0","tests":[
{"test":"cpu_detect","cpu":"286+","status":"PASS"},
{"test":"add_overflow","status":"PASS","result":"0x80","flags":"0x7A92"},
{"test":"sub_overflow","status":"PASS","result":"0x7F","flags":"0x7A12"},
{"test":"inc_cf_preserve","status":"PASS"},
],"status":"complete"}
===END===
```

---

## Scenario 2: Interactive Mode (Host ↔ DOS)

Bidirectional communication: Host sends commands, DOS executes and responds.

### Flow Diagram

```
┌──────────────────────────────────────────────────────────────────────────┐
│                         INTERACTIVE MODE FLOW                            │
├──────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  Host (client.py)               DOSBox-X / DOS (server.com)              │
│  ────────────────               ───────────────────────────              │
│                                                                          │
│  1. client.py starts                                                     │
│     Listen on port 5555                                                  │
│        │                                                                 │
│        │     (waiting for connection)                                    │
│        │                                                                 │
│        │                        2. run_server.sh                         │
│        │                           Start DOSBox-X                        │
│        │                                │                                │
│        │                                ▼                                │
│        │                        3. Mount drive, run server.com           │
│        │                                │                                │
│        │                                ▼                                │
│        │◄───────TCP connect─────  4. Connect to host:5555                │
│        │                                │                                │
│        │◄───────"READY\r\n"─────  5. Send READY prompt                   │
│        │                                │                                │
│        │                                │     ┌───────────────────────┐  │
│        │────────"PING\r"───────►  6.    │     │   Command Loop:       │  │
│        │◄───────"PONG\r\n"──────        │     │                       │  │
│        │                                │     │   - Parse command     │  │
│        │────────"CPU\r"────────►        │     │   - Execute action    │  │
│        │◄───────"CPU: 286+\r\n"─        │     │   - Send response     │  │
│        │                                │     │   - Wait for next     │  │
│        │────────"TEST ADD\r"───►        │     │                       │  │
│        │◄───────"PASS...\r\n"───        │     └───────────────────────┘  │
│        │                                │                                │
│        │────────"QUIT\r"───────►  7. Exit command received               │
│        │◄───────"BYE\r\n"───────        │                                │
│        │                                ▼                                │
│        │     (connection closed)  8. Exit to DOS, DOSBox-X terminates    │
│        │                                                                 │
│        ▼                                                                 │
│  9. Print results, exit                                                  │
│                                                                          │
└──────────────────────────────────────────────────────────────────────────┘
```

### Sequence Diagram

```
    client.py           TCP :5555          DOSBox-X           server.com
         │                   │                  │                   │
         │───listen(:5555)──►│                  │                   │
         │                   │                  │                   │
         │                   │◄────start────────│                   │
         │                   │                  │                   │
         │                   │                  │───run server.com─►│
         │                   │                  │                   │
         │◄──────connect─────│◄─────────────────│◄──init COM1───────│
         │                   │                  │                   │
         │◄─────"READY"──────│◄─────────────────│◄──────────────────│
         │                   │                  │                   │
    ┌────┴────┐              │                  │                   │
    │ Command │              │                  │                   │
    │  Loop   │              │                  │                   │
    └────┬────┘              │                  │                   │
         │                   │                  │                   │
         │─────"PING\r"─────►│─────────────────►│─────────────────►│
         │                   │                  │                   │──┐
         │                   │                  │                   │  │ parse
         │                   │                  │                   │◄─┘
         │◄────"PONG\r\n"────│◄─────────────────│◄─────────────────│
         │                   │                  │                   │
         │─────"CPU\r"──────►│─────────────────►│─────────────────►│
         │◄───"CPU: 286+"────│◄─────────────────│◄─────────────────│
         │                   │                  │                   │
         │───"TEST ADD\r"───►│─────────────────►│─────────────────►│
         │                   │                  │                   │──┐
         │                   │                  │                   │  │ run test
         │                   │                  │                   │◄─┘
         │◄────"PASS..."─────│◄─────────────────│◄─────────────────│
         │                   │                  │                   │
         │─────"QUIT\r"─────►│─────────────────►│─────────────────►│
         │◄─────"BYE"────────│◄─────────────────│◄─────────────────│
         │                   │                  │                   │
         │      (close)      │◄────exit─────────│◄─────────────────│
         │                   │                  │                   │
```

### DOSBox-X Configuration (Scenario 2)

```ini
[serial]
serial1=nullmodem server:127.0.0.1 port:5555 transparent:1
```

- `serial1=nullmodem` - Use null modem (TCP) mode
- `server:127.0.0.1` - Connect to this host (DOSBox as client)
- `port:5555` - TCP port number
- `transparent:1` - Disable modem AT commands

### Command Protocol

| Command | Response | Description |
|---------|----------|-------------|
| `PING` | `PONG` | Connection test |
| `CPU` | `CPU: 8086` or `CPU: 80286+` | Detect CPU type |
| `TEST ADD` | `ADD overflow: PASS/FAIL` + flags | Run ADD overflow test |
| `TEST SUB` | `SUB overflow: PASS/FAIL` + flags | Run SUB overflow test |
| `TEST INC` | `INC CF preserve: PASS/FAIL` | Run INC CF test |
| `QUIT` | `BYE` | Exit server |

---

## Implementation Details

### Serial Port Programming (DOS side)

Both executables configure COM1 at I/O base `0x3F8`:

```
┌─────────────────────────────────────────────────────────────┐
│                    COM1 Register Map                        │
├──────────┬───────────┬──────────────────────────────────────┤
│  Offset  │  Register │  Usage                               │
├──────────┼───────────┼──────────────────────────────────────┤
│  0x3F8   │  THR/RBR  │  Transmit/Receive data (DLAB=0)      │
│  0x3F8   │  DLL      │  Divisor Latch Low (DLAB=1)          │
│  0x3F9   │  IER      │  Interrupt Enable (DLAB=0)           │
│  0x3F9   │  DLH      │  Divisor Latch High (DLAB=1)         │
│  0x3FB   │  LCR      │  Line Control (8N1 + DLAB access)    │
│  0x3FC   │  MCR      │  Modem Control (DTR + RTS)           │
│  0x3FD   │  LSR      │  Line Status (TX/RX ready)           │
└──────────┴───────────┴──────────────────────────────────────┘
```

### Initialization Sequence

```asm
; 1. Set DLAB to access divisor
mov dx, 0x3FB       ; LCR
mov al, 0x80        ; DLAB=1
out dx, al

; 2. Set baud rate (115200 = divisor 1)
mov dx, 0x3F8       ; DLL
mov al, 1
out dx, al
mov dx, 0x3F9       ; DLH
xor al, al
out dx, al

; 3. Set 8N1, clear DLAB
mov dx, 0x3FB       ; LCR
mov al, 0x03        ; 8 bits, no parity, 1 stop
out dx, al

; 4. Enable DTR, RTS
mov dx, 0x3FC       ; MCR
mov al, 0x03
out dx, al
```

### Transmit Byte

```asm
uart_putc:
    ; Wait for THR empty
.wait:
    mov dx, 0x3FD   ; LSR
    in al, dx
    test al, 0x20   ; Bit 5 = THR empty
    jz .wait
    
    ; Send byte
    mov dx, 0x3F8   ; THR
    mov al, [char]
    out dx, al
    ret
```

### Receive Byte

```asm
uart_getc:
    ; Wait for data ready
.wait:
    mov dx, 0x3FD   ; LSR
    in al, dx
    test al, 0x01   ; Bit 0 = data ready
    jz .wait
    
    ; Read byte
    mov dx, 0x3F8   ; RBR
    in al, dx
    ret
```

---

## Building

### Prerequisites

| Tool | Version | Install (macOS) | Install (Linux) |
|------|---------|-----------------|-----------------|
| NASM | 2.x+ | `brew install nasm` | `apt install nasm` |
| DOSBox-X | 2024+ | `brew install dosbox-x` | `apt install dosbox-x` |
| Python | 3.x | (built-in) | `apt install python3` |

### Build Commands

```bash
cd poc/poc-01

# Build both executables
make

# Build individually
make push.com
make server.com

# Clean
make clean
```

### Build Output

```
poc-01/
├── push.com      # 649 bytes - push mode executable
└── server.com    # 852 bytes - server mode executable
```

---

## Running

### Scenario 1: Push Mode (Quick Test)

Single command, fully automated:

```bash
cd poc/poc-01
./run_push.sh
```

Headless (CI mode):
```bash
SDL_VIDEODRIVER=dummy ./run_push.sh
```

Expected output:
```
=== POC-01: Push Mode ===
Starting DOSBox-X with serial output...

Running tests...

=== Results (poc01_results_20260803_110706.txt) ===
{"suite":"poc-01","version":"1.0","tests":[
{"test":"cpu_detect","cpu":"286+","status":"PASS"},
{"test":"add_overflow","status":"PASS","result":"0x80","flags":"0x7A92"},
{"test":"sub_overflow","status":"PASS","result":"0x7F","flags":"0x7A12"},
{"test":"inc_cf_preserve","status":"PASS"},
],"status":"complete"}
===END===
Success: Serial output captured!
```

### Scenario 2: Interactive Mode

**Terminal 1** - Start client (listener) first:
```bash
./client.py
```

**Terminal 2** - Start DOSBox-X:
```bash
./run_server.sh
```

Interactive session in Terminal 1:
```
Listening on 127.0.0.1:5555...
Start DOSBox-X with: ./run_server.sh (in another terminal)

Waiting for DOSBox-X to connect...
Connected from ('127.0.0.1', 53393)
Commands: PING, CPU, TEST ADD, TEST SUB, TEST INC, QUIT
Press Ctrl+C to disconnect

READY
> PING
PONG
> CPU
CPU: 80286+
> TEST ADD
ADD overflow: PASS (0x7F+0x01=0x80, OF=1)
FLAGS=0x7A92
> QUIT
BYE
Disconnected.
```

### Scenario 2: Batch Mode

Run commands non-interactively:

```bash
# Start listener with commands
./client.py "PING" "CPU" "TEST ADD" "QUIT" &

# Then in another terminal (or after a delay)
SDL_VIDEODRIVER=dummy ./run_server.sh
```

---

## File Reference

| File | Lines | Purpose |
|------|------:|---------|
| `push.asm` | ~250 | Push mode: init COM1, run tests, output JSON |
| `server.asm` | ~350 | Server mode: command parser, test execution |
| `dosbox-push.conf` | ~25 | Config for push mode (serial1=file) |
| `dosbox-server.conf` | ~25 | Config for server mode (serial1=nullmodem) |
| `run_push.sh` | ~60 | Launch script for push mode |
| `run_server.sh` | ~40 | Launch script for server mode |
| `client.py` | ~150 | Python client: interactive + batch modes |
| `Makefile` | ~15 | Build system |

---

## Tests Implemented

| Test | Input | Expected | Pass Condition |
|------|-------|----------|----------------|
| `cpu_detect` | FLAGS bits 12-15 | 8086: all set, 286+: cleared | Correctly identifies CPU |
| `add_overflow` | 0x7F + 0x01 | 0x80, OF=1, SF=1 | Result and flags match |
| `sub_overflow` | 0x80 - 0x01 | 0x7F, OF=1 | Signed overflow detected |
| `inc_cf_preserve` | CF=1, then INC 0xFF | CF=1 (unchanged) | INC doesn't affect CF |

---

## Troubleshooting

### "dosbox-x not found"

Install DOSBox-X (not regular DOSBox):
```bash
# macOS
brew install dosbox-x

# Linux
apt install dosbox-x
# or build from https://github.com/joncampbell123/dosbox-x
```

### "Address already in use" (port 5555)

Another process is using the port:
```bash
# Find and kill
lsof -i :5555
kill <PID>
```

### No output in push mode

1. Check `results_*.txt` exists
2. Verify `push.com` was built: `make clean && make`
3. Run without SDL_VIDEODRIVER to see DOS screen

### Exit warning dialog appears

Ensure config has:
```ini
[dosbox]
quit warning=false
```

### Connection timeout in server mode

1. Start `client.py` FIRST (it must be listening)
2. Then run `./run_server.sh`
3. DOSBox-X connects to the client, not vice versa

---

## Next Steps

1. **Extend to MiSTer**: Same serial protocol works with real UART hardware
2. **Add more tests**: Full CPU instruction coverage
3. **CI integration**: GitHub Actions workflow
4. **Result comparison**: Tool to diff between emulators
5. **Production framework**: Integrate this approach into main test suite
