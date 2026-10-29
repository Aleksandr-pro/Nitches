#!/usr/bin/env python3
"""Native 0.2.44: generate the park foliage-rustle ambience loop.

This is a supplemental *foley* bed in the same documented family as
the 0.2.42 wind/road layers (see docs/AUDIO_CREDITS.md): synthesized
filtered noise, never an engine or tyre voice.  The runtime plays it
at barely-audible level, gated by the measured foliage density
around the car, so parks and palm rows acquire a faint living
background that city streets do not have.

Recipe (deterministic, seeded):
- Two decorrelated stereo noise fields shaped into a leaf band
  (~350 Hz-6.5 kHz) with an extra shimmer band (~1.4-8 kHz).
- A strictly periodic low-frequency gust envelope (sum of sines over
  the loop length) breathes the bed between 45% and 100%.
- Hundreds of short high-passed "leaf tick" bursts (4-18 ms) whose
  density follows the same gust envelope, panned randomly.
- The final loop is made seamless by rendering 10 s and crossfading
  the last 2 s into the first 2 s (8 s result).

Output: src/assets/audio/vehicle_foley/foliage_rustle.wav
        (stereo WAV, 32 kHz, 16-bit) + foley_manifest.json entry.
"""
from __future__ import annotations

import json
from pathlib import Path

import numpy as np
import soundfile as sf
from scipy.signal import butter, sosfilt

SR = 32000
RENDER_SECONDS = 10.0
LOOP_SECONDS = 8.0
SEED = 20241029
OUT_DIR = Path(__file__).resolve().parent.parent / "src" / "assets" / "audio" / "vehicle_foley"
OUT_FILE = OUT_DIR / "foliage_rustle.wav"
MANIFEST_FILE = OUT_DIR / "foley_manifest.json"


def _bandpass(x: np.ndarray, low: float, high: float, order: int = 4) -> np.ndarray:
    sos = butter(order, [low, high], btype="bandpass", fs=SR, output="sos")
    return sosfilt(sos, x)


def _periodic_gust(n: int, seconds: float, rng: np.random.Generator) -> np.ndarray:
    """Slow 0..1 gust envelope that is periodic over the render."""
    t = np.arange(n) / SR
    env = np.zeros(n)
    for k in range(1, 7):
        freq = k / seconds * float(rng.integers(1, 4))
        phase = rng.uniform(0.0, 2.0 * np.pi)
        env += (1.0 / k) * np.sin(2.0 * np.pi * freq * t + phase)
    env -= env.min()
    env /= max(env.max(), 1e-9)
    return 0.45 + 0.55 * env


def _leaf_ticks(n: int, gust: np.ndarray, rng: np.random.Generator) -> np.ndarray:
    """Stereo field of very short filtered bursts, density ~ gust."""
    out = np.zeros((n, 2))
    # Candidate onsets every ~7 ms; keep with probability gust * 0.5.
    step = int(0.007 * SR)
    for start in range(0, n - int(0.03 * SR), step):
        if rng.random() > gust[start] * 0.5:
            continue
        length = int(rng.uniform(0.004, 0.018) * SR)
        burst = rng.standard_normal(length) * np.hanning(length)
        burst = _bandpass(burst, float(rng.uniform(1800.0, 3200.0)), 9500.0, order=2)
        amp = float(rng.uniform(0.05, 0.30)) * gust[start]
        pan = float(rng.uniform(0.0, 1.0))
        out[start : start + length, 0] += burst * amp * np.sqrt(1.0 - pan)
        out[start : start + length, 1] += burst * amp * np.sqrt(pan)
    return out


def _seamless(x: np.ndarray, loop_seconds: float) -> np.ndarray:
    keep = int(loop_seconds * SR)
    fade = x.shape[0] - keep
    if fade <= 0:
        return x[:keep]
    ramp = np.linspace(0.0, 1.0, fade, endpoint=False)[:, None]
    head = x[:fade] * (1.0 - ramp) + x[keep:] * ramp
    return np.vstack([head, x[fade:keep]])


def main() -> None:
    rng = np.random.default_rng(SEED)
    n = int(RENDER_SECONDS * SR)
    gust = _periodic_gust(n, RENDER_SECONDS, rng)

    bed = np.zeros((n, 2))
    for ch in range(2):
        noise = rng.standard_normal(n)
        main_band = _bandpass(noise, 350.0, 6500.0)
        shimmer = _bandpass(noise, 1400.0, 8000.0)
        channel = main_band * 0.75 + shimmer * 0.45
        # Double-modulate: slow gust plus a faster shiver so the bed
        # never sounds like steady filtered noise.
        shiver = 0.82 + 0.18 * _bandpass(rng.standard_normal(n), 2.0, 9.0)
        bed[:, ch] = channel * gust * shiver

    mix = bed + _leaf_ticks(n, gust, rng)
    loop = _seamless(mix, LOOP_SECONDS)

    peak = float(np.max(np.abs(loop)))
    loop *= 0.62 / max(peak, 1e-9)
    rms_db = 20.0 * np.log10(float(np.sqrt(np.mean(loop**2))) + 1e-12)
    print(f"foliage_rustle: {loop.shape[0] / SR:.1f}s stereo, peak 0.62, rms {rms_db:.1f} dBFS")

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    sf.write(str(OUT_FILE), loop, SR, subtype="PCM_16")
    print(f"wrote {OUT_FILE} ({OUT_FILE.stat().st_size} bytes)")

    manifest = json.loads(MANIFEST_FILE.read_text(encoding="utf-8"))
    entry = {
        "file": "foliage_rustle.wav",
        "seconds": LOOP_SECONDS,
        "sample_rate": SR,
        "channels": 2,
        "method": (
            "Synthesized stereo foliage-rustle ambience (band-shaped noise bed + "
            "gust-gated leaf-tick bursts, seamless crossfade loop). Foley ambience "
            "only, runtime-gated by measured foliage density; added in 0.2.44."
        ),
    }
    manifest["files"] = [f for f in manifest["files"] if f.get("file") != entry["file"]]
    manifest["files"].append(entry)
    manifest["format"] = "WAV 32000 Hz 16-bit (wind and foliage rustle stereo, rest mono)"
    MANIFEST_FILE.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print("manifest updated")


if __name__ == "__main__":
    main()
