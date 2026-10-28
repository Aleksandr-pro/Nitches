#!/usr/bin/env python3
"""Build the 0.2.40 Camaro / Mercedes / Audi recorded-audio banks.

Input is a checkout of the openly licensed loop bank in
``Jxstrr0/350Chev`` (``sounds/*.mp3`` plus the measured RPM/loop metadata
mirrored below from its ``src/sound/samples.js``).  The script trims each
phase-aligned loop, resamples it to the game's mono 32 kHz bank format,
and derives an off-throttle layer by cyclically low-pass filtering the
*same recording* (no synthesized engine tone is introduced).  Start events
combine a recorded starter motor with a pitch-ramped catch from the car's
own idle/rev loop; stop events pitch the idle loop down and fade it out
over the runtime's 0.82 s shutdown.

Every output folder receives a ``bank_manifest.json`` with the exact
source clip, author, license and URL for each anchor.  Human-readable
credits live in ``docs/AUDIO_CREDITS.md``.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path

import numpy as np
import soundfile as sf
from scipy import signal

TARGET_SR = 32_000

# clip -> measured metadata from 350Chev src/sound/samples.js and
# provenance from its sounds/CREDITS.md.
CLIPS = {
    "v8x62_idle": {
        "rpm": 635,
        "cylinders": 8,
        "loop": (0.3, 3.3217),
        "source": "Chevrolet Corvette V8 start/idle/revs",
        "author": "kyles",
        "license": "CC0 1.0",
        "url": "https://freesound.org/people/kyles/sounds/637184/",
    },
    "v8x57_idle": {
        "rpm": 805,
        "cylinders": 8,
        "loop": (0.3, 3.73032),
        "source": "Chevrolet Caprice V8 at different speeds",
        "author": "romanholtwick",
        "license": "CC0 1.0",
        "url": "https://freesound.org/people/romanholtwick/sounds/391671/",
    },
    "v8x57_rev": {
        "rpm": 1444,
        "cylinders": 8,
        "loop": (0.3, 2.29406),
        "source": "Chevrolet Caprice V8 at different speeds",
        "author": "romanholtwick",
        "license": "CC0 1.0",
        "url": "https://freesound.org/people/romanholtwick/sounds/391671/",
    },
    "v8x54_idle": {
        "rpm": 999,
        "cylinders": 8,
        "loop": (0.3, 3.30313),
        "source": "Ford F350 5.4 V8 startup and idle",
        "author": "Therancher01",
        "license": "CC0 1.0",
        "url": "https://freesound.org/people/Therancher01/sounds/610772/",
    },
    "v8xbb_rev": {
        "rpm": 2265,
        "cylinders": 8,
        "loop": (0.3, 0.88277),
        "source": "Ford 460 big-block V8 rev",
        "author": "Henaway",
        "license": "CC0 1.0",
        "url": "https://freesound.org/people/Henaway/sounds/127980/",
    },
    "v8x50_mid": {
        "rpm": 3747,
        "cylinders": 8,
        "loop": (0.3, 2.28556),
        "source": "Lexus IS F 2UR-GSE V8 on a dynamometer",
        "author": "Altair78",
        "license": "CC BY-SA 4.0",
        "url": "https://commons.wikimedia.org/wiki/File:Lexus_IS-F_dynamometer_2UR-GSE_(2008).ogg",
    },
    "v8f_hi": {
        "rpm": 4342,
        "cylinders": 8,
        "loop": (0.3, 0.60404),
        "source": "Ferrari 360 Spider flat-plane V8",
        "author": "PritzProductions",
        "license": "CC0 1.0",
        "url": "https://freesound.org/people/PritzProductions/sounds/241083/",
    },
    "v8xsc_hi": {
        "rpm": 6478,
        "cylinders": 8,
        "loop": (0.3, 1.50401),
        "source": "Supercharged Holden V8 dyno run-up",
        "author": "Ears68",
        "license": "CC0 1.0",
        "url": "https://freesound.org/people/Ears68/sounds/177184/",
    },
    "v10b_idle": {
        "rpm": 1231,
        "cylinders": 10,
        "loop": (0.3, 1.76274),
        "source": "BMW M6 V10 start and idle",
        "author": "Kinoton",
        "license": "CC0 1.0",
        "url": "https://freesound.org/people/Kinoton/sounds/478597/",
    },
    "v10a_idle": {
        "rpm": 1602,
        "cylinders": 10,
        "loop": (0.3, 2.77265),
        "source": "Lamborghini Huracan EVO 5.2 V10 start-up and idle",
        "author": "JaimeLopes",
        "license": "CC0 1.0",
        "url": "https://freesound.org/people/JaimeLopes/sounds/564373/",
    },
    "v10a_rev": {
        "rpm": 3735,
        "cylinders": 10,
        "loop": (0.3, 0.6534),
        "source": "Lamborghini Huracan EVO 5.2 V10 start-up and idle",
        "author": "JaimeLopes",
        "license": "CC0 1.0",
        "url": "https://freesound.org/people/JaimeLopes/sounds/564373/",
    },
    "crank_dsl": {
        "rpm": 0,
        "cylinders": 6,
        "loop": (0.0, 3.4),
        "source": "Ram 3500 Cummins recorded starter motor (starter layer only)",
        "author": "Therancher01",
        "license": "CC0 1.0",
        "url": "https://freesound.org/people/Therancher01/sounds/610771/",
    },
}

BANKS = {
    "camaro_ss": {
        "car": "Chevrolet Camaro SS 6.2 LT1",
        "anchors": ["v8x62_idle", "v8x57_rev", "v8xbb_rev", "v8x50_mid", "v8xsc_hi"],
        "idle_clip": "v8x62_idle",
        "catch_clip": "v8x62_idle",
        "off_cutoff_hz": 1250.0,
        "starter_rate": 1.05,
        "catch_rate": (0.55, 1.06),
    },
    "mercedes_560_sel": {
        "car": "Mercedes-Benz 560 SEL (W126, M117 V8)",
        "anchors": ["v8x57_idle", "v8x54_idle", "v8x57_rev", "v8xbb_rev", "v8x50_mid", "v8f_hi"],
        "idle_clip": "v8x57_idle",
        "catch_clip": "v8x57_idle",
        "off_cutoff_hz": 950.0,
        "starter_rate": 0.92,
        "catch_rate": (0.55, 1.0),
    },
    "audi_r8": {
        "car": "Audi R8 V10 plus 5.2 FSI",
        "anchors": ["v10b_idle", "v10a_idle", "v10a_rev"],
        "idle_clip": "v10a_idle",
        "catch_clip": "v10a_rev",
        "off_cutoff_hz": 1800.0,
        "starter_rate": 1.18,
        "catch_rate": (0.34, 0.62),
    },
}


def read_clip(source_dir: Path, clip: str) -> tuple[np.ndarray, int]:
    path = source_dir / f"{clip}.mp3"
    data, sr = sf.read(path, always_2d=False)
    if data.ndim > 1:
        data = data.mean(axis=1)
    return np.asarray(data, dtype=np.float64), int(sr)


def resample_to_target(data: np.ndarray, sr: int) -> np.ndarray:
    if sr == TARGET_SR:
        return data.astype(np.float64)
    gcd = np.gcd(TARGET_SR, sr)
    return signal.resample_poly(data, TARGET_SR // gcd, sr // gcd).astype(np.float64)


def loop_audio(source_dir: Path, clip: str) -> np.ndarray:
    data, sr = read_clip(source_dir, clip)
    start_s, end_s = CLIPS[clip]["loop"]
    data = data[int(start_s * sr) : int(end_s * sr)]
    return resample_to_target(data, sr)


def cyclic_filter(data: np.ndarray, sos: np.ndarray, pad_seconds: float = 0.35) -> np.ndarray:
    """Filter a loop without breaking its seam: filter a wrapped copy."""
    pad = min(len(data), int(TARGET_SR * pad_seconds))
    wrapped = np.concatenate([data[-pad:], data, data[:pad]])
    filtered = signal.sosfilt(sos, wrapped)
    return filtered[pad : pad + len(data)]


def normalise_rms(data: np.ndarray, target_db: float, peak_ceiling_db: float = -1.2) -> np.ndarray:
    rms = float(np.sqrt(np.mean(np.square(data))))
    if rms <= 1e-9:
        return data
    gain = (10.0 ** (target_db / 20.0)) / rms
    out = data * gain
    peak = float(np.max(np.abs(out)))
    ceiling = 10.0 ** (peak_ceiling_db / 20.0)
    if peak > ceiling:
        out *= ceiling / peak
    return out


def write_wav(path: Path, data: np.ndarray) -> dict:
    path.parent.mkdir(parents=True, exist_ok=True)
    sf.write(path, np.clip(data, -0.999, 0.999), TARGET_SR, subtype="PCM_16")
    return {
        "file": path.name,
        "seconds": round(len(data) / TARGET_SR, 5),
        "sample_rate": TARGET_SR,
        "channels": 1,
    }


def pitch_ramp(data: np.ndarray, start_rate: float, end_rate: float, seconds: float) -> np.ndarray:
    """Resample a cyclic loop so its playback rate ramps start->end."""
    out_len = int(seconds * TARGET_SR)
    t = np.linspace(0.0, 1.0, out_len)
    # Integral of the linear rate curve gives source position over time.
    source_pos = (start_rate * t + 0.5 * (end_rate - start_rate) * t * t) * seconds * TARGET_SR
    indexes = np.mod(source_pos, len(data))
    return np.interp(indexes, np.arange(len(data) + 1), np.concatenate([data, data[:1]]))


def constant_rate(data: np.ndarray, rate: float, seconds: float) -> np.ndarray:
    out_len = int(seconds * TARGET_SR)
    source_pos = np.arange(out_len) * rate
    source_pos = np.minimum(source_pos, len(data) - 1.001)
    return np.interp(source_pos, np.arange(len(data)), data)


def envelope(length: int, attack_s: float, release_s: float) -> np.ndarray:
    env = np.ones(length)
    attack = min(length, int(attack_s * TARGET_SR))
    release = min(length, int(release_s * TARGET_SR))
    if attack > 0:
        env[:attack] *= np.linspace(0.0, 1.0, attack)
    if release > 0:
        env[-release:] *= np.linspace(1.0, 0.0, release)
    return env


def build_start(source_dir: Path, config: dict, loops: dict[str, np.ndarray]) -> np.ndarray:
    crank, sr = read_clip(source_dir, "crank_dsl")
    crank = resample_to_target(crank[int(0.04 * sr) :], sr)
    starter = constant_rate(crank, float(config["starter_rate"]), 1.02)
    starter = cyclic_filter(
        starter,
        signal.butter(2, 3200.0, btype="lowpass", fs=TARGET_SR, output="sos"),
        pad_seconds=0.12,
    )
    starter = normalise_rms(starter, -19.5) * envelope(len(starter), 0.018, 0.24)

    out = np.zeros(int(1.62 * TARGET_SR))
    out[: len(starter)] += starter
    catch_start = int(0.76 * TARGET_SR)
    rate0, rate1 = config["catch_rate"]
    catch = pitch_ramp(loops[config["catch_clip"]], float(rate0), float(rate1), 0.82)
    catch = normalise_rms(catch, -16.8) * envelope(len(catch), 0.055, 0.34)
    end = min(len(out), catch_start + len(catch))
    out[catch_start:end] += catch[: end - catch_start]
    return normalise_rms(out, -17.6, peak_ceiling_db=-0.9)


def build_stop(config: dict, loops: dict[str, np.ndarray]) -> np.ndarray:
    idle = loops[config["idle_clip"]]
    stop = pitch_ramp(idle, 1.0, 0.38, 0.82)
    stop = cyclic_filter(
        stop,
        signal.butter(2, 2400.0, btype="lowpass", fs=TARGET_SR, output="sos"),
        pad_seconds=0.10,
    )
    # A dying engine rocks on its mounts for the last few cycles; the
    # amplitude wobble is an envelope over the recording, not a new tone.
    t = np.arange(len(stop)) / TARGET_SR
    wobble = 1.0 - 0.16 * np.maximum(0.0, t - 0.45) * np.sin(2.0 * np.pi * 9.0 * t)
    stop *= wobble * envelope(len(stop), 0.012, 0.46)
    return normalise_rms(stop, -19.0, peak_ceiling_db=-1.0)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source-dir", type=Path, required=True, help="350Chev sounds/ directory")
    parser.add_argument("--output-root", type=Path, required=True, help="src/assets/audio")
    args = parser.parse_args()

    highpass = signal.butter(2, 28.0, btype="highpass", fs=TARGET_SR, output="sos")
    for bank_name, config in BANKS.items():
        out_dir = args.output_root / bank_name
        loops: dict[str, np.ndarray] = {}
        for clip in set(config["anchors"]) | {config["idle_clip"], config["catch_clip"]}:
            loops[clip] = cyclic_filter(loop_audio(args.source_dir, clip), highpass)

        off_sos = signal.butter(
            4, float(config["off_cutoff_hz"]), btype="lowpass", fs=TARGET_SR, output="sos"
        )
        anchors = []
        for clip in config["anchors"]:
            meta = CLIPS[clip]
            rpm = int(meta["rpm"])
            on = normalise_rms(loops[clip], -17.0)
            off = normalise_rms(cyclic_filter(loops[clip], off_sos), -21.5)
            on_info = write_wav(out_dir / f"engine_on_{rpm:04d}.wav", on)
            off_info = write_wav(out_dir / f"engine_off_{rpm:04d}.wav", off)
            duration = (meta["loop"][1] - meta["loop"][0])
            anchors.append(
                {
                    "rpm": rpm,
                    "cycles": int(round(duration * rpm / 120.0)),
                    "on": on_info,
                    "off": off_info,
                    "source_clip": clip,
                    "source_recording": meta["source"],
                    "author": meta["author"],
                    "license": meta["license"],
                    "url": meta["url"],
                    "cylinders": meta["cylinders"],
                }
            )

        idle_info = write_wav(
            out_dir / "engine_idle.wav", normalise_rms(loops[config["idle_clip"]], -17.4)
        )
        start_info = write_wav(out_dir / "engine_start.wav", build_start(args.source_dir, config, loops))
        stop_info = write_wav(out_dir / "engine_stop.wav", build_stop(config, loops))
        manifest = {
            "bank": bank_name,
            "car": config["car"],
            "format": "mono WAV 32000 Hz 16-bit",
            "anchors": anchors,
            "idle": {
                **idle_info,
                "source_clip": config["idle_clip"],
                "source_rpm": CLIPS[config["idle_clip"]]["rpm"],
            },
            "start": {
                **start_info,
                "derivation": "Recorded CC0 starter motor (Therancher01, Freesound 610771) crossfaded into a pitch-ramped catch from this bank's own recorded idle/rev loop.",
            },
            "stop": {
                **stop_info,
                "derivation": "This bank's recorded idle loop pitch-ramped 1.0x -> 0.38x and faded over the 0.82 s runtime shutdown.",
            },
            "off_throttle_derivation": "Same recording as the matching on-throttle loop, cyclically low-pass filtered (no seam break) and set 4.5 dB quieter.",
            "tire": "Shared recorded tire_squeal_loop.wav from the Shelby bank (Tom Haigh, CC BY 3.0).",
        }
        (out_dir / "bank_manifest.json").write_text(
            json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
        )
        total = sum(path.stat().st_size for path in out_dir.glob("*.wav"))
        print(f"{bank_name}: {len(anchors)} anchors, {total} WAV bytes -> {out_dir}")


if __name__ == "__main__":
    main()
