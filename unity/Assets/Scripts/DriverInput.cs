using UnityEngine;

/// <summary>
/// Merged driver input for the prototype: keyboard (classic Input
/// Manager, guarded so a project still set to "Input System only"
/// does not spam exceptions) OR the on-screen hold buttons.
///
/// Ignition (engine start/stop) lives here so the HUD can bind one
/// round button to it. Steering can be driven by a visual wheel,
/// left/right arrows or device tilt; sensitivity, deadzone and wheel
/// size are exposed for the settings screen.
/// </summary>
public class DriverInput : MonoBehaviour
{
    public static DriverInput Instance { get; private set; }

    // --- steering profile (runtime settings, saved later) ---
    public enum SteerMode { VisualWheel, Arrows, Tilt }
    public SteerMode CurrentSteerMode = SteerMode.VisualWheel;
    [Range(0.2f, 3f)] public float SteerSensitivity = 1f;
    [Range(0f, 0.4f)] public float SteerDeadzone = 0.08f;
    [Range(0.6f, 1.6f)] public float SteerWheelSize = 1f; // visual scale hint for HUD

    // Touch/UI state, written by HoldButton and manual touch polling.
    public bool TouchLeft;
    public bool TouchRight;
    public bool TouchGas;
    public bool TouchBrake;
    public bool TouchHandbrake;
    public bool TouchNitro;
    public bool TouchIgnition; // momentary: toggles engine on/off

    // Ignition state: engine produces no torque when off.
    public bool EngineOn { get; private set; }

    // Merged output read by VehicleController.
    public float Steer { get; private set; }      // -1..1 (left..right)
    public float Throttle { get; private set; }   // 0..1
    public float Brake { get; private set; }      // 0..1
    public bool Handbrake { get; private set; }
    public bool Nitro { get; private set; }

    private bool _keyboardBroken;
    private float _steerSmooth;
    private float _tiltSmoother;

    private void Awake()
    {
        Instance = this;
        EngineOn = false;
    }

    /// <summary>Toggle engine ignition from the round ignition button.</summary>
    public void ToggleIgnition()
    {
        TouchIgnition = true; // consumed once in Update
        EngineOn = !EngineOn;
    }

    private void Update()
    {
        float steerTarget = 0f;
        float throttle = 0f;
        float brake = 0f;
        bool handbrake = TouchHandbrake;
        bool nitro = TouchNitro;
        bool ignition = TouchIgnition;
        TouchIgnition = false; // momentary pulse

        if (TouchLeft) steerTarget -= 1f;
        if (TouchRight) steerTarget += 1f;
        if (TouchGas) throttle = 1f;
        if (TouchBrake) brake = 1f;

        // Tilt steering: device roll -> steer, only in Tilt mode.
        if (CurrentSteerMode == SteerMode.Tilt)
        {
            float tilt = Mathf.Clamp(Input.acceleration.x, -1f, 1f);
            _tiltSmoother = Mathf.MoveTowards(_tiltSmoother, tilt, 3f * Time.deltaTime);
            if (Mathf.Abs(_tiltSmoother) > SteerDeadzone)
                steerTarget = _tiltSmoother;
        }

        if (!_keyboardBroken)
        {
            try
            {
                float axis = Input.GetAxisRaw("Horizontal");
                if (CurrentSteerMode == SteerMode.Arrows ||
                    CurrentSteerMode == SteerMode.VisualWheel)
                {
                    if (Mathf.Abs(axis) > 0.01f) steerTarget = axis;
                }
                if (Input.GetKey(KeyCode.W) || Input.GetKey(KeyCode.UpArrow)) throttle = 1f;
                if (Input.GetKey(KeyCode.S) || Input.GetKey(KeyCode.DownArrow)) brake = 1f;
                if (Input.GetKey(KeyCode.Space)) handbrake = true;
                if (Input.GetKey(KeyCode.LeftShift) || Input.GetKey(KeyCode.RightShift)) nitro = true;
                // I key = ignition toggle on keyboard (dev convenience).
                if (Input.GetKeyDown(KeyCode.I)) ToggleIgnition();
            }
            catch (System.Exception)
            {
                _keyboardBroken = true;
                Debug.LogWarning("[Nitches] Classic Input is disabled in this project. " +
                                 "Run menu 'Nitches > 1. Setup project' and restart the editor. " +
                                 "Touch buttons still work.");
            }
        }

        // Apply sensitivity + deadzone to merged steer target.
        steerTarget *= SteerSensitivity;
        if (Mathf.Abs(steerTarget) < SteerDeadzone) steerTarget = 0f;

        // Smooth the steering so button/keyboard taps do not snap the wheels.
        float rate = Mathf.Abs(steerTarget) > Mathf.Abs(_steerSmooth) ? 3.2f : 5.0f;
        _steerSmooth = Mathf.MoveTowards(_steerSmooth, steerTarget, rate * Time.deltaTime);

        Steer = _steerSmooth;
        Throttle = EngineOn ? throttle : 0f; // no throttle when engine off
        Brake = brake;
        Handbrake = handbrake;
        Nitro = nitro;
    }
}
