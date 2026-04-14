from __future__ import annotations

import os
import sys
from pathlib import Path


WORKSPACE_ROOT = Path(__file__).resolve().parents[2]
WORKER_ROOT = WORKSPACE_ROOT / "reigh-worker"
WORKER_SCRIPT = WORKSPACE_ROOT / "reigh-worker" / "scripts" / "preview" / "run_preview.py"
FALLBACK_PYTHON = "/usr/local/bin/python3.12"


def _exec_target(python_executable: str) -> "NoReturn":
    os.chdir(WORKER_ROOT)
    os.execv(python_executable, [python_executable, str(WORKER_SCRIPT), *sys.argv[1:]])


def main() -> "NoReturn":
    if not WORKER_SCRIPT.exists():
        raise SystemExit(f"Preview runner not found: {WORKER_SCRIPT}")

    current = Path(sys.executable).resolve()
    fallback = Path(FALLBACK_PYTHON)
    if sys.version_info < (3, 10) and fallback.exists() and current != fallback.resolve():
        _exec_target(str(fallback))

    _exec_target(sys.executable)


if __name__ == "__main__":
    main()
