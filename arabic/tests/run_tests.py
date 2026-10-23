#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Offline tests for the Arabic integration (no game assets or network required).

- test_native_patch: the Windfall door patches in platforms/uwp-game/prepare_game.py — encodings,
  application into the analyzed program, idempotency, and verification of the translated output.
- test_pack_parsers: SARC/Yaz0/BFFNT parsing and the activation rule, against synthetic fixtures
  (arabic/verify_pack.py).
- test_stage_mod: staging (Method A) and overlay (Method B), including the .asm exclusion.
- test_fetch_meta: the pinned download metadata.
"""
import sys
import unittest
from pathlib import Path

HERE = Path(__file__).parent
sys.path.insert(0, str(HERE))
sys.path.insert(0, str(HERE.parent))

import test_native_patch  # noqa: E402,F401
import test_pack_parsers  # noqa: E402,F401
import test_stage_mod  # noqa: E402,F401
import test_fetch_meta  # noqa: E402,F401

if __name__ == "__main__":
    loader = unittest.TestLoader()
    suite = unittest.TestSuite()
    for module in (test_native_patch, test_pack_parsers, test_stage_mod, test_fetch_meta):
        suite.addTests(loader.loadTestsFromModule(module))
    result = unittest.TextTestRunner(verbosity=2).run(suite)
    sys.exit(0 if result.wasSuccessful() else 1)
