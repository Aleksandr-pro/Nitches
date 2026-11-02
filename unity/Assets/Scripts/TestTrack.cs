using UnityEngine;

/// <summary>
/// Minimal code-built test world for the first Unity prototype:
/// a long straight road (enough to feel all 7 gears), ground,
/// road markings and simple building blocks with colliders.
/// Replaced by real worlds later (see MIGRATION_PLAN.md).
/// </summary>
public static class TestTrack
{
    public const int GroundLayer = 8;
    public const int ObstacleLayer = 10;

    private static Material _asphalt, _grass, _lineWhite, _edge, _buildingA, _buildingB, _buildingC;

    /// <summary>Standard can be stripped from builds if unused elsewhere; fall back gracefully.</summary>
    public static Shader LitShader()
    {
        Shader s = Shader.Find("Standard");
        if (s == null) s = Shader.Find("Mobile/Diffuse");
        if (s == null) s = Shader.Find("Legacy Shaders/Diffuse");
        if (s == null) s = Shader.Find("Unlit/Color");
        return s;
    }

    private static Material Mat(string name, Color color, float roughness = 0.95f)
    {
        var m = new Material(LitShader()) { name = name, color = color };
        if (m.HasProperty("_Glossiness")) m.SetFloat("_Glossiness", 1f - roughness);
        return m;
    }

    private static GameObject Box(Transform parent, string name, Vector3 pos, Vector3 size, Material mat, int layer, bool collider = true)
    {
        var go = GameObject.CreatePrimitive(PrimitiveType.Cube);
        go.name = name;
        go.layer = layer;
        go.transform.SetParent(parent, false);
        go.transform.position = pos;
        go.transform.localScale = size;
        go.GetComponent<MeshRenderer>().sharedMaterial = mat;
        if (!collider) Object.Destroy(go.GetComponent<BoxCollider>());
        return go;
    }

    public static void Build(Transform parent)
    {
        _asphalt = Mat("Asphalt", new Color(0.13f, 0.13f, 0.15f));
        _grass = Mat("Grass", new Color(0.24f, 0.42f, 0.20f));
        _lineWhite = Mat("Line", new Color(0.92f, 0.92f, 0.92f), 0.7f);
        _edge = Mat("Edge", new Color(0.85f, 0.32f, 0.18f), 0.8f);
        _buildingA = Mat("BuildingA", new Color(0.55f, 0.58f, 0.64f), 0.6f);
        _buildingB = Mat("BuildingB", new Color(0.72f, 0.64f, 0.52f), 0.6f);
        _buildingC = Mat("BuildingC", new Color(0.42f, 0.48f, 0.58f), 0.6f);

        // Ground slab the suspension rays can hit everywhere.
        Box(parent, "Ground", new Vector3(0f, -0.5f, 400f), new Vector3(1200f, 1f, 2400f), _grass, GroundLayer);

        // Main straight: 12 m wide, z from -100 to 1400 (top-speed room).
        Box(parent, "Road", new Vector3(0f, 0.01f, 650f), new Vector3(12f, 0.04f, 1500f), _asphalt, GroundLayer);
        // Return straight, offset, so the player can loop around.
        Box(parent, "RoadReturn", new Vector3(30f, 0.01f, 650f), new Vector3(12f, 0.04f, 1500f), _asphalt, GroundLayer);
        // Connector pads at both ends.
        Box(parent, "PadSouth", new Vector3(15f, 0.01f, -100f), new Vector3(60f, 0.04f, 40f), _asphalt, GroundLayer);
        Box(parent, "PadNorth", new Vector3(15f, 0.01f, 1400f), new Vector3(60f, 0.04f, 40f), _asphalt, GroundLayer);

        // Centre dashes + edge lines (visual only, no colliders).
        for (float z = -90f; z < 1395f; z += 12f)
        {
            Box(parent, "Dash", new Vector3(0f, 0.045f, z), new Vector3(0.35f, 0.01f, 5f), _lineWhite, GroundLayer, false);
            Box(parent, "DashR", new Vector3(30f, 0.045f, z), new Vector3(0.35f, 0.01f, 5f), _lineWhite, GroundLayer, false);
        }
        Box(parent, "EdgeL", new Vector3(-6.2f, 0.03f, 650f), new Vector3(0.4f, 0.06f, 1500f), _edge, GroundLayer, false);
        Box(parent, "EdgeR", new Vector3(6.2f, 0.03f, 650f), new Vector3(0.4f, 0.06f, 1500f), _edge, GroundLayer, false);

        // Placeholder city blocks flanking the first 600 m.
        var rng = new System.Random(12345);
        Material[] palette = { _buildingA, _buildingB, _buildingC };
        for (int i = 0; i < 46; i++)
        {
            float side = i % 2 == 0 ? -1f : 1f;
            float x = side * (16f + (float)rng.NextDouble() * 22f) + (side > 0f ? 22f : 0f);
            float z = -60f + i * 28f + (float)rng.NextDouble() * 10f;
            float h = 8f + (float)rng.NextDouble() * 34f;
            float w = 10f + (float)rng.NextDouble() * 10f;
            float d = 10f + (float)rng.NextDouble() * 10f;
            Box(parent, "Block" + i, new Vector3(x, h * 0.5f, z), new Vector3(w, h, d), palette[i % 3], ObstacleLayer);
        }

        // A few slalom blocks ON the return straight to test steering/drift.
        for (int i = 0; i < 8; i++)
        {
            float x = 30f + (i % 2 == 0 ? -2.6f : 2.6f);
            Box(parent, "Slalom" + i, new Vector3(x, 0.5f, 200f + i * 45f), new Vector3(1.2f, 1f, 1.2f), _edge, ObstacleLayer);
        }
    }
}
