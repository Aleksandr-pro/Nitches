/*
 * Simcade powertrain model for Nitches Horizon.
 *
 * The module is intentionally independent from Three.js and DOM input.  The
 * bicycle/tire model in the game asks it for signed longitudinal forces, then
 * applies its own friction-circle limits per axle.  Units are SI throughout:
 * metres, seconds, kilograms, newtons, newton-metres and revolutions/minute.
 */

const TAU = Math.PI * 2;
const DEFAULT_GEAR_PATTERNS = Object.freeze({
  5: Object.freeze([3.45, 2.05, 1.42, 1.08, 0.82]),
  6: Object.freeze([3.55, 2.24, 1.61, 1.22, 0.98, 0.78]),
  7: Object.freeze([3.88, 2.52, 1.86, 1.42, 1.12, 0.9, 0.72]),
  8: Object.freeze([4.15, 2.82, 2.12, 1.63, 1.28, 1.02, 0.82, 0.66]),
});

function finite(value, fallback) {
  const number = Number(value);
  return Number.isFinite(number) ? number : fallback;
}

function clamp(value, min, max) {
  return Math.max(min, Math.min(max, finite(value, min)));
}

function positive(value, fallback) {
  const number = finite(value, fallback);
  return number > 0 ? number : fallback;
}

function approach(current, target, maxDelta) {
  if (current < target) return Math.min(current + maxDelta, target);
  return Math.max(current - maxDelta, target);
}

function damp(current, target, rate, dt) {
  const alpha = 1 - Math.exp(-Math.max(0, rate) * Math.max(0, dt));
  return current + (target - current) * alpha;
}

function smoothstep(edge0, edge1, value) {
  const t = clamp((value - edge0) / Math.max(edge1 - edge0, 1e-9), 0, 1);
  return t * t * (3 - 2 * t);
}

function sortedCurve(points) {
  return points
    .map(([x, y]) => [finite(x, 0), finite(y, 0)])
    .filter(([x, y]) => Number.isFinite(x) && Number.isFinite(y))
    .sort((a, b) => a[0] - b[0]);
}

/**
 * Apply a small dead zone and a mild progressive curve to a pedal value.
 * Full keyboard/touch input remains exactly 1; half travel is deliberately
 * softer than linear so low-speed control is usable on a touchscreen.
 */
export function shapePedalInput(value, exponent = 1.18) {
  const normalized = clamp(value, 0, 1);
  if (normalized <= 0.03) return 0;
  const withoutDeadZone = (normalized - 0.03) / 0.97;
  return Math.pow(withoutDeadZone, clamp(exponent, 0.5, 2.5));
}

export function interpolateCurve(points, x) {
  if (!Array.isArray(points) || points.length === 0) return 0;
  const curve = points[0]?.length === 2 ? points : sortedCurve(points);
  if (x <= curve[0][0]) return curve[0][1];
  for (let i = 1; i < curve.length; i++) {
    const [x1, y1] = curve[i];
    if (x <= x1) {
      const [x0, y0] = curve[i - 1];
      const width = Math.max(x1 - x0, 1e-9);
      return y0 + (y1 - y0) * ((x - x0) / width);
    }
  }
  return curve[curve.length - 1][1];
}

function normalizedTorqueShape(engineType, idleRpm, redlineRpm) {
  const shapes = {
    turbo: [[0, 0.42], [0.12, 0.66], [0.25, 0.92], [0.42, 1], [0.65, 0.98], [0.85, 0.9], [1, 0.78]],
    na: [[0, 0.34], [0.15, 0.52], [0.35, 0.72], [0.55, 0.86], [0.75, 0.96], [1, 1]],
    diesel: [[0, 0.55], [0.15, 0.92], [0.3, 1], [0.55, 0.92], [0.8, 0.72], [1, 0.55]],
    electric: [[0, 1], [0.35, 1], [0.65, 0.68], [0.85, 0.44], [1, 0.3]],
  };
  const shape = shapes[engineType] || shapes.turbo;
  return shape.map(([fraction, value]) => [
    idleRpm + (redlineRpm - idleRpm) * fraction,
    value,
  ]);
}

/**
 * Normalize the compact vehicle data used by the game into a complete spec.
 * Existing fields (`mass`, `powerKW`, `topSpeed`, `brakeDecel`) are supported
 * so external/catalogue vehicles can provide the same contract later.
 */
export function createPowertrainSpec(car = {}) {
  const config = car.powertrain || {};
  const massKg = positive(car.massKg ?? car.mass, 1400);
  const ratedPowerW = positive(car.powerW ?? (finite(car.powerKW, 220) * 1000), 220000);
  const ratedTopSpeedMps = positive(
    config.speedLimiterMps ?? car.topSpeedMps ?? car.topSpeed,
    55,
  );
  const idleRpm = positive(config.idleRpm, 850);
  const redlineRpm = Math.max(idleRpm + 1000, positive(config.redlineRpm, 6800));
  const limiterRpm = Math.max(
    redlineRpm,
    positive(config.limiterRpm, redlineRpm * 1.035),
  );
  const peakPowerRpm = clamp(
    positive(config.peakPowerRpm, redlineRpm * 0.9),
    idleRpm + 250,
    redlineRpm,
  );
  const wheelRadiusM = clamp(
    positive(config.wheelRadiusM ?? car.wheelRadiusM ?? car.wheelRadius, 0.34),
    0.2,
    0.55,
  );

  const suppliedRatios = Array.isArray(config.gearRatios)
    ? config.gearRatios.map((ratio) => positive(ratio, 0)).filter((ratio) => ratio > 0)
    : [];
  const requestedGearCount = Math.round(clamp(config.gearCount, 5, 8)) || 6;
  const gearRatios = suppliedRatios.length >= 3
    ? suppliedRatios
    : [...(DEFAULT_GEAR_PATTERNS[requestedGearCount] || DEFAULT_GEAR_PATTERNS[6])];

  const wheelCircumferenceM = TAU * wheelRadiusM;
  const topGearRatio = gearRatios[gearRatios.length - 1];
  const finalDrive = positive(
    config.finalDrive,
    (limiterRpm * wheelCircumferenceM) / (60 * topGearRatio * ratedTopSpeedMps),
  );
  const reverseRatio = positive(config.reverseRatio, gearRatios[0] * 0.92);

  let torqueCurveNm;
  if (Array.isArray(config.torqueCurveNm) && config.torqueCurveNm.length >= 2) {
    torqueCurveNm = sortedCurve(config.torqueCurveNm);
  } else {
    const shape = normalizedTorqueShape(config.engineType || 'turbo', idleRpm, redlineRpm);
    const shapeAtPeakPower = Math.max(interpolateCurve(shape, peakPowerRpm), 0.05);
    const derivedPeakTorque = ratedPowerW / ((peakPowerRpm * TAU) / 60) / shapeAtPeakPower;
    const peakTorqueNm = positive(config.peakTorqueNm, derivedPeakTorque);
    torqueCurveNm = shape.map(([rpm, normalized]) => [rpm, normalized * peakTorqueNm]);
  }

  const peakTorqueNm = Math.max(...torqueCurveNm.map(([, torque]) => torque));
  const brakeDecel = positive(car.brakeDecel, 9.5);
  const maxBrakeTorqueNm = positive(
    config.maxBrakeTorqueNm,
    massKg * brakeDecel * wheelRadiusM,
  );

  return Object.freeze({
    massKg,
    ratedPowerW,
    ratedTopSpeedMps,
    speedLimiterMps: positive(config.speedLimiterMps, ratedTopSpeedMps),
    idleRpm,
    redlineRpm,
    limiterRpm,
    peakPowerRpm,
    launchRpm: clamp(
      positive(config.launchRpm, idleRpm + 1450),
      idleRpm + 250,
      redlineRpm,
    ),
    torqueCurveNm: Object.freeze(torqueCurveNm.map(([rpm, torque]) => Object.freeze([rpm, torque]))),
    peakTorqueNm,
    engineBrakeNm: positive(config.engineBrakeNm, Math.max(28, peakTorqueNm * 0.12)),
    gearRatios: Object.freeze([...gearRatios]),
    reverseRatio,
    finalDrive,
    wheelRadiusM,
    efficiency: clamp(finite(config.efficiency, 0.88), 0.55, 0.98),
    shiftUpS: clamp(positive(config.shiftUpMs, 135) / 1000, 0.02, 0.6),
    shiftDownS: clamp(positive(config.shiftDownMs, 155) / 1000, 0.02, 0.7),
    maxBrakeTorqueNm,
    maxBrakeForceN: maxBrakeTorqueNm / wheelRadiusM,
    brakeFrontBias: clamp(finite(config.brakeFrontBias, 0.68), 0.35, 0.85),
    maxReverseSpeedMps: clamp(positive(config.maxReverseSpeedMps, 9), 3, 16),
    selectorHoldS: clamp(finite(config.selectorHoldS, 0.09), 0, 0.5),
  });
}

export function gearRatioFor(spec, gear) {
  if (gear === -1) return spec.reverseRatio;
  if (!Number.isInteger(gear) || gear < 1) return 0;
  return spec.gearRatios[gear - 1] || 0;
}

export function coupledEngineRpm(spec, gear, longitudinalSpeedMps) {
  const ratio = gearRatioFor(spec, gear);
  if (!ratio) return spec.idleRpm;
  const wheelRpm = Math.abs(longitudinalSpeedMps) / (TAU * spec.wheelRadiusM) * 60;
  return wheelRpm * ratio * spec.finalDrive;
}

export function speedAtEngineRpm(spec, gear, rpm) {
  const ratio = gearRatioFor(spec, gear);
  if (!ratio) return 0;
  return (Math.max(0, rpm) / 60) * TAU * spec.wheelRadiusM / (ratio * spec.finalDrive);
}

export function engineTorqueAt(spec, rpm) {
  return Math.max(0, interpolateCurve(spec.torqueCurveNm, rpm));
}

export function createPowertrainState(spec) {
  return resetPowertrainState({}, spec);
}

export function resetPowertrainState(state, spec) {
  state.selector = 'D';
  state.gear = 1;
  state.pendingGear = null;
  state.shiftTimerS = 0;
  state.shiftDurationS = 0;
  state.shiftHoldS = 0;
  state.engineRpm = spec.idleRpm;
  state.rpmRatio = clamp(spec.idleRpm / spec.limiterRpm, 0, 1);
  state.clutch = 0;
  state.stopHoldS = 0;
  state.drivePedal = 0;
  state.serviceBrakePedal = 0;
  state.engineTorqueNm = 0;
  state.engineLoad = 0;
  state.wheelTorqueNm = 0;
  state.driveForceN = 0;
  state.engineBrakeForceN = 0;
  state.serviceBrakeForceN = 0;
  state.braking = false;
  state.limiterActive = false;
  state.shifting = false;
  return state;
}

function startShift(state, spec, targetGear) {
  if (!Number.isInteger(targetGear) || targetGear === state.gear) return false;
  if (targetGear < 1 || targetGear > spec.gearRatios.length) return false;
  state.pendingGear = targetGear;
  state.shiftDurationS = targetGear > state.gear ? spec.shiftUpS : spec.shiftDownS;
  state.shiftTimerS = state.shiftDurationS;
  state.shifting = true;
  return true;
}

function updateAutomaticGear(state, spec, speedMps, drivePedal) {
  if (state.selector !== 'D' || state.pendingGear !== null) return;
  if (!Number.isInteger(state.gear) || state.gear < 1) state.gear = 1;

  const coupledRpm = coupledEngineRpm(spec, state.gear, speedMps);
  // While coasting, hold the current gear for engine braking unless the
  // engine is genuinely approaching the limiter (for example downhill).
  const upshiftRpm = drivePedal <= 0.03
    ? spec.redlineRpm * 0.97
    : spec.redlineRpm * (0.54 + 0.43 * clamp(drivePedal, 0, 1));
  if (
    state.gear < spec.gearRatios.length
    && Math.abs(speedMps) > 1.5
    && coupledRpm >= upshiftRpm
  ) {
    startShift(state, spec, state.gear + 1);
    return;
  }

  if (state.gear <= 1) return;
  const lowerCoupledRpm = coupledEngineRpm(spec, state.gear - 1, speedMps);
  if (lowerCoupledRpm > spec.limiterRpm * 0.94) return;

  const lowRpm = Math.max(spec.idleRpm + 500, spec.redlineRpm * 0.27);
  // Anti-hunting hysteresis.  The first-to-second step is wide: an upshift
  // at 97% lands near 58% in second.  A fixed 62% kickdown threshold would
  // immediately request first again, so derive the threshold from the
  // actual adjacent-gear step and require RPM to fall materially below
  // the post-upshift operating point before kickdown is allowed.
  const currentRatio = gearRatioFor(spec, state.gear);
  const lowerRatio = gearRatioFor(spec, state.gear - 1);
  const postUpshiftRpm = lowerRatio > 0
    ? upshiftRpm * (currentRatio / lowerRatio)
    : spec.redlineRpm * 0.58;
  const kickdownRpm = Math.min(spec.redlineRpm * 0.62, postUpshiftRpm * 0.86);
  const kickdown = drivePedal > 0.82
    && coupledRpm < kickdownRpm
    && finite(state.shiftHoldS, 0) <= 0;
  const dangerouslyLow = coupledRpm > 0 && coupledRpm < Math.max(spec.idleRpm + 260, spec.redlineRpm * 0.2);
  if ((coupledRpm > 0 && coupledRpm < lowRpm && (finite(state.shiftHoldS, 0) <= 0 || dangerouslyLow)) || kickdown) {
    startShift(state, spec, state.gear - 1);
  }
}

/**
 * Advance the gearbox/engine by one fixed physics step.
 *
 * Mobile control semantics are intentionally Horizon-like:
 * - in D the brake button brakes, then becomes reverse after a stopped hold;
 * - in R the gas button brakes backward motion, then returns to D at a stop.
 */
export function updatePowertrain(state, spec, input = {}) {
  const dt = clamp(finite(input.dt, 0), 0, 0.05);
  const speedMps = finite(input.longitudinalSpeedMps, 0);
  // Gearbox output follows the driven wheels.  During a burnout this is
  // deliberately different from body speed, causing RPM flare and allowing
  // the automatic gearbox to react to wheel speed rather than GPS speed.
  const drivenWheelSpeedMps = finite(input.drivenWheelSpeedMps, speedMps);
  const throttlePedal = clamp(input.throttlePedal, 0, 1);
  const brakePedal = clamp(input.brakePedal, 0, 1);
  const canDrive = input.canDrive !== false;

  if (!state || !spec) throw new TypeError('updatePowertrain requires state and spec');
  if (!Number.isFinite(state.engineRpm)) resetPowertrainState(state, spec);

  if (!canDrive || dt === 0) {
    state.engineRpm = damp(state.engineRpm, spec.idleRpm, 8, Math.max(dt, 1 / 240));
    state.rpmRatio = clamp(state.engineRpm / spec.limiterRpm, 0, 1);
    state.clutch = approach(state.clutch, 0, dt * 7);
    state.drivePedal = 0;
    state.serviceBrakePedal = 0;
    state.engineTorqueNm = 0;
    state.engineLoad = 0;
    state.wheelTorqueNm = 0;
    state.driveForceN = 0;
    state.engineBrakeForceN = 0;
    state.serviceBrakeForceN = 0;
    state.braking = false;
    state.limiterActive = false;
    return state;
  }

  // Selector state machine.  A short stopped hold prevents the old abrupt
  // transition from service brake to reverse while the car is still rolling.
  if (state.selector === 'D') {
    if (state.gear < 1) state.gear = 1;
    if (brakePedal > 0.04 && Math.abs(speedMps) <= 0.14) {
      state.stopHoldS += dt;
      if (state.stopHoldS >= spec.selectorHoldS) {
        state.selector = 'R';
        state.gear = -1;
        state.pendingGear = null;
        state.shiftTimerS = 0;
        state.shiftDurationS = 0;
        state.shifting = false;
        state.stopHoldS = 0;
      }
    } else {
      state.stopHoldS = 0;
    }
  } else {
    state.selector = 'R';
    state.gear = -1;
    if (throttlePedal > 0.04 && Math.abs(speedMps) <= 0.14) {
      state.stopHoldS += dt;
      if (state.stopHoldS >= Math.min(0.12, spec.selectorHoldS)) {
        state.selector = 'D';
        state.gear = 1;
        state.stopHoldS = 0;
      }
    } else {
      state.stopHoldS = 0;
    }
  }

  state.shiftHoldS = Math.max(0, finite(state.shiftHoldS, 0) - dt);

  // Complete an in-progress shift before making another automatic decision.
  if (state.pendingGear !== null) {
    state.shiftTimerS -= dt;
    if (state.shiftTimerS <= 0) {
      const completedGear = state.pendingGear;
      const wasUpshift = completedGear > state.gear;
      state.gear = completedGear;
      state.pendingGear = null;
      state.shiftTimerS = 0;
      state.shiftDurationS = 0;
      state.shifting = false;
      // Let the new gear actually pull for a beat.  This also makes each
      // shift perceptible instead of a stutter around one threshold.
      state.shiftHoldS = wasUpshift ? 0.55 : 0.28;
    }
  }

  let drivePedal = state.selector === 'R' ? brakePedal : throttlePedal;
  let serviceBrakePedal = state.selector === 'R' ? throttlePedal : brakePedal;

  // If the player presses both pedals while moving in the selected
  // direction, the service brake wins.  At a standstill the selector logic
  // above is allowed to arbitrate instead of burning the clutch forever.
  const movingSelectedDirection = state.selector === 'R' ? speedMps < -0.2 : speedMps > 0.2;
  if (movingSelectedDirection && serviceBrakePedal > 0.03) drivePedal = 0;

  updateAutomaticGear(state, spec, drivenWheelSpeedMps, drivePedal);

  const activeGear = state.gear;
  const ratio = gearRatioFor(spec, activeGear);
  const coupledRpm = coupledEngineRpm(spec, activeGear, drivenWheelSpeedMps);
  const pendingCoupledRpm = state.pendingGear === null
    ? coupledRpm
    : coupledEngineRpm(spec, state.pendingGear, drivenWheelSpeedMps);

  // Clutch model: open during shifts, deliberately slipping in first/reverse
  // at launch, and open at a standstill with no drive request.
  let clutchTarget = 1;
  if (state.pendingGear !== null) {
    clutchTarget = 0;
  } else if (Math.abs(drivenWheelSpeedMps) < 0.12 && drivePedal <= 0.02) {
    clutchTarget = 0;
  } else if (activeGear === 1 || activeGear === -1) {
    const engagement = smoothstep(spec.launchRpm * 0.34, spec.launchRpm * 0.98, coupledRpm);
    clutchTarget = drivePedal > 0.02
      ? 0.34 + 0.66 * engagement
      : 0.12 + 0.55 * engagement;
  }
  state.clutch = damp(
    clamp(state.clutch, 0, 1),
    clutchTarget,
    state.pendingGear !== null ? 22 : 10,
    dt,
  );

  // Engine speed.  At launch the engine can sit above the coupled wheelspeed;
  // once the clutch is engaged it follows the wheels through the gear ratio.
  let desiredRpm;
  if (state.pendingGear !== null) {
    desiredRpm = Math.max(spec.idleRpm, pendingCoupledRpm);
    if (state.pendingGear < activeGear && drivePedal > 0.05) desiredRpm += 220;
  } else if (drivePedal > 0.02 && (activeGear === 1 || activeGear === -1)) {
    const launchTarget = spec.launchRpm + drivePedal * 550;
    desiredRpm = Math.max(coupledRpm, launchTarget * (1 - state.clutch) + coupledRpm * state.clutch);
  } else {
    desiredRpm = Math.max(
      spec.idleRpm,
      coupledRpm * state.clutch + spec.idleRpm * (1 - state.clutch),
    );
  }
  state.engineRpm = clamp(
    damp(state.engineRpm, desiredRpm, state.pendingGear !== null ? 16 : 24, dt),
    spec.idleRpm * 0.82,
    spec.limiterRpm * 1.01,
  );

  const speedLimiter = positive(input.speedLimiterMps, spec.speedLimiterMps);
  const atForwardLimiter = state.selector === 'D' && speedMps >= speedLimiter;
  const atReverseLimiter = state.selector === 'R' && speedMps <= -spec.maxReverseSpeedMps;
  const atRevLimiter = state.engineRpm >= spec.limiterRpm;
  state.limiterActive = atForwardLimiter || atReverseLimiter || atRevLimiter;

  const direction = state.selector === 'R' ? -1 : 1;
  let engineTorqueNm = engineTorqueAt(spec, state.engineRpm) * drivePedal * state.clutch;
  if (state.limiterActive && drivePedal > 0) engineTorqueNm = 0;

  const wheelTorqueNm = engineTorqueNm * ratio * spec.finalDrive * spec.efficiency;
  let driveForceN = direction * wheelTorqueNm / spec.wheelRadiusM;

  // Engine braking is part of the driven-axle force.  It fades out with the
  // clutch near a stop so it cannot drag the stopped car backwards.
  let engineBrakeForceN = 0;
  if (drivePedal <= 0.03 && Math.abs(speedMps) > 0.25 && ratio > 0) {
    const rpmLoad = clamp(
      (state.engineRpm - spec.idleRpm) / Math.max(spec.limiterRpm - spec.idleRpm, 1),
      0,
      1,
    );
    const engineBrakeTorque = spec.engineBrakeNm * (0.35 + 0.65 * rpmLoad) * state.clutch;
    engineBrakeForceN = -Math.sign(speedMps)
      * engineBrakeTorque * ratio * spec.finalDrive * spec.efficiency
      / spec.wheelRadiusM;
    driveForceN += engineBrakeForceN;
  }

  if (state.selector === 'D' && input.boostForceN) {
    driveForceN += Math.max(0, finite(input.boostForceN, 0));
  }

  const serviceBrakeForceN = Math.abs(speedMps) > 0.015 && serviceBrakePedal > 0
    ? -Math.sign(speedMps) * spec.maxBrakeForceN * serviceBrakePedal
    : 0;

  state.drivePedal = drivePedal;
  state.serviceBrakePedal = serviceBrakePedal;
  state.engineTorqueNm = engineTorqueNm;
  state.engineLoad = clamp(drivePedal * state.clutch, 0, 1);
  state.wheelTorqueNm = wheelTorqueNm;
  state.driveForceN = driveForceN;
  state.engineBrakeForceN = engineBrakeForceN;
  state.serviceBrakeForceN = serviceBrakeForceN;
  state.braking = serviceBrakePedal > 0.03;
  state.shifting = state.pendingGear !== null;
  state.rpmRatio = clamp(state.engineRpm / spec.limiterRpm, 0, 1);
  return state;
}
