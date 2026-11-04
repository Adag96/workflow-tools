#!/bin/bash
# PYTHONDONTWRITEBYTECODE: never drop __pycache__ into the extension folder (Chrome refuses it)
PYTHONDONTWRITEBYTECODE=1 exec python3 -B "$(dirname "$0")/host.py"
