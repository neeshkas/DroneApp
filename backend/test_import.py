#!/usr/bin/env python
import sys

print(f"Python: {sys.executable}")
print(f"Path: {sys.path}")

try:
    from main import app

    print("OK: imported app from main.py")
except Exception as exc:
    print(f"ERROR: {exc}")
    raise
