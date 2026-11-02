using UnityEngine;

/// <summary>
/// Syncs model wheels with the raycast vehicle: a steer pivot per
/// wheel sits at the suspension mount, the model wheel hangs under
/// it at the current spring length and spins around its axle.
/// Index order everywhere: FL, FR, RL, RR.
/// </summary>
public class WheelVisuals : MonoBehaviour
{
    public Transform[] SteerPivots = new Transform[4];
    public Transform[] SpinNodes = new Transform[4];

    private readonly Quaternion[] _spinBase = { Quaternion.identity, Quaternion.identity, Quaternion.identity, Quaternion.identity };
    private VehicleController _vehicle;
    private float _spinAngle;

    public void Bind(VehicleController vehicle, Transform[] pivots, Transform[] spins)
    {
        _vehicle = vehicle;
        SteerPivots = pivots;
        SpinNodes = spins;
        for (int i = 0; i < 4; i++)
            if (SpinNodes[i] != null) _spinBase[i] = SpinNodes[i].localRotation;
    }

    private void LateUpdate()
    {
        if (_vehicle == null) return;
        _spinAngle += _vehicle.WheelSpinRad * Time.deltaTime * Mathf.Rad2Deg;

        for (int i = 0; i < 4; i++)
        {
            Transform pivot = SteerPivots[i];
            if (pivot == null) continue;

            // Pivot follows the chassis mount; the wheel rests at
            // mount height minus current spring length.
            Vector3 mount = _vehicle.MountLocal(i);
            pivot.localPosition = new Vector3(mount.x, mount.y - _vehicle.SpringLengths[i], mount.z);
            float steerDeg = i < 2 ? _vehicle.SteerAngleDeg : 0f;
            pivot.localRotation = Quaternion.Euler(0f, steerDeg, 0f);

            Transform spin = SpinNodes[i];
            if (spin != null)
                spin.localRotation = Quaternion.Euler(_spinAngle, 0f, 0f);
        }
    }
}
