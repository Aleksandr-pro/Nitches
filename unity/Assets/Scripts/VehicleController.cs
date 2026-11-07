using UnityEngine;

/// <summary>
/// Arcade raycast vehicle, written from scratch for the Unity port.
/// Spec numbers mirror the supplied Bugatti catalogue entry of the
/// Godot build (same gearing, mass, tracks and shift calibration),
/// so the car behaves like its Godot twin while the port grows.
/// Physics wheels are suspension rays; model wheels are visual only
/// (see WheelVisuals).
/// </summary>
[RequireComponent(typeof(Rigidbody))]
public class VehicleController : MonoBehaviour
{
    // --- catalogue spec: Bygatti Shiron Super Sport ---
    public float MassKg = 1975f;
    public float[] GearRatios = { 3.20f, 2.188f, 1.583f, 1.167f, 0.881f, 0.690f, 0.542f };
    public float ReverseRatio = 3.0f;
    public float FinalDrive = 2.671f;
    public float IdleRpm = 950f;
    public float RedlineRpm = 7100f;
    public float ShiftUpRpm = 5800f;   // lands the 6->7 shift at 403 km/h, as supplied
    public float ShiftDownRpm = 2600f;
    public float WheelRadius = 0.340f;
    public float Wheelbase = 2.724f;
    public float TrackFront = 1.754f;
    public float TrackRear = 1.679f;
    public float DragArea = 0.69f;     // Cd * A, m^2

    // --- suspension / tyre tuning (arcade) ---
    public float SpringRestLength = 0.40f;
    public float SpringStiffness = 42000f;
    public float SpringDamper = 3600f;
    public float LateralGrip = 9.5f;     // 1/s velocity-kill factor, scaled by load
    public float MaxSteerLowDeg = 30f;
    public float MaxSteerHighDeg = 7f;
    public float DownforceCoef = 3.1f;   // N per (m/s)^2
    public float NitroTorqueMult = 1.45f;

    public int GroundLayer = 8;

    public float SpeedKmh { get; private set; }
    public float Rpm { get; private set; }
    public int Gear { get; private set; }  // -1 reverse, 0..6 forward (display = Gear+1)
    public float ThrottleNow { get; private set; }
    public float SteerAngleDeg { get; private set; }
    public bool AnyWheelGrounded { get; private set; }

    /// <summary>Engine ignition state. When false the car makes no torque and revs to zero.</summary>
    public bool EngineOn { get; private set; }

    /// <summary>Called by the round ignition button (HUD) or keyboard I.</summary>
    public void SetIgnition(bool on)
    {
        EngineOn = on;
        if (!on)
        {
            Gear = 0;
            _rpmSmooth = IdleRpm; // will decay below idle in FixedUpdate toward 0
        }
        Debug.Log($"[Nitches] Ignition {(on ? "ON" : "OFF")}");
    }

    /// <summary>Current spring length per wheel [FL, FR, RL, RR] for visuals.</summary>
    public readonly float[] SpringLengths = new float[4];
    /// <summary>Wheel spin speed, rad/s (signed).</summary>
    public float WheelSpinRad { get; private set; }

    private Rigidbody _rb;
    private readonly Vector3[] _mounts = new Vector3[4]; // FL FR RL RR, local
    private readonly bool[] _grounded = new bool[4];
    private readonly float[] _loads = new float[4];
    private float _shiftTimer;
    private float _rpmSmooth;

    private void Awake()
    {
        _rb = GetComponent<Rigidbody>();
        _rb.mass = MassKg;
        _rb.automaticCenterOfMass = false;
        _rb.centerOfMass = new Vector3(0f, 0.42f, -0.05f);
        _rb.interpolation = RigidbodyInterpolation.Interpolate;
        _rb.collisionDetectionMode = CollisionDetectionMode.ContinuousDynamic;

        float hz = Wheelbase * 0.5f;
        _mounts[0] = new Vector3(-TrackFront * 0.5f, 0.62f, hz);
        _mounts[1] = new Vector3(TrackFront * 0.5f, 0.62f, hz);
        _mounts[2] = new Vector3(-TrackRear * 0.5f, 0.62f, -hz);
        _mounts[3] = new Vector3(TrackRear * 0.5f, 0.62f, -hz);
        for (int i = 0; i < 4; i++) SpringLengths[i] = SpringRestLength;
        Gear = 0;
        _rpmSmooth = IdleRpm;
    }

    private float EngineTorqueNm(float rpm)
    {
        // W16 torque plateau 2000-7000 rpm at 1600 Nm (supplied spec),
        // ramp below, falloff to the limiter.
        if (rpm < 2000f) return Mathf.Lerp(880f, 1600f, Mathf.Clamp01((rpm - IdleRpm) / (2000f - IdleRpm)));
        if (rpm <= 7000f) return 1600f;
        return Mathf.Lerp(1600f, 0f, Mathf.Clamp01((rpm - 7000f) / 200f));
    }

    private void FixedUpdate()
    {
        DriverInput input = DriverInput.Instance;
        float throttle = input != null ? input.Throttle : 0f;
        float brake = input != null ? input.Brake : 0f;
        float steer = input != null ? input.Steer : 0f;
        bool handbrake = input != null && input.Handbrake;
        bool nitro = input != null && input.Nitro;
        ThrottleNow = throttle;

        Vector3 vel = _rb.linearVelocity;
        float forwardSpeed = Vector3.Dot(vel, transform.forward);
        SpeedKmh = forwardSpeed * 3.6f;
        float absSpeed = Mathf.Abs(forwardSpeed);

        // --- gearbox state machine (simple auto box with reverse) ---
        if (Gear >= 0 && brake > 0.5f && absSpeed < 0.6f) Gear = -1;
        else if (Gear < 0 && throttle > 0.5f && absSpeed < 0.6f) Gear = 0;
        // In reverse, "brake" pedal drives backwards; in drive, brake brakes.
        float drivePedal = Gear < 0 ? brake : throttle;
        float brakePedal = Gear < 0 ? throttle : brake;
        if (!EngineOn) drivePedal = 0f; // no torque when the engine is off

        float ratio = Gear < 0 ? ReverseRatio : GearRatios[Mathf.Clamp(Gear, 0, GearRatios.Length - 1)];
        float wheelRad = absSpeed / WheelRadius;
        WheelSpinRad = forwardSpeed / WheelRadius;
        float coupledRpm = wheelRad * ratio * FinalDrive * 60f / (2f * Mathf.PI);

        // Free-rev when wheels are off the ground or clutch would slip.
        float targetRpm;
        if (!EngineOn)
            targetRpm = 0f; // engine stopped
        else if (AnyWheelGrounded)
            targetRpm = Mathf.Max(IdleRpm, coupledRpm);
        else
            targetRpm = Mathf.Lerp(IdleRpm, RedlineRpm, drivePedal);
        _rpmSmooth = Mathf.Lerp(_rpmSmooth, targetRpm, 1f - Mathf.Exp(-8f * Time.fixedDeltaTime));
        Rpm = _rpmSmooth;

        _shiftTimer -= Time.fixedDeltaTime;
        if (Gear >= 0 && _shiftTimer <= 0f)
        {
            if (Rpm > ShiftUpRpm && Gear < GearRatios.Length - 1 && drivePedal > 0.05f)
            {
                Gear++;
                _shiftTimer = 0.28f;
                _rpmSmooth *= GearRatios[Gear] / GearRatios[Gear - 1];
            }
            else if (Rpm < ShiftDownRpm && Gear > 0)
            {
                Gear--;
                _shiftTimer = 0.22f;
            }
        }
        bool shifting = _shiftTimer > 0.16f;

        // --- steering: less angle as speed grows ---
        float steerMax = Mathf.Lerp(MaxSteerLowDeg, MaxSteerHighDeg, Mathf.Clamp01(absSpeed / 55f));
        SteerAngleDeg = steer * steerMax;
        Quaternion steerRot = Quaternion.Euler(0f, SteerAngleDeg, 0f);

        // --- engine force at the driven (all four, AWD 45/55) wheels ---
        float engineTorque = shifting ? 0f : EngineTorqueNm(Rpm) * drivePedal;
        if (nitro) engineTorque *= NitroTorqueMult;
        float wheelTorqueTotal = engineTorque * ratio * FinalDrive * 0.88f;
        float driveForceTotal = wheelTorqueTotal / WheelRadius;
        if (Gear < 0) driveForceTotal = -driveForceTotal;

        int groundMask = 1 << GroundLayer;
        AnyWheelGrounded = false;

        for (int i = 0; i < 4; i++)
        {
            bool front = i < 2;
            Vector3 mountWorld = transform.TransformPoint(_mounts[i]);
            Quaternion wheelRot = transform.rotation * (front ? steerRot : Quaternion.identity);
            Vector3 wheelForward = wheelRot * Vector3.forward;
            Vector3 wheelRight = wheelRot * Vector3.right;

            float rayLen = SpringRestLength + WheelRadius;
            _grounded[i] = Physics.Raycast(mountWorld, -transform.up, out RaycastHit hit, rayLen, groundMask, QueryTriggerInteraction.Ignore);
            if (!_grounded[i])
            {
                SpringLengths[i] = SpringRestLength;
                _loads[i] = 0f;
                continue;
            }
            AnyWheelGrounded = true;

            float springLen = Mathf.Max(0.02f, hit.distance - WheelRadius);
            float compression = SpringRestLength - springLen;
            SpringLengths[i] = springLen;

            Vector3 pointVel = _rb.GetPointVelocity(hit.point);
            float compressionVel = Vector3.Dot(pointVel, transform.up);
            float springForce = compression * SpringStiffness - compressionVel * SpringDamper;
            springForce = Mathf.Max(0f, springForce);
            _loads[i] = springForce;
            _rb.AddForceAtPosition(transform.up * springForce, hit.point);

            float loadFactor = Mathf.Clamp01(springForce / 9000f);

            // Lateral grip: kill sideways slip, weaker at the rear with handbrake.
            float lateralVel = Vector3.Dot(pointVel, wheelRight);
            float grip = LateralGrip * loadFactor;
            if (handbrake && !front) grip *= 0.18f;
            Vector3 lateralForce = -wheelRight * (lateralVel * grip * MassKg * 0.25f);
            _rb.AddForceAtPosition(lateralForce, hit.point);

            // Longitudinal: engine drive + brakes.
            float share = front ? 0.225f : 0.275f; // AWD 45/55
            float longitudinal = driveForceTotal * share;
            float forwardVelAtWheel = Vector3.Dot(pointVel, wheelForward);
            float brakeForce = brakePedal * 14000f * 0.25f;
            if (handbrake && !front) brakeForce += 9000f * 0.25f;
            longitudinal += -Mathf.Sign(forwardVelAtWheel) * brakeForce * loadFactor
                            * Mathf.Clamp01(Mathf.Abs(forwardVelAtWheel) * 4f);
            _rb.AddForceAtPosition(wheelForward * longitudinal, hit.point);
        }

        // --- aero drag + rolling resistance (440 km/h terminal on gearing+drag) ---
        float speed = vel.magnitude;
        if (speed > 0.1f)
        {
            Vector3 drag = -vel.normalized * (0.5f * 1.225f * DragArea * speed * speed);
            _rb.AddForce(drag);
            if (AnyWheelGrounded)
                _rb.AddForce(-vel.normalized * (MassKg * 9.81f * 0.012f));
        }

        // --- downforce keeps the car planted at speed ---
        _rb.AddForce(-transform.up * (forwardSpeed * forwardSpeed * DownforceCoef));

        // Gentle yaw damping so drifts stay controllable.
        Vector3 ang = _rb.angularVelocity;
        ang.y *= (1f - 1.1f * Time.fixedDeltaTime);
        _rb.angularVelocity = ang;
    }

    /// <summary>Local mount point of wheel i (FL FR RL RR).</summary>
    public Vector3 MountLocal(int i) => _mounts[i];
}
