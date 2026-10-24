import test from 'node:test';
import assert from 'node:assert/strict';

import {
  coupledEngineRpm,
  createPowertrainSpec,
  createPowertrainState,
  engineTorqueAt,
  shapePedalInput,
  speedAtEngineRpm,
  updatePowertrain,
} from '../../src/vehicle/powertrain.js';

const MUSTANG = {
  mass: 1470,
  powerKW: 271,
  topSpeed: 55,
  brakeDecel: 9.2,
  dragArea: 0.78,
  powertrain: {
    engineType: 'na',
    idleRpm: 800,
    redlineRpm: 6800,
    limiterRpm: 7050,
    peakPowerRpm: 5400,
    peakTorqueNm: 540,
    gearCount: 6,
    wheelRadiusM: 0.338,
    efficiency: 0.86,
    shiftUpMs: 150,
    shiftDownMs: 170,
    brakeFrontBias: 0.67,
  },
};

const GTR = {
  mass: 1765,
  powerKW: 421,
  topSpeed: 64,
  brakeDecel: 10.5,
  dragArea: 0.62,
  powertrain: {
    engineType: 'turbo',
    idleRpm: 850,
    redlineRpm: 7200,
    limiterRpm: 7450,
    peakPowerRpm: 6600,
    peakTorqueNm: 637,
    gearCount: 6,
    wheelRadiusM: 0.35,
    efficiency: 0.88,
    shiftUpMs: 105,
    shiftDownMs: 125,
    brakeFrontBias: 0.68,
  },
};

function simulateStraightLine(car, {
  durationS = 30,
  tractionLimitN = 9000,
  throttlePedal = 1,
  initialSpeedMps = 0,
} = {}) {
  const spec = createPowertrainSpec(car);
  const state = createPowertrainState(spec);
  const dt = 1 / 240;
  let speed = initialSpeedMps;
  let distance = 0;
  let timeTo100 = null;
  let accelerationAt10 = null;
  let accelerationAt45 = null;

  for (let step = 0; step < Math.round(durationS / dt); step++) {
    updatePowertrain(state, spec, {
      dt,
      longitudinalSpeedMps: speed,
      throttlePedal,
      brakePedal: 0,
      canDrive: true,
    });

    const drive = Math.max(-tractionLimitN, Math.min(tractionLimitN, state.driveForceN));
    const aero = 0.5 * 1.225 * car.dragArea * speed * Math.abs(speed);
    const rolling = car.mass * 9.81 * 0.012 * Math.tanh(speed / 0.65);
    const acceleration = (drive - aero - rolling) / car.mass;

    if (accelerationAt10 === null && speed >= 10) accelerationAt10 = acceleration;
    if (accelerationAt45 === null && speed >= 45) accelerationAt45 = acceleration;
    if (timeTo100 === null && speed >= 100 / 3.6) timeTo100 = step * dt;

    speed += acceleration * dt;
    distance += speed * dt;
    assert.ok(Number.isFinite(speed), 'speed must stay finite');
    assert.ok(Number.isFinite(state.engineRpm), 'engine RPM must stay finite');
  }

  return { spec, state, speed, distance, timeTo100, accelerationAt10, accelerationAt45 };
}

test('pedal shaping has a dead zone, progressive middle, and exact full travel', () => {
  assert.equal(shapePedalInput(0), 0);
  assert.equal(shapePedalInput(0.03), 0);
  assert.ok(shapePedalInput(0.5) > 0.35 && shapePedalInput(0.5) < 0.5);
  assert.equal(shapePedalInput(1), 1);
});

test('powertrain spec derives gearing from the rated top speed and redline', () => {
  const spec = createPowertrainSpec(MUSTANG);
  assert.ok(Math.abs(speedAtEngineRpm(spec, 6, spec.limiterRpm) - 55) < 0.01);
  assert.ok(speedAtEngineRpm(spec, 1, spec.limiterRpm) > 10);
  assert.ok(speedAtEngineRpm(spec, 1, spec.limiterRpm) < 14);
  assert.ok(engineTorqueAt(spec, 4000) > 350);
  assert.ok(spec.maxBrakeForceN > 12000);
});

test('Mustang and GT-R accelerate with speed-dependent force and reach their geared top speeds', () => {
  const mustang = simulateStraightLine(MUSTANG, {
    durationS: 35,
    tractionLimitN: 8500,
  });
  assert.ok(mustang.timeTo100 > 4.2 && mustang.timeTo100 < 7.5, `Mustang 0–100: ${mustang.timeTo100}`);
  assert.ok(mustang.accelerationAt10 > mustang.accelerationAt45 + 1.5);
  assert.ok(Math.abs(mustang.speed - 55) < 0.65, `Mustang top speed: ${mustang.speed}`);
  assert.equal(mustang.state.gear, 6);

  const gtr = simulateStraightLine(GTR, {
    durationS: 35,
    tractionLimitN: 17500,
  });
  assert.ok(gtr.timeTo100 > 2.4 && gtr.timeTo100 < 4.8, `GT-R 0–100: ${gtr.timeTo100}`);
  assert.ok(gtr.accelerationAt10 > gtr.accelerationAt45 + 2);
  assert.ok(Math.abs(gtr.speed - 64) < 0.75, `GT-R top speed: ${gtr.speed}`);
});

test('partial throttle upshifts earlier, and torque is interrupted during a shift', () => {
  const spec = createPowertrainSpec(MUSTANG);
  const speed = speedAtEngineRpm(spec, 1, spec.redlineRpm * 0.68);

  const partial = createPowertrainState(spec);
  partial.clutch = 1;
  updatePowertrain(partial, spec, {
    dt: 1 / 240,
    longitudinalSpeedMps: speed,
    throttlePedal: 0.25,
    brakePedal: 0,
  });
  assert.equal(partial.pendingGear, 2);

  const full = createPowertrainState(spec);
  full.clutch = 1;
  updatePowertrain(full, spec, {
    dt: 1 / 240,
    longitudinalSpeedMps: speed,
    throttlePedal: 1,
    brakePedal: 0,
  });
  assert.equal(full.pendingGear, null);
  const engagedForce = Math.abs(full.driveForceN);

  for (let i = 0; i < 12; i++) {
    updatePowertrain(partial, spec, {
      dt: 1 / 240,
      longitudinalSpeedMps: speed,
      throttlePedal: 1,
      brakePedal: 0,
    });
  }
  assert.ok(partial.clutch < 0.35);
  assert.ok(Math.abs(partial.driveForceN) < engagedForce * 0.45);

  for (let i = 0; i < 60 && partial.pendingGear !== null; i++) {
    updatePowertrain(partial, spec, {
      dt: 1 / 240,
      longitudinalSpeedMps: speed,
      throttlePedal: 1,
      brakePedal: 0,
    });
  }
  assert.equal(partial.gear, 2);
});

test('service brake, stopped hold, reverse, and return to D form a stable state machine', () => {
  const spec = createPowertrainSpec(MUSTANG);
  const state = createPowertrainState(spec);
  state.gear = 3;
  state.clutch = 1;

  updatePowertrain(state, spec, {
    dt: 1 / 240,
    longitudinalSpeedMps: 22,
    throttlePedal: 0,
    brakePedal: 1,
  });
  assert.equal(state.selector, 'D');
  assert.ok(state.serviceBrakeForceN < -10000);
  assert.equal(state.engineTorqueNm, 0);
  assert.equal(state.driveForceN, state.engineBrakeForceN);

  for (let i = 0; i < 55; i++) {
    updatePowertrain(state, spec, {
      dt: 1 / 240,
      longitudinalSpeedMps: 0,
      throttlePedal: 0,
      brakePedal: 1,
    });
  }
  assert.equal(state.selector, 'R');
  assert.equal(state.gear, -1);
  assert.ok(state.driveForceN < -1000, 'held brake pedal becomes reverse drive only after the stop hold');

  updatePowertrain(state, spec, {
    dt: 1 / 240,
    longitudinalSpeedMps: -5,
    throttlePedal: 1,
    brakePedal: 0,
  });
  assert.ok(state.serviceBrakeForceN > 10000, 'gas brakes backward motion while in R');

  for (let i = 0; i < 40; i++) {
    updatePowertrain(state, spec, {
      dt: 1 / 240,
      longitudinalSpeedMps: 0,
      throttlePedal: 1,
      brakePedal: 0,
    });
  }
  assert.equal(state.selector, 'D');
  assert.equal(state.gear, 1);
});

test('engine braking and speed limiter are distinct from service braking', () => {
  const spec = createPowertrainSpec(GTR);
  const coasting = createPowertrainState(spec);
  coasting.gear = 3;
  coasting.clutch = 1;
  coasting.engineRpm = coupledEngineRpm(spec, 3, 30);
  updatePowertrain(coasting, spec, {
    dt: 1 / 240,
    longitudinalSpeedMps: 30,
    throttlePedal: 0,
    brakePedal: 0,
  });
  assert.ok(coasting.engineBrakeForceN < -100);
  assert.equal(coasting.serviceBrakeForceN, 0);
  assert.equal(coasting.braking, false);

  const limited = createPowertrainState(spec);
  limited.gear = 6;
  limited.clutch = 1;
  limited.engineRpm = spec.limiterRpm;
  updatePowertrain(limited, spec, {
    dt: 1 / 240,
    longitudinalSpeedMps: spec.speedLimiterMps,
    throttlePedal: 1,
    brakePedal: 0,
  });
  assert.equal(limited.limiterActive, true);
  assert.equal(limited.engineTorqueNm, 0);
});
