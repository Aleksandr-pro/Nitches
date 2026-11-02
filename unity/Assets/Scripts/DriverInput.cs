using UnityEngine;

/// <summary>
/// Merged driver input for the prototype: keyboard (classic Input
/// Manager, guarded so a project still set to "Input System only"
/// does not spam exceptions) OR the on-screen hold buttons.
/// The Nitches editor setup menu switches Active Input Handling to
/// "Both", after an editor restart both paths are live.
/// </summary>
public class DriverInput : MonoBehaviour
{
    public static DriverInput Instance { get; private set; }

    // Touch/UI state, written by HoldButton and manual touch polling.
    public bool TouchLeft;
    public bool TouchRight;
    public bool TouchGas;
    public bool TouchBrake;
    public bool TouchHandbrake;
    public bool TouchNitro;

    // Merged output read by VehicleController.
    public float Steer { get; private set; }      // -1..1 (left..right)
    public float Throttle { get; private set; }   // 0..1
    public float Brake { get; private set; }      // 0..1
    public bool Handbrake { get; private set; }
    public bool Nitro { get; private set; }

    private bool _keyboardBroken;
    private float _steerSmooth;

    private void Awake()
    {
        Instance = this;
    }

    private void Update()
    {
        float steerTarget = 0f;
        float throttle = 0f;
        float brake = 0f;
        bool handbrake = TouchHandbrake;
        bool nitro = TouchNitro;

        if (TouchLeft) steerTarget -= 1f;
        if (TouchRight) steerTarget += 1f;
        if (TouchGas) throttle = 1f;
        if (TouchBrake) brake = 1f;

        if (!_keyboardBroken)
        {
            try
            {
                float axis = Input.GetAxisRaw("Horizontal");
                if (Mathf.Abs(axis) > 0.01f) steerTarget = axis;
                if (Input.GetKey(KeyCode.W) || Input.GetKey(KeyCode.UpArrow)) throttle = 1f;
                if (Input.GetKey(KeyCode.S) || Input.GetKey(KeyCode.DownArrow)) brake = 1f;
                if (Input.GetKey(KeyCode.Space)) handbrake = true;
                if (Input.GetKey(KeyCode.LeftShift) || Input.GetKey(KeyCode.RightShift)) nitro = true;
            }
            catch (System.Exception)
            {
                _keyboardBroken = true;
                Debug.LogWarning("[Nitches] Classic Input is disabled in this project. " +
                                 "Run menu 'Nitches > 1. Setup project' and restart the editor. Touch buttons still work.");
            }
        }

        // Smooth the steering so button/keyboard taps do not snap the wheels.
        float rate = Mathf.Abs(steerTarget) > Mathf.Abs(_steerSmooth) ? 3.2f : 5.0f;
        _steerSmooth = Mathf.MoveTowards(_steerSmooth, steerTarget, rate * Time.deltaTime);

        Steer = _steerSmooth;
        Throttle = throttle;
        Brake = brake;
        Handbrake = handbrake;
        Nitro = nitro;
    }
}
