#!/usr/bin/env python3
"""Build the vehicle recorded-audio banks (0.2.40 banks, 0.2.42 realism pass).

Supplied-car banks come from a checkout of the openly licensed loop bank
in ``Jxstrr0/350Chev`` (``sounds/*.mp3`` plus the measured RPM/loop
metadata mirrored below from its ``src/sound/samples.js``).

0.2.42 changes, all in service of a dense, believable RPM ladder:

* **More anchors.**  Sparse banks previously forced runtime pitch
  ratios up to 2.3x (chipmunk formants on the R8).  Additional anchors
  are derived from the *same recordings* with crank-cycle-synchronous
  TD-PSOLA: whole 720-degree cycles are overlap-added at the new
  period, so the firing pattern and spectral envelope (formants) of
  the recording survive while the pitch moves.  No synthesized engine
  tone is introduced anywhere; every anchor is a real loop or a
  PSOLA derivation of one, and the manifest says which.
* **Loop de-click.**  Hermite value+slope seam correction removes the
  residual step some steadied loops carry at the wrap point.
* **Exhaust crackle pops** are cut from each bank's own high-RPM
  recorded loops (single exhaust pulses, enveloped) and resequenced
  stochastically at runtime.
* **Shared foley** (wind, road beds per surface, transmission whine,
  impacts, scrape, suspension thump) is synthesized deterministically
  and documented as such; the shift clunk is extracted from the
  recorded Mustang starter engagement.  Engine and tyre-squeal voices
  remain 100% field recordings.

The Shelby stage post-processes the shipped GT500 bank in place
(de-click plus PSOLA 5000/5600 anchors above the 4400 rpm top loop).

Human-readable credits live in ``docs/AUDIO_CREDITS.md``; every bank
folder receives a ``bank_manifest.json`` with per-anchor provenance.
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

# anchors: (clip, target_rpm, method) — method "recorded" requires
# target_rpm == the clip's measured rpm; "psola" derives the target
# from that clip's recording (see psola_shift).
BANKS = {
    "camaro_ss": {
        "car": "Chevrolet Camaro SS 6.2 LT1",
        "anchors": [
            ("v8x62_idle", 635, "recorded"),
            ("v8x62_idle", 1050, "psola"),
            ("v8x57_rev", 1444, "recorded"),
            ("v8xbb_rev", 2265, "recorded"),
            ("v8x50_mid", 2900, "psola"),
            ("v8x50_mid", 3747, "recorded"),
            ("v8x50_mid", 5000, "psola"),
            ("v8xsc_hi", 6478, "recorded"),
        ],
        "idle_clip": "v8x62_idle",
        "catch_clip": "v8x62_idle",
        "off_cutoff_hz": 1250.0,
        "starter_rate": 1.05,
        "catch_rate": (0.55, 1.06),
        "pop_sources": [3747, 6478],
        "pop_seed": 4242,
    },
    "mercedes_560_sel": {
        "car": "Mercedes-Benz 560 SEL (W126, M117 V8)",
        "anchors": [
            ("v8x57_idle", 805, "recorded"),
            ("v8x54_idle", 999, "recorded"),
            ("v8x57_rev", 1444, "recorded"),
            ("v8xbb_rev", 2265, "recorded"),
            ("v8x50_mid", 2900, "psola"),
            ("v8x50_mid", 3747, "recorded"),
            ("v8x50_mid", 5000, "psola"),
        ],
        "idle_clip": "v8x57_idle",
        "catch_clip": "v8x57_idle",
        "off_cutoff_hz": 950.0,
        "starter_rate": 0.92,
        "catch_rate": (0.55, 1.0),
        "pop_sources": [3747, 5000],
        "pop_seed": 5605,
    },
    "audi_r8": {
        "car": "Audi R8 V10 plus 5.2 FSI",
        "anchors": [
            ("v10b_idle", 1231, "recorded"),
            ("v10a_idle", 1602, "recorded"),
            ("v10a_idle", 2400, "psola"),
            ("v10a_rev", 3735, "recorded"),
            ("v10a_rev", 5200, "psola"),
            ("v10a_rev", 6800, "psola"),
        ],
        "idle_clip": "v10a_idle",
        "catch_clip": "v10a_rev",
        "off_cutoff_hz": 1800.0,
        "starter_rate": 1.18,
        "catch_rate": (0.34, 0.62),
        "pop_sources": [2400, 3735, 5200],
        "pop_seed": 5200,
    },
}

SHELBY_PSOLA_RPMS = [5000, 5600]
SHELBY_TOP_RPM = 4400


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


def clip_cycles(clip: str) -> int:
    meta = CLIPS[clip]
    duration = meta["loop"][1] - meta["loop"][0]
    return max(1, int(round(duration * float(meta["rpm"]) / 120.0)))


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


def match_rms(data: np.ndarray, reference: np.ndarray) -> np.ndarray:
    ref = float(np.sqrt(np.mean(np.square(reference))))
    rms = float(np.sqrt(np.mean(np.square(data))))
    if rms <= 1e-9 or ref <= 1e-9:
        return data
    return data * (ref / rms)


def declick_loop(data: np.ndarray, window_s: float = 0.03) -> np.ndarray:
    """Remove the wrap-point step with a Hermite value+slope correction.

    The last ``window_s`` seconds are bent so the loop ends exactly on
    the first sample's value and slope.  Content before the window is
    untouched; length (and therefore integer crank cycles) is kept.
    """
    x = np.array(data, dtype=np.float64, copy=True)
    if len(x) < 64:
        return x
    dv = float(x[-1] - x[0])
    slope_tail = float(x[-1] - x[-2])
    slope_head = float(x[1] - x[0])
    if abs(dv) < 0.003 and abs(slope_tail - slope_head) < 0.01:
        return x
    w = min(len(x) // 4, int(TARGET_SR * window_s))
    s = np.linspace(0.0, 1.0, w)
    # Cubic Hermite with c(0)=0, c'(0)=0, c(1)=dv, c'(1)=(slope_tail-slope_head)*w
    m1 = (slope_tail - slope_head) * w
    h10 = -2.0 * s**3 + 3.0 * s**2
    h11 = s**3 - s**2
    correction = h10 * dv + h11 * m1
    x[-w:] -= correction
    return x


def find_pulse_marks(data: np.ndarray, samples_per_cycle: float, cylinders: int) -> list[int]:
    """Locate exhaust-pulse peaks (the 'glottal pulses' of an engine)."""
    env = signal.sosfilt(
        signal.butter(2, 500.0, btype="lowpass", fs=TARGET_SR, output="sos"), np.abs(data)
    )
    fire = samples_per_cycle / float(cylinders)
    peaks, _ = signal.find_peaks(
        env,
        distance=int(fire * 0.55),
        prominence=0.5 * float(np.std(env)),
        height=float(np.median(env) + 0.35 * np.std(env)),
    )
    if len(peaks) < 8:
        step = max(1, int(round(fire)))
        return list(range(0, len(data), step))
    marks = [int(p) for p in peaks]
    median_spacing = float(np.median(np.diff(marks)))
    cleaned = [marks[0]]
    for mark in marks[1:]:
        if mark - cleaned[-1] >= 0.5 * median_spacing:
            cleaned.append(mark)
    out: list[int] = []
    for i, mark in enumerate(cleaned):
        out.append(mark)
        nxt = cleaned[(i + 1) % len(cleaned)]
        gap = (nxt - mark) % len(data)
        if gap > 1.7 * median_spacing:
            out.append(int((mark + gap / 2.0) % len(data)))
    return sorted(out)


def psola_shift(
    data: np.ndarray,
    cycles_in: int,
    ratio: float,
    cylinders: int,
    min_seconds: float = 0.6,
) -> np.ndarray:
    """Pulse-synchronous TD-PSOLA pitch shift of a seamless loop.

    Grains of two local pulse periods are taken cyclically from the
    source at detected exhaust-pulse marks and overlap-added at mark
    times scaled by ``1/ratio``.  The waveform of each pulse (its
    spectral envelope/formants) is preserved while the pulse rate —
    the perceived engine pitch — moves by ``ratio``.  Mark spacing is
    scaled uniformly, so an uneven firing pattern (crossplane lope)
    keeps its proportions.  Output is an integer number of crank
    cycles and loops exactly.
    """
    x = np.asarray(data, dtype=np.float64)
    n = len(x)
    spc = n / float(cycles_in)
    spc_out = spc / ratio
    cycles_out = max(cycles_in, int(round(min_seconds * TARGET_SR / spc_out)))
    out_len = int(round(cycles_out * spc_out))
    marks = find_pulse_marks(x, spc, cylinders)
    spacings = np.diff(np.concatenate([marks, [marks[0] + n]]))
    y = np.zeros(out_len)
    wsum = np.zeros(out_len)
    reps = int(np.ceil(out_len * ratio / n)) + 1
    for rep in range(reps):
        for i, mark in enumerate(marks):
            src_pos = rep * n + mark
            out_center = src_pos / ratio
            grain_len = int(round(2.0 * float(spacings[i])))
            if grain_len % 2:
                grain_len += 1
            if out_center - grain_len > out_len:
                continue
            win = np.hanning(grain_len)
            grain_idx = (np.arange(grain_len) - grain_len // 2 + mark) % n
            start = int(round(out_center)) - grain_len // 2
            out_idx = (start + np.arange(grain_len)) % out_len
            np.add.at(y, out_idx, x[grain_idx] * win)
            np.add.at(wsum, out_idx, win)
    return y / np.maximum(wsum, 1e-6)


def derive_psola_anchor(
    base: np.ndarray,
    cycles_in: int,
    cylinders: int,
    parent_rpm: float,
    target_rpm: int,
) -> tuple[np.ndarray, int, float, float]:
    """PSOLA-derive an anchor at an exact construction ratio.

    The output pulse rate is the parent's verified pulse rate scaled
    by ``target/parent`` *by construction* (same grains, scaled mark
    spacing), and engine pitch perception follows pulse rate.  A
    spectral comb estimate is recorded in the manifest for reference,
    but it is not used for labelling: PSOLA deliberately preserves
    the parent's spectral envelope, which biases comb estimators
    toward the parent rpm even though the pulse rate has moved.
    """
    ratio = float(target_rpm) / float(parent_rpm)
    derived = declick_loop(psola_shift(base, cycles_in, ratio, cylinders))
    measured = measure_rpm(derived, cylinders, float(target_rpm))
    return derived, int(target_rpm), measured, ratio


def measure_rpm(data: np.ndarray, cylinders: int, claim: float) -> float:
    """Comb-score the firing-frequency harmonics to verify an anchor."""
    x = (data - np.mean(data)) * np.hanning(len(data))
    n_fft = 1 << 17
    spectrum = np.abs(np.fft.rfft(x, n_fft))
    freqs = np.fft.rfftfreq(n_fft, 1.0 / TARGET_SR)
    best_rpm, best_score = claim, -1.0
    for rpm in np.arange(claim * 0.84, claim * 1.16, 3.0):
        f_fire = rpm * cylinders / 120.0
        score = 0.0
        for harmonic in range(1, 9):
            f = f_fire * harmonic
            if f > 6000.0:
                break
            i = int(np.argmin(np.abs(freqs - f)))
            score += float(spectrum[max(0, i - 1) : i + 2].max()) / harmonic
        if score > best_score:
            best_rpm, best_score = float(rpm), score
    return best_rpm


def write_wav(path: Path, data: np.ndarray) -> dict:
    path.parent.mkdir(parents=True, exist_ok=True)
    sf.write(path, np.clip(data, -0.999, 0.999), TARGET_SR, subtype="PCM_16")
    channels = 2 if data.ndim > 1 else 1
    return {
        "file": path.name,
        "seconds": round(len(data) / TARGET_SR, 5),
        "sample_rate": TARGET_SR,
        "channels": channels,
    }


def pitch_ramp(data: np.ndarray, start_rate: float, end_rate: float, seconds: float) -> np.ndarray:
    """Resample a cyclic loop so its playback rate ramps start->end."""
    out_len = int(seconds * TARGET_SR)
    t = np.linspace(0.0, 1.0, out_len)
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


def extract_pops(sources: list[np.ndarray], out_dir: Path, seed: int, count: int = 10) -> list[dict]:
    """Cut single exhaust pulses out of the bank's own recorded loops.

    A real overrun crackle is just the exhaust firing unevenly; cutting
    actual pulses from the car's high-RPM loops and resequencing them
    at runtime keeps exactly that recorded voice.
    """
    rng = np.random.default_rng(seed)
    env_sos = signal.butter(2, 700.0, btype="lowpass", fs=TARGET_SR, output="sos")
    candidates: list[tuple[float, int, int]] = []
    for source_index, x in enumerate(sources):
        env = signal.sosfilt(env_sos, np.abs(x))
        peaks, _ = signal.find_peaks(
            env,
            distance=int(0.030 * TARGET_SR),
            prominence=0.35 * float(np.std(env)),
            height=float(np.median(env) + 0.25 * np.std(env)),
        )
        for peak in peaks:
            candidates.append((float(env[peak]), source_index, int(peak)))
    candidates.sort(key=lambda item: -item[0])
    pool = candidates[:60]
    rng.shuffle(pool)
    accepted: list[tuple[int, int]] = []
    for _strength, source_index, peak in pool:
        if any(si == source_index and abs(peak - p) < int(0.03 * TARGET_SR) for si, p in accepted):
            continue
        accepted.append((source_index, peak))
        if len(accepted) >= count * 2:
            break
    infos: list[dict] = []
    lp_choices = [3600.0, 5200.0, 7600.0]
    made = 0
    for source_index, peak in accepted:
        if made >= count:
            break
        x = sources[source_index]
        start = peak - int(0.006 * TARGET_SR)
        length = int(rng.uniform(0.055, 0.115) * TARGET_SR)
        # Sources are seamless loops, so a pulse near the wrap point is
        # still usable by indexing cyclically.
        idx = (start + np.arange(length)) % len(x)
        segment = np.array(x[idx], dtype=np.float64)
        cutoff = lp_choices[made % len(lp_choices)]
        segment = signal.sosfilt(
            signal.butter(2, cutoff, btype="lowpass", fs=TARGET_SR, output="sos"), segment
        )
        t = np.arange(length) / TARGET_SR
        tau = float(rng.uniform(0.016, 0.038))
        env = np.exp(-t / tau)
        attack = min(length, int(0.0015 * TARGET_SR))
        env[:attack] *= np.linspace(0.0, 1.0, attack)
        segment *= env
        peak_value = float(np.max(np.abs(segment)))
        if peak_value <= 1e-6:
            continue
        segment *= (10.0 ** (float(rng.uniform(-3.2, -1.6)) / 20.0)) / peak_value
        info = write_wav(out_dir / f"pop_{made + 1:02d}.wav", segment)
        infos.append(info)
        made += 1
    return infos


def build_supplied_banks(source_dir: Path, output_root: Path) -> None:
    highpass = signal.butter(2, 28.0, btype="highpass", fs=TARGET_SR, output="sos")
    for bank_name, config in BANKS.items():
        out_dir = output_root / bank_name
        out_dir.mkdir(parents=True, exist_ok=True)
        needed_clips = {clip for clip, _rpm, _m in config["anchors"]} | {
            config["idle_clip"],
            config["catch_clip"],
        }
        loops: dict[str, np.ndarray] = {}
        for clip in needed_clips:
            loops[clip] = declick_loop(cyclic_filter(loop_audio(source_dir, clip), highpass))

        off_sos = signal.butter(
            4, float(config["off_cutoff_hz"]), btype="lowpass", fs=TARGET_SR, output="sos"
        )
        # First pass: build every anchor's audio (PSOLA labels come from
        # measurement, so file names are only known after derivation).
        prepared: list[dict] = []
        for clip, target_rpm, method in config["anchors"]:
            meta = CLIPS[clip]
            base = loops[clip]
            if method == "psola":
                anchor_audio, rpm, measured, ratio = derive_psola_anchor(
                    base, clip_cycles(clip), int(meta["cylinders"]), float(meta["rpm"]), int(target_rpm)
                )
                derivation = (
                    f"Pulse-synchronous TD-PSOLA (formant-preserving) derivation "
                    f"of the recorded {clip} loop at {meta['rpm']} rpm, ratio {ratio:.3f}, "
                    f"pulse rate scaled to {rpm} rpm by construction (comb spectral estimate {measured:.0f}, biased toward the parent envelope PSOLA preserves); no synthesized tone."
                )
            else:
                assert int(meta["rpm"]) == target_rpm, f"{clip} recorded rpm mismatch"
                anchor_audio = base
                rpm = int(target_rpm)
                measured = measure_rpm(anchor_audio, int(meta["cylinders"]), float(rpm))
                derivation = "Recorded loop, trimmed to whole crank cycles and de-clicked at the seam."
            prepared.append(
                {
                    "clip": clip,
                    "meta": meta,
                    "method": method,
                    "rpm": rpm,
                    "measured": measured,
                    "audio": anchor_audio,
                    "derivation": derivation,
                }
            )
        prepared.sort(key=lambda item: item["rpm"])

        # Remove stale anchor files from earlier bank layouts.
        new_names = {
            f"engine_{layer}_{item['rpm']:04d}.wav"
            for item in prepared
            for layer in ("on", "off")
        }
        for stale in list(out_dir.glob("engine_on_*.wav")) + list(out_dir.glob("engine_off_*.wav")):
            if stale.name not in new_names:
                stale.unlink()

        anchors = []
        on_by_rpm: dict[int, np.ndarray] = {}
        gd_cycles: list[int] = []
        for item in prepared:
            clip = item["clip"]
            meta = item["meta"]
            rpm = int(item["rpm"])
            anchor_audio = item["audio"]
            on = normalise_rms(anchor_audio, -17.0)
            off = normalise_rms(cyclic_filter(anchor_audio, off_sos), -21.5)
            on_by_rpm[rpm] = on
            on_info = write_wav(out_dir / f"engine_on_{rpm:04d}.wav", on)
            off_info = write_wav(out_dir / f"engine_off_{rpm:04d}.wav", off)
            cycles = int(round((len(on) / TARGET_SR) * rpm / 120.0))
            gd_cycles.append(cycles)
            anchors.append(
                {
                    "rpm": rpm,
                    "cycles": cycles,
                    "measured_rpm": round(float(item["measured"]), 1),
                    "on": on_info,
                    "off": off_info,
                    "source_clip": clip,
                    "source_recording": meta["source"],
                    "author": meta["author"],
                    "license": meta["license"],
                    "url": meta["url"],
                    "cylinders": meta["cylinders"],
                    "derivation": item["derivation"],
                }
            )
            print(
                f"  {bank_name} {rpm:5d} {item['method']:9s} from {clip:<12s} "
                f"measured {float(item['measured']):7.0f} cycles {cycles}"
            )

        pop_sources = [on_by_rpm[rpm] for rpm in config["pop_sources"] if rpm in on_by_rpm]
        pop_infos = extract_pops(pop_sources, out_dir, int(config["pop_seed"]))

        idle_info = write_wav(
            out_dir / "engine_idle.wav", normalise_rms(loops[config["idle_clip"]], -17.4)
        )
        start_info = write_wav(out_dir / "engine_start.wav", build_start(source_dir, config, loops))
        stop_info = write_wav(out_dir / "engine_stop.wav", build_stop(config, loops))
        manifest = {
            "bank": bank_name,
            "car": config["car"],
            "format": "mono WAV 32000 Hz 16-bit",
            "audio_0242": True,
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
            "pops": {
                "files": pop_infos,
                "derivation": "Single exhaust pulses cut from this bank's own high-RPM recorded loops, enveloped and resequenced stochastically at runtime for overrun crackle.",
            },
            "off_throttle_derivation": "Same recording as the matching on-throttle loop, cyclically low-pass filtered (no seam break) and set 4.5 dB quieter.",
            "tire": "Shared recorded tire_squeal_loop.wav from the Shelby bank (Tom Haigh, CC BY 3.0).",
        }
        (out_dir / "bank_manifest.json").write_text(
            json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
        )
        rpms = [int(item["rpm"]) for item in prepared]
        total = sum(path.stat().st_size for path in out_dir.glob("*.wav"))
        print(f"{bank_name}: {len(anchors)} anchors, {len(pop_infos)} pops, {total} WAV bytes -> {out_dir}")
        print(f"  GDScript: rpms={rpms} cycles={gd_cycles}")


def process_shelby_bank(shelby_dir: Path) -> None:
    manifest_path = shelby_dir / "bank_manifest.json"
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    loops_by_file: dict[str, np.ndarray] = {}
    for entry in manifest["engine_loops"]:
        path = shelby_dir / entry["file"]
        data, sr = sf.read(path, always_2d=False)
        assert sr == TARGET_SR, f"{path} sample rate {sr}"
        data = np.asarray(data, dtype=np.float64)
        cleaned = declick_loop(data)
        if not np.array_equal(cleaned, data):
            sf.write(path, np.clip(cleaned, -0.999, 0.999), TARGET_SR, subtype="PCM_16")
        loops_by_file[entry["file"]] = cleaned
        entry["samples"] = int(len(cleaned))
    # The long idle and tyre loops wrap at runtime too.
    for extra_name in ("mustang_idle.wav", "tire_squeal_loop.wav"):
        path = shelby_dir / extra_name
        data, _sr = sf.read(path, always_2d=False)
        cleaned = declick_loop(np.asarray(data, dtype=np.float64))
        if not np.array_equal(cleaned, np.asarray(data, dtype=np.float64)):
            sf.write(path, np.clip(cleaned, -0.999, 0.999), TARGET_SR, subtype="PCM_16")

    # Drop previously derived entries so re-runs regenerate their
    # manifest rows alongside the audio (idempotent full rebuild).
    manifest["engine_loops"] = [
        e for e in manifest["engine_loops"] if "derived_from" not in e
    ]
    loops_by_file = {
        name: data
        for name, data in loops_by_file.items()
        if any(e["file"] == name for e in manifest["engine_loops"])
    }
    existing_rpms = {(e["layer"], int(e["rpm"])) for e in manifest["engine_loops"]}
    top_entries = {
        e["layer"]: e for e in manifest["engine_loops"] if int(e["rpm"]) == SHELBY_TOP_RPM
    }
    new_entries: list[dict] = []
    for layer in ("on", "off"):
        parent_entry = top_entries[layer]
        parent = loops_by_file[parent_entry["file"]]
        parent_cycles = int(parent_entry["cycles"])
        for target_rpm in SHELBY_PSOLA_RPMS:
            derived_raw, rpm, measured, ratio = derive_psola_anchor(
                parent, parent_cycles, 8, float(SHELBY_TOP_RPM), int(target_rpm)
            )
            derived = match_rms(derived_raw, parent)
            file_name = f"gt500_{layer}_{rpm:04d}.wav"
            sf.write(
                shelby_dir / file_name,
                np.clip(derived, -0.999, 0.999),
                TARGET_SR,
                subtype="PCM_16",
            )
            cycles = int(round((len(derived) / TARGET_SR) * rpm / 120.0))
            print(
                f"  shelby {layer} {rpm} psola x{ratio:.3f} from {parent_entry['file']} "
                f"measured {measured:.0f} cycles {cycles}"
            )
            if (layer, rpm) not in existing_rpms:
                new_entries.append(
                    {
                        "file": file_name,
                        "layer": layer,
                        "rpm": rpm,
                        "cycles": cycles,
                        "samples": int(len(derived)),
                        "measured_rpm": round(measured, 1),
                        "source_freesound_id": parent_entry["source_freesound_id"],
                        "source_time_s": parent_entry["source_time_s"],
                        "source_rpm": parent_entry["source_rpm"],
                        "derived_from": parent_entry["file"],
                        "derivation": (
                            f"Pulse-synchronous TD-PSOLA (formant-preserving) pitch-shift "
                            f"of the recorded {parent_entry['file']} loop, ratio {ratio:.3f}, "
                            f"pulse rate scaled to {rpm} rpm by construction (comb spectral estimate {measured:.0f}, biased toward the parent envelope PSOLA preserves); no synthesized tone."
                        ),
                    }
                )
    manifest["engine_loops"].extend(new_entries)
    manifest["audio_0242"] = True

    pop_sources = [
        loops_by_file["gt500_off_4400.wav"],
        loops_by_file["gt500_on_4400.wav"],
    ]
    pop_infos = extract_pops(pop_sources, shelby_dir, seed=1967)
    manifest["pops"] = {
        "files": pop_infos,
        "derivation": "Single exhaust pulses cut from the recorded GT500 4400 rpm loops, enveloped and resequenced stochastically at runtime for overrun crackle.",
    }
    manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    total_loops = len(manifest["engine_loops"])
    print(f"shelby: {total_loops} engine loops in manifest, {len(pop_infos)} pops")


def shaped_noise(seconds: float, alpha: float, rng: np.random.Generator) -> np.ndarray:
    """FFT-shaped 1/f^alpha noise; inherently seamless (periodic)."""
    n = int(seconds * TARGET_SR)
    white = rng.standard_normal(n)
    spectrum = np.fft.rfft(white)
    freqs = np.fft.rfftfreq(n, 1.0 / TARGET_SR)
    shape = np.ones_like(freqs)
    shape[1:] = (freqs[1:] / 100.0) ** (-alpha / 2.0)
    out = np.fft.irfft(spectrum * shape, n)
    return out / max(float(np.max(np.abs(out))), 1e-9)


def fft_filter(data: np.ndarray, low_hz: float | None, high_hz: float | None) -> np.ndarray:
    """Zero-phase brick-wall-ish filtering in the FFT domain (periodic-safe)."""
    n = len(data)
    spectrum = np.fft.rfft(data)
    freqs = np.fft.rfftfreq(n, 1.0 / TARGET_SR)
    gain = np.ones_like(freqs)
    if high_hz is not None:
        # Smooth (raised-cosine) high cut over one octave.
        transition = np.clip((np.log2(np.maximum(freqs, 1e-6) / high_hz) + 0.5), 0.0, 1.0)
        gain *= 0.5 * (1.0 + np.cos(np.pi * (1.0 - transition))) * (freqs > high_hz * 0.5) + (
            freqs <= high_hz * 0.5
        )
    if low_hz is not None:
        transition = np.clip((np.log2(np.maximum(freqs, 1e-6) / low_hz) + 0.5), 0.0, 1.0)
        gain *= 0.5 * (1.0 - np.cos(np.pi * transition)) * (freqs < low_hz * 2.0) + (
            freqs >= low_hz * 2.0
        )
    return np.fft.irfft(spectrum * gain, n)


def periodic_am(seconds: float, depth: float, max_hz: float, rng: np.random.Generator) -> np.ndarray:
    n = int(seconds * TARGET_SR)
    spectrum = np.zeros(n // 2 + 1, dtype=complex)
    freqs = np.fft.rfftfreq(n, 1.0 / TARGET_SR)
    mask = (freqs > 0.2) & (freqs < max_hz)
    phases = rng.uniform(0.0, 2.0 * np.pi, int(mask.sum()))
    spectrum[mask] = np.exp(1j * phases) / np.maximum(freqs[mask], 0.4)
    am = np.fft.irfft(spectrum, n)
    am /= max(float(np.max(np.abs(am))), 1e-9)
    return 1.0 - depth * (0.5 + 0.5 * am)


def sine_drop(f0: float, f1: float, seconds: float, tau: float) -> np.ndarray:
    n = int(seconds * TARGET_SR)
    t = np.arange(n) / TARGET_SR
    freq = f1 + (f0 - f1) * np.exp(-t / (tau * 0.6))
    phase = 2.0 * np.pi * np.cumsum(freq) / TARGET_SR
    return np.sin(phase) * np.exp(-t / tau)


def extract_clunk(shelby_dir: Path) -> np.ndarray:
    """Mechanical shift clunk from the recorded Mustang starter engage."""
    data, _sr = sf.read(shelby_dir / "mustang_start.wav", always_2d=False)
    x = np.asarray(data, dtype=np.float64)
    search = x[: int(0.6 * TARGET_SR)]
    onset_env = signal.sosfilt(
        signal.butter(2, 900.0, btype="lowpass", fs=TARGET_SR, output="sos"), np.abs(search)
    )
    onset = int(np.argmax(onset_env > 0.35 * float(onset_env.max())))
    start = max(0, onset - int(0.004 * TARGET_SR))
    length = int(0.11 * TARGET_SR)
    segment = np.array(x[start : start + length], dtype=np.float64)
    segment = signal.sosfilt(
        signal.butter(2, 1150.0, btype="lowpass", fs=TARGET_SR, output="sos"), segment
    )
    t = np.arange(len(segment)) / TARGET_SR
    env = np.exp(-t / 0.028)
    env[: int(0.001 * TARGET_SR)] *= np.linspace(0.0, 1.0, int(0.001 * TARGET_SR))
    segment *= env
    peak = float(np.max(np.abs(segment)))
    return segment * ((10.0 ** (-2.0 / 20.0)) / max(peak, 1e-9))


def build_foley(foley_dir: Path, shelby_dir: Path) -> None:
    foley_dir.mkdir(parents=True, exist_ok=True)
    rng = np.random.default_rng(20241029)
    files: list[dict] = []

    # Wind: decorrelated stereo 1/f noise with baked integer-cycle gusts.
    wind_seconds = 6.0
    t = np.arange(int(wind_seconds * TARGET_SR)) / TARGET_SR
    gust = 0.74 + 0.16 * np.sin(2.0 * np.pi * 2.0 * t / wind_seconds) + 0.10 * np.sin(
        2.0 * np.pi * 5.0 * t / wind_seconds + 1.3
    )
    channels = []
    for _ in range(2):
        channel = fft_filter(shaped_noise(wind_seconds, 1.05, rng), 40.0, 3400.0) * gust
        channels.append(channel)
    wind = np.stack(channels, axis=1)
    wind = normalise_rms(wind, -20.0)
    files.append(
        {
            **write_wav(foley_dir / "wind_loop.wav", wind),
            "method": "Synthesized stereo 1/f noise, FFT-shaped (inherently seamless), baked gust LFO. Foley layer only.",
        }
    )

    # Road beds per surface.
    road_specs = {
        "road_asphalt.wav": (0.85, 55.0, 2400.0, 0.0, -21.0),
        "road_sidewalk.wav": (0.95, 60.0, 2000.0, 0.0, -20.5),
        "road_grass.wav": (1.25, 45.0, 820.0, 0.38, -19.0),
        "road_sand.wav": (0.45, 260.0, 5200.0, 0.26, -20.0),
    }
    for name, (alpha, low, high, am_depth, rms_db) in road_specs.items():
        bed = fft_filter(shaped_noise(4.0, alpha, rng), low, high)
        if name == "road_sidewalk.wav":
            # Concrete expansion joints ticking under the tyres.
            joint = np.zeros_like(bed)
            spacing = int(0.55 * TARGET_SR)
            puff = sine_drop(120.0, 70.0, 0.045, 0.012)
            for start in range(0, len(bed) - len(puff), spacing):
                joint[start : start + len(puff)] += puff
            bed = bed + 0.35 * joint
        if am_depth > 0.0:
            bed = bed * periodic_am(4.0, am_depth, 7.0, rng)
        bed = normalise_rms(bed, rms_db)
        files.append(
            {
                **write_wav(foley_dir / name, bed),
                "method": "Synthesized FFT-shaped noise road bed (seamless). Foley layer only; tyre squeal itself stays the CC BY recording.",
            }
        )

    # Transmission whine: integer-cycle harmonic loop, pitched at runtime
    # with output-shaft speed (reverse gear whine is the audible case).
    whine_seconds = 2.0
    tw = np.arange(int(whine_seconds * TARGET_SR)) / TARGET_SR
    whine = np.zeros_like(tw)
    for harmonic, amp in ((1, 1.0), (2, 0.52), (3, 0.26), (4, 0.11)):
        whine += amp * np.sin(2.0 * np.pi * 82.0 * harmonic * tw)
    whine += 0.45 * np.sin(2.0 * np.pi * 82.5 * tw)  # 165 cycles: still seamless
    whine = normalise_rms(whine, -24.0)
    files.append(
        {
            **write_wav(foley_dir / "whine_loop.wav", whine),
            "method": "Synthesized harmonic gear-mesh loop at 82 Hz, pitched by output-shaft speed at runtime, mixed ~26 dB under the recorded engine. Foley layer only.",
        }
    )

    # Impacts / thump / scrape.
    def impact(f0: float, lp: float, seconds: float, tau: float, noise_gain: float, metal: float):
        noise = rng.standard_normal(int(seconds * TARGET_SR))
        noise = fft_filter(noise, 60.0, lp) * np.exp(
            -np.arange(len(noise)) / TARGET_SR / (tau * 0.7)
        )
        body = sine_drop(f0, f0 * 0.52, seconds, tau)
        out = body + noise_gain * noise / max(float(np.max(np.abs(noise))), 1e-9)
        if metal > 0.0:
            tm = np.arange(len(out)) / TARGET_SR
            out += metal * np.sin(2.0 * np.pi * 620.0 * tm) * np.exp(-tm / 0.05)
            out += metal * 0.6 * np.sin(2.0 * np.pi * 935.0 * tm) * np.exp(-tm / 0.035)
        peak = float(np.max(np.abs(out)))
        return out * ((10.0 ** (-1.5 / 20.0)) / max(peak, 1e-9))

    for name, params in {
        "impact_soft.wav": (95.0, 700.0, 0.20, 0.055, 0.25, 0.0),
        "impact_med.wav": (120.0, 1300.0, 0.26, 0.07, 0.5, 0.10),
        "impact_hard.wav": (150.0, 2400.0, 0.34, 0.09, 0.8, 0.22),
    }.items():
        files.append(
            {
                **write_wav(foley_dir / name, impact(*params)),
                "method": "Synthesized body-knock (pitch-dropping sine + filtered noise burst). Foley layer only.",
            }
        )
    thump = sine_drop(72.0, 40.0, 0.20, 0.06)
    puff = fft_filter(rng.standard_normal(len(thump)), 50.0, 420.0)
    thump = thump + 0.3 * puff / max(float(np.max(np.abs(puff))), 1e-9) * np.exp(
        -np.arange(len(thump)) / TARGET_SR / 0.04
    )
    thump *= (10.0 ** (-2.5 / 20.0)) / max(float(np.max(np.abs(thump))), 1e-9)
    files.append(
        {
            **write_wav(foley_dir / "suspension_thump.wav", thump),
            "method": "Synthesized low suspension thump. Foley layer only.",
        }
    )
    scrape = fft_filter(shaped_noise(3.0, 0.25, rng), 1300.0, 6500.0)
    scrape = scrape * periodic_am(3.0, 0.5, 9.0, rng)
    scrape = normalise_rms(scrape, -23.0)
    files.append(
        {
            **write_wav(foley_dir / "scrape_loop.wav", scrape),
            "method": "Synthesized metallic scrape bed (seamless). Foley layer only.",
        }
    )

    clunk = extract_clunk(shelby_dir)
    files.append(
        {
            **write_wav(foley_dir / "shift_clunk.wav", clunk),
            "method": "Extracted from the recorded Mustang starter engagement (lmbubec, Freesound 119449, CC0), low-passed and enveloped; per-car character via runtime pitch/gain.",
        }
    )

    manifest = {
        "foley_0242": True,
        "format": "WAV 32000 Hz 16-bit (wind stereo, rest mono)",
        "note": "Engine and tyre-squeal voices are field recordings in the per-car banks; this folder is supplemental foley only.",
        "files": files,
    }
    (foley_dir / "foley_manifest.json").write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    total = sum(path.stat().st_size for path in foley_dir.glob("*.wav"))
    print(f"foley: {len(files)} files, {total} WAV bytes -> {foley_dir}")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source-dir", type=Path, default=None, help="350Chev sounds/ directory")
    parser.add_argument("--output-root", type=Path, default=Path("src/assets/audio"))
    parser.add_argument("--shelby-dir", type=Path, default=None, help="shipped Shelby bank folder")
    parser.add_argument("--foley-dir", type=Path, default=None, help="vehicle foley output folder")
    args = parser.parse_args()

    if args.source_dir is not None:
        build_supplied_banks(args.source_dir, args.output_root)
    if args.shelby_dir is not None:
        process_shelby_bank(args.shelby_dir)
    if args.foley_dir is not None:
        shelby = args.shelby_dir if args.shelby_dir is not None else args.output_root / "shelby"
        build_foley(args.foley_dir, shelby)


if __name__ == "__main__":
    main()
