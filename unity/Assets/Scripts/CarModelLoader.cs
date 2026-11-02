using System;
using UnityEngine;

/// <summary>
/// Loads a supplied-car GLB from StreamingAssets/Cars at runtime via
/// glTFast, finds the contract wheel nodes (Wheel_FL/FR/RL/RR + Spin),
/// auto-fixes the nose direction (front wheels must sit at +Z), and
/// hands pivots/spins to WheelVisuals. Any failure keeps the fallback
/// box car drivable and reports through the status callback.
/// </summary>
public class CarModelLoader : MonoBehaviour
{
    private GLTFast.GltfImport _import; // kept alive while the instance lives

    public async void Load(string glbFileName, VehicleController vehicle, WheelVisuals visuals,
                           GameObject fallbackToHide, Action<string> status)
    {
        try
        {
            status?.Invoke("LOADING MODEL: " + glbFileName);
            string path = System.IO.Path.Combine(Application.streamingAssetsPath, "Cars", glbFileName)
                .Replace("\\", "/");

            _import = new GLTFast.GltfImport();
            bool ok = await _import.Load(path);
            if (!ok)
            {
                status?.Invoke("MODEL LOAD FAILED (fallback car). Check StreamingAssets/Cars.");
                Debug.LogError("[Nitches] glTF load failed: " + path);
                return;
            }

            var holder = new GameObject("CarModel");
            holder.transform.SetParent(transform, false);
            ok = await _import.InstantiateMainSceneAsync(holder.transform);
            if (!ok)
            {
                status?.Invoke("MODEL INSTANTIATE FAILED (fallback car).");
                return;
            }

            // --- find contract wheels ---
            string[] names = { "Wheel_FL", "Wheel_FR", "Wheel_RL", "Wheel_RR" };
            Transform[] wheelNodes = new Transform[4];
            Transform[] spinNodes = new Transform[4];
            foreach (Transform t in holder.GetComponentsInChildren<Transform>(true))
            {
                for (int i = 0; i < 4; i++)
                {
                    if (t.name == names[i]) wheelNodes[i] = t;
                    if (t.name == names[i] + "_Spin") spinNodes[i] = t;
                }
            }
            for (int i = 0; i < 4; i++)
                if (spinNodes[i] == null) spinNodes[i] = wheelNodes[i];

            if (wheelNodes[0] == null || wheelNodes[2] == null)
            {
                status?.Invoke("MODEL OK but wheel nodes not found (visuals static).");
                if (fallbackToHide != null) fallbackToHide.SetActive(false);
                return;
            }

            // --- orient: front axle must be at +Z in vehicle space ---
            float frontZ = (transform.InverseTransformPoint(wheelNodes[0].position).z +
                            transform.InverseTransformPoint(wheelNodes[1].position).z) * 0.5f;
            float rearZ = (transform.InverseTransformPoint(wheelNodes[2].position).z +
                           transform.InverseTransformPoint(wheelNodes[3].position).z) * 0.5f;
            if (frontZ < rearZ)
                holder.transform.localRotation = Quaternion.Euler(0f, 180f, 0f);

            // --- build steer pivots at the physics mounts, adopt wheels ---
            Transform[] pivots = new Transform[4];
            for (int i = 0; i < 4; i++)
            {
                var pivot = new GameObject("SteerPivot_" + names[i]);
                pivot.transform.SetParent(transform, false);
                Vector3 mount = vehicle.MountLocal(i);
                pivot.transform.localPosition = new Vector3(mount.x, mount.y - vehicle.SpringRestLength, mount.z);
                pivots[i] = pivot.transform;

                // Reparent the wheel subtree to the pivot, keeping world pose;
                // the small residual offset vs the physics mount is < 1 cm
                // because the GLB hubs were authored at the spec positions.
                Transform adopt = spinNodes[i] != wheelNodes[i] ? spinNodes[i] : wheelNodes[i];
                adopt.SetParent(pivot.transform, true);
                spinNodes[i] = adopt;
            }

            visuals.Bind(vehicle, pivots, spinNodes);
            if (fallbackToHide != null) fallbackToHide.SetActive(false);
            status?.Invoke("");
            Debug.Log("[Nitches] Car model loaded: " + glbFileName);
        }
        catch (Exception e)
        {
            status?.Invoke("MODEL ERROR (fallback car): " + e.Message);
            Debug.LogError("[Nitches] CarModelLoader: " + e);
        }
    }
}
