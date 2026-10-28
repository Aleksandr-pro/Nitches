# Audio credits — Native 0.2.35

The Shelby vehicle voice in Nitches Horizon is built from real field
recordings, not from an oscillator or a synthesized engine tone.

## Recorded engine bank

### Mustang GT500 driving loops — CC0

- Recordings by **VacekH**, published on Freesound as Mustang GT500
  sounds **205501**, **205503**, **205508**, **205510**, and
  **205511**.
- License: **Creative Commons CC0 1.0 Universal (public-domain
  dedication)**.
- Example source page:
  <https://freesound.org/people/VacekH/sounds/205510/>
- Game files: `gt500_on_0900.wav` … `gt500_on_4400.wav` and
  `gt500_off_0900.wav` … `gt500_off_4400.wav` in
  `src/assets/audio/shelby/`.
- The recordings were cut into phase-aligned whole-crank-cycle loops
  at sixteen RPM points, with separate on-throttle and
  off-throttle layers. Adjacent RPM loops and the two load layers
  are equal-power crossfaded at runtime.

### Mustang idle, starter, and shutdown — CC0

- Recording by **lmbubec**, “Ford Mustang Engine (1985)”, Freesound
  sound **119449**.
- License: **Creative Commons CC0 1.0 Universal (public-domain
  dedication)**.
- Source: <https://freesound.org/people/lmbubec/sounds/119449/>
- Game files: `mustang_idle.wav`, `mustang_start.wav`, and
  `mustang_stop.wav`.
- The fifteen-second idle is used below the first driving loops.
  The starter event is assembled from the recorded crank/catch;
  the shutdown event is taken from the recorded engine-off tail.

## Tyre squeal — CC BY 3.0

- “Car Tire Squeal Skid Loop” by **Tom Haigh / audible-edge**.
- OpenGameArt:
  <https://opengameart.org/content/car-tire-squeal-skid-loop>
- Original Freesound recording: **71739**.
- License: **Creative Commons Attribution 3.0 Unported (CC BY 3.0)**,
  <https://creativecommons.org/licenses/by/3.0/>.
- Game file: `tire_squeal_loop.wav`.
- Changes: converted to mono 32 kHz/16-bit WAV, level-normalized,
  and circular-crossfaded so the loop has no click at the seam.

This attribution satisfies the CC BY 3.0 requirement for the tyre
recording. CC0 does not legally require attribution for the engine
recordings, but their authors and source pages are credited here as
a matter of provenance.

## Accuracy note

No freely redistributable recording that could be verified as the
exact 1967 Shelby GT500 428 cu in engine was found; the exact-car
libraries located during research are commercial products and were
not copied. The shipped bank is therefore described honestly as
real Mustang/GT500 V8 recordings: GT500 driving loops for the main
voice, plus a 1985 Mustang 5.0 recording for the long idle and the
ignition events. It is not claimed to be a sample-accurate capture
of a 1967 428.

## Runtime layout

- Sixteen RPM points: 900, 1100, 1300, 1500, 1700, 1900, 2100,
  2350, 2600, 2850, 3100, 3350, 3600, 3850, 4100, and 4400 rpm.
- Four continuous bank players crossfade two neighbouring RPM
  points in both throttle layers. A fifth player carries the long
  idle, a sixth carries starter/shutdown one-shots, and a seventh
  carries controlled tyre slip.
- Above the 4400 rpm top recording, the remaining climb to the
  6400 rpm redline is compressed rather than pitch-stretched by an
  unnatural amount.
- All vehicle layers share a dedicated bus with a limiter.
