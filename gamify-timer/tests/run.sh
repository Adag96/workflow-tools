#!/bin/bash
# Run the Gamify Timer tests without writing __pycache__ (Chrome refuses to load an
# unpacked extension containing any "_"-prefixed file or folder).
cd "$(dirname "$0")/.." && PYTHONDONTWRITEBYTECODE=1 exec python3 -B tests/test_engine.py "$@"
