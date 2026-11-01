# Audio credits — Native 0.2.40

Every vehicle voice in Nitches Horizon is built from real field or
dynamometer recordings, not from an oscillator or a synthesized
engine tone. The Shelby bank dates from 0.2.35; 0.2.40 adds separate
recorded banks for the Audi R8 V10 plus, Chevrolet Camaro SS, and
Mercedes-Benz 560 SEL.

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

## 0.2.40 supplied-car banks

Each new bank is mono 32 kHz/16-bit WAV, is cut to whole crank-cycle
loops, and ships matching `engine_on`, `engine_off`, `engine_idle`,
`engine_start`, and `engine_stop` files. The off-throttle loop is the
matching recording after a cyclic low-pass filter (the loop seam is
preserved) and a 4.5 dB level reduction. The starter event uses the
recorded CC0 starter by **Therancher01**, Freesound sound **610771**,
crossfaded into a pitch-ramped catch from that car's own recorded
bank. The stop event is that car's own idle pitch-ramped from 1.0× to
0.38× over the 0.82 s shutdown. Machine-readable per-clip provenance
is kept in each bank's `bank_manifest.json`.

### Audi R8 V10 plus — CC0 sources

- 1231 rpm: BMW M6 V10 start/idle by **Kinoton**, Freesound **478597**,
  CC0 1.0: <https://freesound.org/people/Kinoton/sounds/478597/>
- 1602 and 3735 rpm, plus idle: Lamborghini Huracán EVO 5.2 V10 by
  **JaimeLopes**, Freesound **564373**, CC0 1.0:
  <https://freesound.org/people/JaimeLopes/sounds/564373/>
- Game directory: `src/assets/audio/audi_r8/`.

### Chevrolet Camaro SS — CC0 and CC BY-SA sources

- 635 rpm/idle: Chevrolet Corvette V8 by **kyles**, Freesound
  **637184**, CC0 1.0:
  <https://freesound.org/people/kyles/sounds/637184/>
- 1444 rpm: Chevrolet Caprice V8 by **romanholtwick**, Freesound
  **391671**, CC0 1.0:
  <https://freesound.org/people/romanholtwick/sounds/391671/>
- 2265 rpm: Ford 460 big-block V8 by **Henaway**, Freesound **127980**,
  CC0 1.0: <https://freesound.org/people/Henaway/sounds/127980/>
- 3747 rpm: Lexus IS F 2UR-GSE V8 dynamometer recording by
  **Altair78**, **CC BY-SA 4.0**:
  <https://commons.wikimedia.org/wiki/File:Lexus_IS-F_dynamometer_2UR-GSE_(2008).ogg>.
  The adapted 3747 rpm on/off loops are distributed under CC BY-SA 4.0.
- 6478 rpm: supercharged Holden V8 by **Ears68**, Freesound **177184**,
  CC0 1.0: <https://freesound.org/people/Ears68/sounds/177184/>
- Game directory: `src/assets/audio/camaro_ss/`.

### Mercedes-Benz 560 SEL — CC0 and CC BY-SA sources

- 805 and 1444 rpm/idle: Chevrolet Caprice V8 by **romanholtwick**,
  Freesound **391671**, CC0 1.0 (link above).
- 999 rpm: Ford F-350 5.4 V8 by **Therancher01**, Freesound **610772**,
  CC0 1.0: <https://freesound.org/people/Therancher01/sounds/610772/>
- 2265 rpm: Ford 460 big-block V8 by **Henaway**, CC0 1.0 (link above).
- 3747 rpm: Lexus IS F 2UR-GSE V8 by **Altair78**, **CC BY-SA 4.0**
  (link above; adapted loops are distributed under the same license).
- 4342 rpm: Ferrari 360 Spider V8 by **PritzProductions**, Freesound
  **241083**, CC0 1.0:
  <https://freesound.org/people/PritzProductions/sounds/241083/>
- Game directory: `src/assets/audio/mercedes_560_sel/`.

### Bugatti Chiron Super Sport (in game: Bygatti Shiron Super Sport) — CC0 sources (0.3.31)

No openly licensed W16 recording exists, so the bank voices the car
with the deepest multi-cylinder CC0 material from the same clip pool,
pitched low: V10 loops under 5000 rpm and a supercharged-V8 top end.
As everywhere in this build the perceived pitch follows the recorded
pulse rate (PSOLA derivations are labelled per anchor in
`bank_manifest.json`); nothing is a synthesized engine tone, and no
clip is claimed to be a real W16 recording.

- 900 and 2000 rpm/idle: BMW M6 V10 start and idle by **Kinoton**,
  Freesound **478597**, CC0 1.0:
  <https://freesound.org/people/Kinoton/sounds/478597/>
- 1602, 3735 and 5000 rpm: Lamborghini Huracan EVO 5.2 V10 by
  **JaimeLopes**, Freesound **564373**, CC0 1.0 (link above).
- 6478 and 7000 rpm: supercharged Holden V8 dyno run-up by
  **Ears68**, Freesound **177184**, CC0 1.0:
  <https://freesound.org/people/Ears68/sounds/177184/>
- Starter layer inside `engine_start.wav`: the shared CC0 starter
  recording by **Therancher01**, Freesound **610771** (as in every
  supplied-car bank).
- Game directory: `src/assets/audio/bugatti_chiron/`.

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
not copied. The shipped Shelby bank is therefore described honestly
as real Mustang/GT500 V8 recordings: GT500 driving loops for the main
voice, plus a 1985 Mustang 5.0 recording for the long idle and the
ignition events. It is not claimed to be a sample-accurate capture
of a 1967 428.

The same rule applies to the 0.2.40 cars. Freely redistributable,
exact, loopable recordings of a 2016 R8 5.2 FSI, a Camaro LT1, and a
W126 M117 were not verified, and the advertised non-commercial exact
recordings were deliberately not used. The shipped banks instead use
same-layout/family real recordings (5.2-litre V10 for the R8 and
cross-plane V8s for the Camaro and 560 SEL), with per-car RPM,
pitch, idle-crossfade, and gain profiles. They are real recorded
engine voices matched to each car's architecture, not claims of
sample-accurate captures of those exact production engines.

## Runtime layout

- Shelby: eighteen RPM points, 900–5600 rpm, above which the climb
  to its 6400 rpm redline is compressed rather than pitch-stretched
  by an unnatural amount (see the 0.2.42 section below).
- Audi R8: 1231, 1602, 2400, 3735, 5200, and 6800 rpm anchors;
  900 rpm idle and an 8500 rpm sound redline.
- Camaro SS: 635, 1050, 1444, 2265, 2900, 3747, 5000, and 6478 rpm
  anchors; 750 rpm idle and a 6500 rpm sound redline.
- Mercedes 560 SEL: 805, 999, 1444, 2265, 2900, 3747, and 5000 rpm
  anchors; 700 rpm idle, a 6000 rpm sound redline, and a quieter
  master offset.
- `NativeVehicleAudio.configure_for_car()` selects the bank before
  the node enters the tree. Four continuous players crossfade two
  neighbouring RPM points in both throttle layers; a fifth carries
  idle, a sixth starter/shutdown one-shots, and a seventh controlled
  tyre slip.
- All vehicle layers share a dedicated bus with a limiter.

## 0.2.42 realism pass — recorded-texture PSOLA anchors and foley

Sparse anchor ladders forced large runtime pitch stretches (the V10
jumped 1602→3735 rpm at up to ×2.13). 0.2.42 densifies every bank
without inventing a synthetic voice: the missing anchors are
pulse-synchronous **TD-PSOLA** derivatives of the same CC0/CC BY-SA
recordings — individual firing pulses from the real loops are
re-timed, so the grain, formants and exhaust texture stay recorded
while the firing rate (perceived pitch) becomes exact. Each derived
anchor is documented in its `bank_manifest.json` with the parent
recording, ratio and method; harmonic-comb verification values are
kept as reference notes. Anchor RPM of real loops was verified by
spectral comb analysis against the firing harmonics (all shipped
anchors measured within 1.3% of their labels).

- Shelby GT500: 900–4400 rpm recorded points plus 5000/5600 rpm
  TD-PSOLA derivatives of the recorded 4400 rpm loops; the climb to
  the 6400 rpm redline is compressed to the 5600 rpm anchor at ×0.80
  so runtime pitch never exceeds ×1.30.
- Audi R8 V10: 1231/1602/3735 rpm recorded anchors plus 2400 (from
  3735), 5200 and 6800 rpm (from 3735) TD-PSOLA derivatives.
- Camaro SS: 635/1444/2265/3747/6478 rpm recorded anchors plus 1050
  (from the 635 Caprice loop), 2900 and 5000 rpm (from the recorded
  Lexus IS F loop, CC BY-SA 4.0) TD-PSOLA derivatives.
- Mercedes 560 SEL: 805/999/1444/2265/3747 rpm recorded anchors plus
  2900/5000 rpm TD-PSOLA derivatives. The earlier 4342 rpm anchor
  (Ferrari V12 recording, CC BY 3.0) was removed: a V12 voice inside
  a luxury V8 was worse than a densified V8 ladder.
- Idle voicing now comes from idle-character recordings rather than
  the mid-rev loops that previously doubled as "idle": Corvette V8
  637184 (Camaro), Chevrolet Caprice 391671 (Mercedes), BMW M6 V10
  478597 (Audi), each looped at whole crank cycles.
- Every bank ships ten exhaust-pop one-shots (`pop_01..10.wav`)
  sliced from transient peaks of its own recorded loops; the runtime
  schedules them on trailing throttle with per-car intensity (R8
  crackles hard, the 560 SEL barely burbles).
- `vehicle_foley/` is secondary by design and deliberately small:
  wind, four road-surface beds, scrape and thump are filtered-noise
  and low-frequency renders; `shift_clunk.wav` is a transient cut
  from the recorded Corvette starter clip (637184); the three impact
  layers are noise burst + low thump renders used only for delta-V
  crashes; `whine_loop.wav` is a discrete-mesh render played at very
  low level for reverse/first gear. The engine voice, exhaust pops
  and tyre squeal remain the real recordings credited above; no
  synthesized engine tone is used anywhere in the runtime.
- Runtime mixing: log-domain (geometric pitch + equal-power)
  crossfades, per-anchor loudness compensation measured from the
  files, a dynamic 18 dB/oct engine lowpass following RPM/load/
  camera, living-idle RPM wander, limiter gate at 19 Hz firing rate,
  downshift throttle-blip sampling, wind ∝ speed², surface-aware
  road beds, and a listener mix per camera (chase/hood/top).
- 0.2.44 adds one more documented foley ambience:
  `vehicle_foley/foliage_rustle.wav`, a synthesized stereo rustle bed
  (band-shaped noise + gust-gated leaf ticks, generated by
  `scripts/generate_foliage_rustle.py`). It plays barely audibly,
  gated by the measured foliage density around the car, and ducks
  under wind/road at speed. Like the rest of the foley folder it is
  ambience only — no engine or tyre voice is synthesized.
