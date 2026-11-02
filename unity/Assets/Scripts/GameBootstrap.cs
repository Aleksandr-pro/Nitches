using UnityEngine;
using UnityEngine.EventSystems;

/// <summary>
/// Code-first bootstrap for the Unity port prototype: builds light,
/// camera, test track, the (fallback-then-GLB) car, HUD and engine
/// audio at runtime, so ANY empty scene becomes the game on Play.
/// The editor setup menu still creates a proper named scene for
/// builds; it stays empty and this bootstrap fills it.
/// </summary>
public class GameBootstrap : MonoBehaviour
{
    public const string PrototypeCarGlb = "bugatti_chiron_super_sport.glb";
    private const int CarLayer = 9;

    [RuntimeInitializeOnLoadMethod(RuntimeInitializeLoadType.AfterSceneLoad)]
    private static void Boot()
    {
        if (GameObject.Find("NitchesBootstrap") != null) return;
        var go = new GameObject("NitchesBootstrap");
        go.AddComponent<GameBootstrap>();
    }

    private Material Mat(Color color, float gloss = 0.25f)
    {
        var m = new Material(TestTrack.LitShader()) { color = color };
        if (m.HasProperty("_Glossiness")) m.SetFloat("_Glossiness", gloss);
        return m;
    }

    private void Awake()
    {
        Time.fixedDeltaTime = 0.01f; // 100 Hz physics for the raycast suspension
        Application.targetFrameRate = 60;

        // --- light & sky ---
        var sunGo = new GameObject("Sun");
        var sun = sunGo.AddComponent<Light>();
        sun.type = LightType.Directional;
        sun.intensity = 2.4f;
        sun.shadows = LightShadows.Soft;
        sunGo.transform.rotation = Quaternion.Euler(52f, -32f, 0f);
        RenderSettings.ambientMode = UnityEngine.Rendering.AmbientMode.Flat;
        RenderSettings.ambientLight = new Color(0.38f, 0.44f, 0.52f);
        RenderSettings.fog = true;
        RenderSettings.fogColor = new Color(0.62f, 0.72f, 0.82f);
        RenderSettings.fogStartDistance = 350f;
        RenderSettings.fogEndDistance = 1600f;

        // --- input ---
        var inputGo = new GameObject("DriverInput");
        var input = inputGo.AddComponent<DriverInput>();

        // --- world ---
        var trackGo = new GameObject("TestTrack");
        TestTrack.Build(trackGo.transform);

        // --- car root (physics) ---
        var carGo = new GameObject("PlayerCar");
        carGo.layer = CarLayer;
        carGo.transform.position = new Vector3(0f, 0.05f, -30f);
        var vehicle = carGo.AddComponent<VehicleController>(); // Rigidbody auto-added
        vehicle.GroundLayer = TestTrack.GroundLayer;

        var bodyCol = carGo.AddComponent<BoxCollider>();
        bodyCol.center = new Vector3(0f, 0.58f, 0f);
        bodyCol.size = new Vector3(1.86f, 0.62f, 4.62f);
        var cabinCol = carGo.AddComponent<BoxCollider>();
        cabinCol.center = new Vector3(0f, 0.95f, -0.25f);
        cabinCol.size = new Vector3(1.58f, 0.5f, 2.1f);

        // --- fallback visuals (hidden when the GLB arrives) ---
        var fallback = new GameObject("FallbackBody");
        fallback.transform.SetParent(carGo.transform, false);
        var bodyMesh = GameObject.CreatePrimitive(PrimitiveType.Cube);
        bodyMesh.transform.SetParent(fallback.transform, false);
        bodyMesh.transform.localPosition = new Vector3(0f, 0.55f, 0f);
        bodyMesh.transform.localScale = new Vector3(1.86f, 0.5f, 4.6f);
        bodyMesh.GetComponent<MeshRenderer>().sharedMaterial = Mat(new Color(0.55f, 0.06f, 0.05f), 0.6f);
        Destroy(bodyMesh.GetComponent<BoxCollider>());
        var cabinMesh = GameObject.CreatePrimitive(PrimitiveType.Cube);
        cabinMesh.transform.SetParent(fallback.transform, false);
        cabinMesh.transform.localPosition = new Vector3(0f, 0.95f, -0.25f);
        cabinMesh.transform.localScale = new Vector3(1.58f, 0.45f, 2.1f);
        cabinMesh.GetComponent<MeshRenderer>().sharedMaterial = Mat(new Color(0.08f, 0.09f, 0.11f), 0.7f);
        Destroy(cabinMesh.GetComponent<BoxCollider>());

        // Fallback wheels wired through the same visuals system.
        var visuals = carGo.AddComponent<WheelVisuals>();
        Transform[] pivots = new Transform[4];
        Transform[] spins = new Transform[4];
        var tyreMat = Mat(new Color(0.05f, 0.05f, 0.05f), 0.1f);
        for (int i = 0; i < 4; i++)
        {
            var pivot = new GameObject("FallbackPivot" + i);
            pivot.transform.SetParent(carGo.transform, false);
            var spin = new GameObject("FallbackSpin" + i);
            spin.transform.SetParent(pivot.transform, false);
            var wheel = GameObject.CreatePrimitive(PrimitiveType.Cylinder);
            wheel.transform.SetParent(spin.transform, false);
            wheel.transform.localRotation = Quaternion.Euler(0f, 0f, 90f);
            wheel.transform.localScale = new Vector3(vehicle.WheelRadius * 2f, 0.16f, vehicle.WheelRadius * 2f);
            wheel.GetComponent<MeshRenderer>().sharedMaterial = tyreMat;
            Destroy(wheel.GetComponent<Collider>());
            pivots[i] = pivot.transform;
            spins[i] = spin.transform;
        }
        visuals.Bind(vehicle, pivots, spins);

        // --- camera ---
        var camGo = new GameObject("MainCamera");
        camGo.tag = "MainCamera";
        var cam = camGo.AddComponent<Camera>();
        cam.clearFlags = CameraClearFlags.SolidColor;
        cam.backgroundColor = new Color(0.53f, 0.68f, 0.84f);
        cam.farClipPlane = 2500f;
        cam.fieldOfView = 62f;
        camGo.AddComponent<AudioListener>();
        camGo.transform.position = new Vector3(0f, 2.4f, -38f);
        var chase = camGo.AddComponent<ChaseCamera>();
        chase.Target = carGo.transform;
        chase.Vehicle = vehicle;

        // --- HUD + UI event system ---
        var esGo = new GameObject("EventSystem");
        esGo.AddComponent<EventSystem>();
        esGo.AddComponent<StandaloneInputModule>();

        var hudGo = new GameObject("Hud");
        var hud = hudGo.AddComponent<Hud>();
        hud.Build(input, vehicle);

        // --- engine audio (recorded bank) ---
        var audioGo = new GameObject("EngineAudio");
        audioGo.transform.SetParent(carGo.transform, false);
        var engineAudio = audioGo.AddComponent<EngineAudio>();
        engineAudio.Vehicle = vehicle;

        // --- real model (async; fallback hides on success) ---
        hud.SetStatus("UNITY PROTOTYPE 0.1.0 - " + PrototypeCarGlb);
        var loader = carGo.AddComponent<CarModelLoader>();
        loader.Load(PrototypeCarGlb, vehicle, visuals, fallback, hud.SetStatus);
        Debug.Log("[Nitches] Bootstrap complete. Drive with WASD/arrows or touch buttons.");
    }
}
