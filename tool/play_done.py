#!/usr/bin/env python3
"""Play a short chime when a Linux build finishes."""

import math
import os
import struct
import subprocess
import sys
import tempfile
import wave


def write_wav(path: str) -> None:
    rate = 22050
    notes = ((880, 0.12), (1174, 0.18))
    frames = []
    for freq, duration in notes:
        count = int(rate * duration)
        for index in range(count):
            elapsed = index / rate
            attack = min(1.0, index / (rate * 0.01))
            release = min(1.0, (count - index) / (rate * 0.03))
            sample = int(16000 * attack * release * math.sin(2 * math.pi * freq * elapsed))
            frames.append(struct.pack("<h", sample))
        frames.extend([struct.pack("<h", 0)] * int(rate * 0.04))
    with wave.open(path, "w") as handle:
        handle.setnchannels(1)
        handle.setsampwidth(2)
        handle.setframerate(rate)
        handle.writeframes(b"".join(frames))


def main() -> None:
    path = os.path.join(tempfile.gettempdir(), "change_gui_build_done.wav")
    write_wav(path)
    players = (
        ["paplay", path],
        ["pw-play", path],
        ["aplay", "-q", path],
        ["ffplay", "-nodisp", "-autoexit", "-loglevel", "quiet", path],
    )
    for command in players:
        try:
            subprocess.run(
                command,
                check=True,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
            return
        except (FileNotFoundError, subprocess.CalledProcessError):
            continue
    sys.stdout.write("\a")
    sys.stdout.flush()


if __name__ == "__main__":
    main()
