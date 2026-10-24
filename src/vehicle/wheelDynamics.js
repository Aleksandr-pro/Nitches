/*
 * Longitudinal per-axle wheel model.
 *
 * The previous physics simply clipped engine force to the tire friction
 * circle.  That is stable, but it has no wheel inertia, no slip-ratio peak,
 * no lock-up, and therefore very little of the launch/braking character a
 * player can feel.  This module keeps the model deliberately small enough
 * for a phone: one angular velocity per axle, a Pacejka-like slip curve, a
 * short tire-relaxation lag, and simcade ABS modulation.
 */

function finite(value, fallback) {
  const number = Number(value);
  return Number.isFinite(number) ? number : fallback;
}

function clamp(value, min, max) {
  return Math.max(min, Math.min(max, finite(value, min)));
}

function damp(current, target, rate, dt) {
  const alpha = 1 - Math.exp(-Math.max(0, rate) * Math.max(0, dt));
  return current + (target - current) * alpha;
}

/**
 * Normalized longitudinal tire curve.  It rises to a peak near 15% slip and
 * then falls toward the sliding value instead of staying perfectly flat.
 */
export function longitudinalSlipCurve(slipRatio, {
  peakSlip = 0.15,
  slidingFactor = 0.74,
} = {}) {
  const slip = finite(slipRatio, 0);
  const magnitude = Math.abs(slip);
  if (magnitude < 1e-9) return 0;

  let normalized;
  if (magnitude <= peakSlip) {
    normalized = Math.sin((Math.PI / 2) * Math.pow(magnitude / peakSlip, 0.78));
  } else {
    const decay = 1 - Math.exp(-(magnitude - peakSlip) / 0.24);
    normalized = 1 - (1 - slidingFactor) * decay;
  }
  return Math.sign(slip) * clamp(normalized, 0, 1);
}

export function longitudinalSlipRatio(surfaceSpeedMps, groundSpeedMps) {
  const surface = finite(surfaceSpeedMps, 0);
  const ground = finite(groundSpeedMps, 0);
  const denominator = Math.max(Math.abs(surface), Math.abs(ground), 2.2);
  return clamp((surface - ground) / denominator, -1.5, 1.5);
}

export function createAxleWheelState() {
  return resetAxleWheelState({}, 0);
}

export function resetAxleWheelState(state, surfaceSpeedMps = 0, wheelRadiusM = 0.34) {
  const radius = Math.max(0.15, finite(wheelRadiusM, 0.34));
  state.omegaRadPerS = finite(surfaceSpeedMps, 0) / radius;
  state.surfaceSpeedMps = finite(surfaceSpeedMps, 0);
  state.slipRatio = 0;
  state.tireForceN = 0;
  state.effectiveBrakeTorqueNm = 0;
  state.absActive = false;
  return state;
}

function updateAxleWheelSubstep(state, input, dt) {
  const groundSpeedMps = finite(input.groundSpeedMps, 0);
  const driveTorqueNm = finite(input.driveTorqueNm, 0);
  const brakeTorqueNm = Math.abs(finite(input.brakeTorqueNm, 0));
  const loadN = Math.max(0, finite(input.loadN, 0));
  const mu = Math.max(0, finite(input.mu, 0));
  const lateralForceN = finite(input.lateralForceN, 0);
  const wheelRadiusM = clamp(finite(input.wheelRadiusM, 0.34), 0.15, 0.6);
  const inertiaKgM2 = clamp(finite(input.inertiaKgM2, 7.5), 0.8, 30);
  const absStrength = clamp(finite(input.absStrength, 0.65), 0, 1);

  const surfaceSpeedMps = state.omegaRadPerS * wheelRadiusM;
  const slipRatio = longitudinalSlipRatio(surfaceSpeedMps, groundSpeedMps);

  // Combined-slip budget: lateral force consumes part of the same friction
  // circle, leaving only the remainder for drive/braking force.
  const frictionLimitN = mu * loadN;
  const lateralFraction = frictionLimitN > 0
    ? clamp(Math.abs(lateralForceN) / frictionLimitN, 0, 0.995)
    : 0;
  const longitudinalLimitN = frictionLimitN * Math.sqrt(Math.max(0, 1 - lateralFraction * lateralFraction));
  const targetTireForceN = longitudinalLimitN * longitudinalSlipCurve(slipRatio, {
    peakSlip: finite(input.peakSlip, 0.15),
    slidingFactor: finite(input.slidingFactor, 0.74),
  });

  // A real tire does not build force instantly.  This relaxation is also
  // what makes a launch readable instead of an on/off grip switch.
  const relaxationRate = clamp(finite(input.relaxationRate, 26), 4, 80);
  state.tireForceN = damp(
    finite(state.tireForceN, 0),
    targetTireForceN,
    relaxationRate,
    dt,
  );

  // Simcade ABS: once braking slip is well past the peak, release enough
  // brake torque for the wheel to spin back up.  Strength comes from the
  // selected assist profile; Drift therefore locks more readily.
  const brakingSlip = Math.abs(groundSpeedMps) > 0.05
    ? -Math.sign(groundSpeedMps) * slipRatio
    : 0;
  let effectiveBrakeTorqueNm = brakeTorqueNm;
  state.absActive = false;
  if (brakeTorqueNm > 0 && Math.abs(groundSpeedMps) > 2.5 && brakingSlip > 0.17) {
    const excess = clamp((brakingSlip - 0.17) / 0.22, 0, 1);
    const release = absStrength * excess;
    effectiveBrakeTorqueNm *= 1 - 0.82 * release;
    state.absActive = release > 0.08;
  }

  const brakeDirection = Math.abs(state.omegaRadPerS) > 0.04
    ? Math.sign(state.omegaRadPerS)
    : Math.sign(groundSpeedMps);
  const netTorqueNm = driveTorqueNm
    - brakeDirection * effectiveBrakeTorqueNm
    - state.tireForceN * wheelRadiusM;

  state.omegaRadPerS += (netTorqueNm / inertiaKgM2) * dt;

  // Static brake hold: do not let the numerical wheel jitter through zero
  // when the service brake is clearly stronger than the remaining torques.
  if (
    effectiveBrakeTorqueNm > Math.abs(driveTorqueNm - state.tireForceN * wheelRadiusM)
    && Math.abs(groundSpeedMps) < 0.14
    && Math.abs(state.omegaRadPerS) < 1.25
  ) {
    state.omegaRadPerS = 0;
  }

  state.surfaceSpeedMps = state.omegaRadPerS * wheelRadiusM;
  state.slipRatio = longitudinalSlipRatio(state.surfaceSpeedMps, groundSpeedMps);
  state.effectiveBrakeTorqueNm = effectiveBrakeTorqueNm;
  return state;
}

/**
 * Advance one axle.  Input torques are totals for both wheels on that axle;
 * brake torque is a positive magnitude.
 */
export function updateAxleWheel(state, input = {}) {
  if (!state) throw new TypeError('updateAxleWheel requires a wheel state');
  if (!Number.isFinite(state.omegaRadPerS)) resetAxleWheelState(state);

  const dt = clamp(finite(input.dt, 0), 0, 0.05);
  if (dt === 0) return state;

  // Longitudinal tire stiffness is very high at parking speeds.  Two
  // substeps at the game's 240 Hz physics rate keep launch/lock-up stable
  // without requiring a fully implicit tire solver.
  const substeps = dt > (1 / 360) ? 2 : 1;
  const substepDt = dt / substeps;
  for (let i = 0; i < substeps; i++) updateAxleWheelSubstep(state, input, substepDt);
  return state;
}
