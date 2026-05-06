#!/usr/bin/env python3
"""Workspace-root wrapper for the Sprint 3 dual-run comparison harness."""

from __future__ import annotations

import sys
from pathlib import Path


WORKSPACE_ROOT = Path(__file__).resolve().parents[1]
WORKER_ROOT = WORKSPACE_ROOT / "reigh-worker"


def _prepend_worker_root() -> None:
    worker_root = str(WORKER_ROOT)
    if sys.path[:1] != [worker_root]:
        sys.path = [entry for entry in sys.path if entry != worker_root]
        sys.path.insert(0, worker_root)


def main() -> int:
    _prepend_worker_root()
    from scripts.dual_run_compare.dual_run_compare import main as worker_main

    return worker_main()


if __name__ == "__main__":
    raise SystemExit(main())
