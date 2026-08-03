#!/usr/bin/env python3
"""
POC-01: Interactive client for server mode.
Acts as TCP server - DOSBox-X connects to us.
"""

import socket
import sys
import select
import threading
import time

HOST = '127.0.0.1'
PORT = 5555
TIMEOUT = 30.0

def receive_thread(sock, stop_event):
    """Background thread to receive and print data from DOS server."""
    sock.setblocking(False)
    while not stop_event.is_set():
        try:
            ready = select.select([sock], [], [], 0.1)
            if ready[0]:
                data = sock.recv(1024)
                if not data:
                    print("\n[Connection closed by DOS]")
                    stop_event.set()
                    break
                text = data.decode('ascii', errors='replace')
                sys.stdout.write(text)
                sys.stdout.flush()
        except BlockingIOError:
            pass
        except Exception as e:
            if not stop_event.is_set():
                print(f"\n[Receive error: {e}]")
            break

def interactive_mode():
    """Interactive mode - wait for connection, then allow typing commands."""
    print(f"Listening on {HOST}:{PORT}...")
    print("Start DOSBox-X with: ./run_server.sh (in another terminal)")
    print("")

    server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)

    try:
        server.bind((HOST, PORT))
        server.listen(1)
        server.settimeout(TIMEOUT)

        print("Waiting for DOSBox-X to connect...")
        conn, addr = server.accept()
        print(f"Connected from {addr}")
        print("Commands: PING, CPU, TEST ADD, TEST SUB, TEST INC, QUIT")
        print("Press Ctrl+C to disconnect")
        print("")

    except socket.timeout:
        print("ERROR: Timeout waiting for connection")
        print("Make sure to start DOSBox-X: ./run_server.sh")
        sys.exit(1)
    except OSError as e:
        print(f"ERROR: {e}")
        if "Address already in use" in str(e):
            print("Port 5555 is already in use. Kill other processes first.")
        sys.exit(1)

    # Start receive thread
    stop_event = threading.Event()
    recv_thread = threading.Thread(target=receive_thread, args=(conn, stop_event))
    recv_thread.daemon = True
    recv_thread.start()

    # Wait for READY prompt
    time.sleep(1)

    try:
        while not stop_event.is_set():
            try:
                line = input()
                if stop_event.is_set():
                    break
                conn.send((line + '\r').encode('ascii'))
                time.sleep(0.1)
            except EOFError:
                break

    except KeyboardInterrupt:
        print("\n[Disconnecting...]")
    finally:
        stop_event.set()
        conn.close()
        server.close()
        recv_thread.join(timeout=1.0)
        print("Disconnected.")

def batch_mode(commands):
    """Run a list of commands non-interactively."""
    print(f"Listening on {HOST}:{PORT} for DOSBox-X connection...")

    server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)

    try:
        server.bind((HOST, PORT))
        server.listen(1)
        server.settimeout(TIMEOUT)
        conn, addr = server.accept()
        print(f"Connected from {addr}")
    except socket.timeout:
        print("ERROR: Timeout waiting for connection")
        sys.exit(1)
    except Exception as e:
        print(f"ERROR: {e}")
        sys.exit(1)

    results = []

    try:
        # Wait for READY
        time.sleep(1)
        conn.settimeout(2)
        try:
            ready = conn.recv(1024)
            print(f"<<< {ready.decode('ascii', errors='replace').strip()}")
        except socket.timeout:
            pass

        for cmd in commands:
            print(f">>> {cmd}")
            conn.send((cmd + '\r').encode('ascii'))
            time.sleep(0.3)

            # Read response
            response = b''
            conn.setblocking(False)
            deadline = time.time() + 1.0
            while time.time() < deadline:
                try:
                    ready = select.select([conn], [], [], 0.1)
                    if ready[0]:
                        chunk = conn.recv(1024)
                        if not chunk:
                            break
                        response += chunk
                        deadline = time.time() + 0.3  # Extend on activity
                except:
                    break

            text = response.decode('ascii', errors='replace')
            for line in text.strip().split('\n'):
                if line.strip():
                    print(f"<<< {line.strip()}")
            results.append((cmd, text))

    finally:
        conn.close()
        server.close()

    return results

if __name__ == '__main__':
    if len(sys.argv) > 1:
        # Batch mode: run commands from arguments
        commands = sys.argv[1:]
        batch_mode(commands)
    else:
        # Interactive mode
        interactive_mode()
