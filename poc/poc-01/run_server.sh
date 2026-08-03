#!/bin/bash
# POC-01: Run server mode
# Starts DOSBox-X which connects to host listener
# Start client.py FIRST, then run this script

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

# Build if needed
if [ ! -f server.com ]; then
    echo "Building server.com..."
    make server.com
fi

# Check for dosbox-x
DOSBOX=$(command -v dosbox-x 2>/dev/null || echo "")
if [ -z "$DOSBOX" ]; then
    echo "ERROR: dosbox-x not found in PATH"
    echo "Install with: brew install dosbox-x (macOS) or apt install dosbox-x (Linux)"
    exit 1
fi

echo "=== POC-01: Server Mode ==="
echo ""
echo "IMPORTANT: Start client.py FIRST in another terminal!"
echo ""
echo "  Terminal 1: ./client.py"
echo "  Terminal 2: ./run_server.sh  (this script)"
echo ""
echo "DOSBox-X will connect to the client on port 5555."
echo "Commands: PING, CPU, TEST ADD, TEST SUB, TEST INC, QUIT"
echo ""
echo "Press Enter to continue (or Ctrl+C to cancel)..."
read -r

# Run DOSBox-X
"$DOSBOX" -conf dosbox-server.conf

echo "Server stopped."
