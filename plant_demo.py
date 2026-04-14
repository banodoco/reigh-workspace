#!/usr/bin/env python3
"""Run this in a real terminal: python3 plant_demo.py"""

import time, sys, os

if os.name == "nt":
    os.system("")

# 12 rows for the plant area. Ground at row 11 (very bottom).
# Text spread across rows 2, 6, 10.

STAGES = [
    # (frame_data, delay_seconds)
    # Matches _PLANT_STAGES in reigh-worker/source/runtime/worker/status_display.py

    # --- Spring (slow, quiet) ---
    (["       ", "       ", "       ", "       ", "       ", "       ", "       ", "       ", "       ", "       ", "       ", "  ▔▔▔  "], 6),
    (["       ", "       ", "       ", "       ", "       ", "       ", "       ", "       ", "       ", "       ", "   .   ", "  ▔▔▔  "], 5),
    (["       ", "       ", "       ", "       ", "       ", "       ", "       ", "       ", "       ", "       ", "   |   ", "  ▔▔▔  "], 4),
    (["       ", "       ", "       ", "       ", "       ", "       ", "       ", "       ", "       ", "  ,|,  ", "   |   ", "  ▔▔▔  "], 4),
    (["       ", "       ", "       ", "       ", "       ", "       ", "       ", "       ", "   |   ", "  ,|,  ", "   |   ", "  ▔▔▔  "], 3),
    (["       ", "       ", "       ", "       ", "       ", "       ", "       ", "   |   ", "   |   ", " ,,|,, ", "   |   ", "  ▔▔▔  "], 3),
    # --- Growing (picking up pace) ---
    (["       ", "       ", "       ", "       ", "       ", "       ", "   |   ", "   |   ", "   |   ", " ,,|,, ", "   |   ", "  ▔▔▔  "], 2),
    (["       ", "       ", "       ", "       ", "       ", "   |   ", "   |   ", "   |   ", "   |   ", " ,,|,, ", "   |   ", "  ▔▔▔  "], 2),
    # --- Bud (slows for anticipation) ---
    (["       ", "       ", "       ", "       ", "   .   ", "   |   ", "   |   ", "   |   ", "   |   ", " ,,|,, ", "   |   ", "  ▔▔▔  "], 4),
    (["       ", "       ", "       ", "       ", "  (.)  ", "   |   ", "   |   ", "   |   ", "   |   ", " ,,|,, ", "   |   ", "  ▔▔▔  "], 4),
    # --- Bloom (medium pace) ---
    (["       ", "       ", "       ", "       ", "  {o}  ", "   |   ", "   |   ", "   |   ", "   |   ", " ,,|,, ", "   |   ", "  ▔▔▔  "], 3),
    (["       ", "       ", "       ", "       ", " -{O}- ", "   |   ", "   |   ", "   |   ", "   |   ", " ,,|,, ", "   |   ", "  ▔▔▔  "], 3),
    (["       ", "       ", "       ", "  \\=/  ", " -{O}- ", "  /=\\  ", "   |   ", "   |   ", "   |   ", " ,,|,, ", "   |   ", "  ▔▔▔  "], 5),
    (["       ", "       ", "       ", "  \\=/  ", " -{O}- ", "  /=\\  ", "   |   ", "   |   ", "   |   ", " ,,|,, ", "   |   ", "  ▔▔▔  "], 5),
    # --- Fading (slow, wistful) ---
    (["       ", "       ", "       ", "       ", " -{o}- ", "  /=\\  ", "   |   ", "   |   ", "   |   ", " ,,|,, ", "   |   ", "  ▔▔▔  "], 4),
    (["       ", "       ", "       ", "       ", "  {o}  ", "   |   ", "   |   ", "   |   ", "   |   ", " ,,|,, ", "   |   ", "  ▔▔▔  "], 3),
    (["       ", "       ", "       ", "       ", "  :o:  ", "   |   ", "   |   ", "   |   ", "   |   ", " ,,|,, ", "   |   ", "  ▔▔▔  "], 3),
    # --- Seed head (slow build) ---
    (["       ", "       ", "       ", "   :   ", "  :O:  ", "   :   ", "   |   ", "   |   ", "   |   ", " ,,|,, ", "   |   ", "  ▔▔▔  "], 4),
    (["       ", "       ", "       ", "  .:.  ", "  :O:  ", "  ':'  ", "   |   ", "   |   ", "   |   ", " ,,|,, ", "   |   ", "  ▔▔▔  "], 5),
    (["       ", "       ", "       ", "  .:.  ", "  :O:  ", "  ':'  ", "   |   ", "   |   ", "   |   ", " ,,|,, ", "   |   ", "  ▔▔▔  "], 6),
    # --- Wind! (fast burst) ---
    (["       ", "       ", "    .  ", "  .: . ", "  :O:  ", "  ':'  ", "   |   ", "   |   ", "   |   ", " ,,|,, ", "   |   ", "  ▔▔▔  "], 1),
    (["       ", "    . .", "      .", "   :   ", "  :o:  ", "   :   ", "   |   ", "   |   ", "   |   ", " ,,|,, ", "   |   ", "  ▔▔▔  "], 1),
    (["    . .", "      .", "       ", "       ", "   o   ", "   :   ", "   |   ", "   |   ", "   |   ", " ,,|,, ", "   |   ", "  ▔▔▔  "], 1),
    (["      .", "       ", "       ", "       ", "   .   ", "   |   ", "   |   ", "   |   ", "   |   ", " ,,|,, ", "   |   ", "  ▔▔▔  "], 2),
    # --- Autumn (slowing down) ---
    (["       ", "       ", "       ", "       ", "       ", "   |   ", "   |   ", "   |   ", "   |   ", " ,,|,, ", "   |   ", "  ▔▔▔  "], 3),
    (["       ", "       ", "       ", "       ", "       ", "       ", "   |   ", "   |   ", "   |   ", " ,.|., ", "   |   ", "  ▔▔▔  "], 4),
    (["       ", "       ", "       ", "       ", "       ", "       ", "       ", "   |   ", "   |   ", "  .|.  ", "   |   ", "  ▔▔▔  "], 5),
    (["       ", "       ", "       ", "       ", "       ", "       ", "       ", "       ", "   |   ", "   |   ", "   |   ", "  ▔▔▔  "], 4),
    # --- Winter (very slow, still) ---
    (["       ", "       ", "       ", "       ", "       ", "       ", "       ", "       ", "       ", "       ", "   |   ", "  ▔▔▔  "], 6),
    (["       ", "       ", "       ", "       ", "       ", "       ", "       ", "       ", "       ", "       ", "   .   ", "  ▔▔▔  "], 6),
    (["       ", "       ", "       ", "       ", "       ", "       ", "       ", "       ", "       ", "       ", "       ", "  ▔▔▔  "], 8),
]

DOTS = ["GPU free · waiting for tasks   ", "GPU free · waiting for tasks.  ", "GPU free · waiting for tasks.. ", "GPU free · waiting for tasks..."]

HEIGHT = 15  # 12 plant rows + 3 blank below
UP = f"\033[{HEIGHT}A"
CLEAR = "\033[K"

gpu = "NVIDIA GeForce RTX 5090"
profile = "Balanced"

print()
print("\n" * HEIGHT, end="")

tick = 0
start = time.time()

try:
    while True:
        stage, delay = STAGES[tick % len(STAGES)]
        dots = DOTS[tick % len(DOTS)]

        elapsed = time.time() - start
        h, m = int(elapsed // 3600), int((elapsed % 3600) // 60)
        uptime = f"{h}h {m}m" if h > 0 else f"{m}m"

        info = {
            2: gpu,
            6: f"{profile}  ·  {uptime} up  ·  0 tasks",
            10: dots,
        }

        sys.stdout.write(UP)
        for row in range(12):
            sys.stdout.write(f"  {info.get(row, ''):<43s}{stage[row]}{CLEAR}\n")
        sys.stdout.write(f"{CLEAR}\n")
        sys.stdout.write(f"{CLEAR}\n")
        sys.stdout.write(f"{CLEAR}\n")
        sys.stdout.flush()

        tick += 1
        time.sleep(delay)
except KeyboardInterrupt:
    print("\n")
