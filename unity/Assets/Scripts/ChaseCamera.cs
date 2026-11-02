using UnityEngine;

/// <summary>Simple smoothed chase camera with a speed FOV kick.</summary>
[RequireComponent(typeof(Camera))]
public class ChaseCamera : MonoBehaviour
{
    public Transform Target;
    public VehicleController Vehicle;
    public Vector3 Offset = new Vector3(0f, 2.3f, -7.8f);
    public float PositionDamp = 6f;
    public float LookAhead = 9f;

    private Camera _cam;

    private void Awake()
    {
        _cam = GetComponent<Camera>();
    }

    private void LateUpdate()
    {
        if (Target == null) return;

        Vector3 desired = Target.TransformPoint(Offset);
        float t = 1f - Mathf.Exp(-PositionDamp * Time.deltaTime);
        transform.position = Vector3.Lerp(transform.position, desired, t);

        Vector3 look = Target.position + Vector3.up * 1.1f + Target.forward * LookAhead;
        transform.LookAt(look, Vector3.up);

        if (Vehicle != null && _cam != null)
        {
            float targetFov = Mathf.Lerp(62f, 74f, Mathf.Clamp01(Mathf.Abs(Vehicle.SpeedKmh) / 320f));
            _cam.fieldOfView = Mathf.Lerp(_cam.fieldOfView, targetFov, 1f - Mathf.Exp(-3f * Time.deltaTime));
        }
    }
}
