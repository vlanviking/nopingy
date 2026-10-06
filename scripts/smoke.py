#!/usr/bin/env python3
"""Live network verification using loopback and a temporary local TCP listener."""
import pathlib
import socket
import subprocess
import sys
import threading

binary = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else "dist/nopingy.app/Contents/MacOS/nopingy").resolve()

def probe(target, expected):
    result = subprocess.run([str(binary), "--probe", target], text=True, capture_output=True, timeout=55)
    print(f"{target}: {result.stdout.strip()}")
    assert result.stdout.startswith(expected + "\t"), (target, result.stdout, result.stderr)
    assert result.returncode == (0 if expected == "up" else 1)

def serve(listener):
    try:
        client, _ = listener.accept()
        client.close()
    except OSError:
        pass

for address, family in [("127.0.0.1", socket.AF_INET), ("::1", socket.AF_INET6)]:
    probe(address, "up")
    with socket.socket(family, socket.SOCK_STREAM) as listener:
        listener.bind((address, 0))
        port = listener.getsockname()[1]
        listener.listen(1)
        thread = threading.Thread(target=serve, args=(listener,), daemon=True)
        thread.start()
        target = f"[{address}]:{port}" if family == socket.AF_INET6 else f"{address}:{port}"
        probe(target, "up")
        thread.join(timeout=2)
    probe(target, "down")

probe("D/example.com", "up")
probe("T/127.0.0.1", "up")
invalid = subprocess.run([str(binary), "--probe", "--help"], text=True, capture_output=True, timeout=5)
assert invalid.returncode == 2 and "Invalid target" in invalid.stdout
print("All 9 live network checks passed.")
