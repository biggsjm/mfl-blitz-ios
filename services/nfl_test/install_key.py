#!/usr/bin/env python3
"""Receive a key via SSH stdin, without echo, logs or command-line secrets."""
import os
from pathlib import Path
import sys

if sys.stdin.isatty():
    sys.exit("Requires a private piped input; do not type a key as a shell command.")
token = sys.stdin.read(513).strip()
if not token or len(token) > 512 or not token.isascii() or any(ord(c) < 33 or ord(c) > 126 for c in token):
    sys.exit("Invalid token; nothing saved.")
directory = Path.home() / ".config/mfl-nfl-test"
directory.mkdir(mode=0o700, parents=True, exist_ok=True)
os.chmod(directory, 0o700)
# Refuse an accidental replacement; rotation requires a separate explicit action.
fd = os.open(directory / "api-key", os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
with os.fdopen(fd, "w") as output:
    output.write(token)
print("Private key installed; value not displayed.")
