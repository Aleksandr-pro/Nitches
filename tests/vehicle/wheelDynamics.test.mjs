import test from 'node:test';
import assert from 'node:assert/strict';

import {
  createAxleWheelState,
  longitudinalSlipCurve,
  longitudinalSlipRatio,
  updateAxleWheel,
} from '../../src/vehicle/wheelDynamics.js';

test('longitudinal slip curve peaks near 15 percent and falls when sliding', () => {
  assert.equal(longitudinalSlipCurve(0), 0);
  assert.ok(longitudinalSlipCurve(0.05) > 0.35);
  assert.ok(Math.abs(longitudinalSlipCurve(0.15) - 1) < 0.02);
  assert.ok(longitudinalSlipCurve(0.65) < longitudinalSlipCurve(0.15));
  assert.ok(longitudinalSlipCurve(0.65) > 0.65);
  assert.ok(longitudinalSlipCurve(-0.15) < -0.98);
  assert.ok(Math.abs(longitudinalSlipRatio(12, 10) - (2 / 12)) < 1e-9);
});

test('driven wheel spins up under torque, builds tire force with relaxation, then produces slip', () => {
  const wheel = createAxleWheelState();
  const input = {
    dt: 1 / 240,
    groundSpeedMps: 0,
    driveTorqueNm: 5200,
    brakeTorqueNm: 0,
    loadN: 7800,
    mu: 1.02,
    lateralForceN: 0,
    wheelRadiusM: 0.338,
    inertiaKgM2: 7.5,
  };

  updateAxleWheel(wheel, input);
  const firstForce = wheel.tireForceN;
  assert.ok(wheel.omegaRadPerS > 0);
  assert.ok(firstForce >= 0);

  for (let i = 0; i < 35; i++) updateAxleWheel(wheel, input);
  assert.ok(wheel.surfaceSpeedMps > 1.5);
  assert.ok(wheel.slipRatio > 0.45);
  assert.ok(wheel.tireForceN > 2500);
  assert.ok(wheel.tireForceN > firstForce);
});

test('brake torque creates negative slip, while lateral force consumes longitudinal grip', () => {
  const common = {
    dt: 1 / 240,
    groundSpeedMps: 28,
    driveTorqueNm: 0,
    brakeTorqueNm: 3600,
    loadN: 8200,
    mu: 1.05,
    wheelRadiusM: 0.34,
    inertiaKgM2: 7.5,
    absStrength: 0,
  };

  const straight = createAxleWheelState();
  straight.omegaRadPerS = 28 / 0.34;
  for (let i = 0; i < 70; i++) updateAxleWheel(straight, { ...common, lateralForceN: 0 });
  assert.ok(straight.slipRatio < -0.08);
  assert.ok(straight.tireForceN < -2500);

  const cornering = createAxleWheelState();
  cornering.omegaRadPerS = 28 / 0.34;
  for (let i = 0; i < 70; i++) updateAxleWheel(cornering, { ...common, lateralForceN: 7200 });
  assert.ok(Math.abs(cornering.tireForceN) < Math.abs(straight.tireForceN) * 0.72);
});

test('ABS releases brake torque after excessive braking slip', () => {
  const wheel = createAxleWheelState();
  wheel.omegaRadPerS = 8 / 0.34; // already far too slow for 30 m/s ground speed
  wheel.surfaceSpeedMps = 8;
  wheel.slipRatio = longitudinalSlipRatio(8, 30);

  updateAxleWheel(wheel, {
    dt: 1 / 240,
    groundSpeedMps: 30,
    driveTorqueNm: 0,
    brakeTorqueNm: 6000,
    loadN: 8500,
    mu: 1.05,
    lateralForceN: 0,
    wheelRadiusM: 0.34,
    inertiaKgM2: 7.5,
    absStrength: 0.9,
  });

  assert.equal(wheel.absActive, true);
  assert.ok(wheel.effectiveBrakeTorqueNm < 2600);
  assert.ok(Number.isFinite(wheel.omegaRadPerS));
});
