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

- Shelby: sixteen RPM points, 900–4400 rpm, above which the climb to
  its 6400 rpm redline is compressed rather than pitch-stretched by
  an unnatural amount.
- Audi R8: 1231, 1602, and 3735 rpm anchors; 900 rpm idle and an
  8500 rpm sound redline.
- Camaro SS: 635, 1444, 2265, 3747, and 6478 rpm anchors; 750 rpm
  idle and a 6500 rpm sound redline.
- Mercedes 560 SEL: 805, 999, 1444, 2265, 3747, and 4342 rpm anchors;
  700 rpm idle, a 6000 rpm sound redline, and a quieter master offset.
- `NativeVehicleAudio.configure_for_car()` selects the bank before
  the node enters the tree. Four continuous players crossfade two
  neighbouring RPM points in both throttle layers; a fifth carries
  idle, a sixth starter/shutdown one-shots, and a seventh controlled
  tyre slip.
- All vehicle layers share a dedicated bus with a limiter.
