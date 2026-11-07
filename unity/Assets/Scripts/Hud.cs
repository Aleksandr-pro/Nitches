using UnityEngine;
using UnityEngine.EventSystems;
using UnityEngine.UI;

/// <summary>
/// Prototype HUD built from code, styled per the v0.1 UI contract:
/// safe area ≥3% width / 4% height, buttons 40–55 % opacity and ≥56 dp,
/// icons instead of words (except N₂O), tall gas/brake with depth,
/// round N₂O / drift / ignition, round minimap and instrument cluster,
/// big steering wheel on the left.
///
/// Cyrillic/real sprite icons arrive with the bundled menu font in
/// stage 3; this prototype uses symbol glyphs + a generated font so it
/// works from a blank scene with zero assets.
/// </summary>
public class Hud : MonoBehaviour
{
    // --- layout constants at reference resolution 1280×720 ---
    private const float RefWidth = 1280f;
    private const float RefHeight = 720f;
    private const float SafeWidthPct = 0.03f;   // ≥3 % of width
    private const float SafeHeightPct = 0.04f;  // ≥4 % of height

    private const float WheelSize = 210f;       // big steering wheel diameter
    private const float ClusterSize = 190f;     // instrument cluster diameter
    private const float MinimapSize = 150f;     // minimap diameter
    private const float IgnitionSize = 96f;     // round ignition button diameter
    private const float PedalWidth = 118f;      // tall gas/brake width  (≥56 dp)
    private const float PedalHeight = 210f;     // tall gas/brake height
    private const float RoundBtnSize = 100f;    // nitro/drift diameter   (≥56 dp)

    private static readonly Color Dim = new Color(0.06f, 0.07f, 0.09f, 0.50f); // 40–55 % opacity
    private static readonly Color Pressed = new Color(1f, 0.6f, 0.1f, 0.75f);
    private static readonly Color TextWhite = Color.white;
    private static readonly Color Accent = new Color(1f, 0.82f, 0.35f);

    // --- generated round textures ---
    private Texture2D _texCircle, _texRing, _texNeedle, _texDot;

    // --- canvas ---
    private Canvas _canvas;
    private RectTransform _safePanel; // inset by safe area on all sides
    private float _safeX, _safeY;

    // --- instrument cluster (top right) ---
    private RawImage _clusterRingImg;
    private RectTransform _clusterNeedle;
    private Text _clusterSpeed, _clusterGear, _clusterRpm;

    // --- minimap + ignition (top left) ---
    private RawImage _mapRingImg, _mapDotImg, _mapHeadingImg;
    private Image _ignitionImg;
    private Text _ignitionLabel;

    // --- big steering wheel (bottom left) ---
    private RectTransform _wheelOuter, _wheelInner;

    // --- pedals / buttons (bottom right) ---
    private Image _btnGas, _btnBrake, _btnNitro, _btnDrift;
    private Image _btnSteerL, _btnSteerR;

    private VehicleController _vehicle;
    private DriverInput _input;

    public void Build(DriverInput input, VehicleController vehicle)
    {
        _input = input;
        _vehicle = vehicle;

        // --- canvas ---
        var go = new GameObject("HudCanvas");
        go.transform.SetParent(transform, false);
        _canvas = go.AddComponent<Canvas>();
        _canvas.renderMode = RenderMode.ScreenSpaceOverlay;
        go.AddComponent<CanvasScaler>();
        go.AddComponent<GraphicRaycaster>();

        // --- safe-area panel: everything stays ≥3%W / ≥4%H from edges ---
        var panelGo = new GameObject("SafePanel");
        panelGo.transform.SetParent(go.transform, false);
        _safePanel = panelGo.AddComponent<RectTransform>();
        _safePanel.anchorMin = Vector2.zero;
        _safePanel.anchorMax = Vector2.one;
        _safePanel.offsetMin = Vector2.zero;
        _safePanel.offsetMax = Vector2.zero;
        _safeX = Screen.width * SafeWidthPct;
        _safeY = Screen.height * SafeHeightPct;

        // generated textures (circles / rings / needle / dot)
        _texCircle = MakeCircle(256, Color.white);
        _texRing = MakeRing(256, Color.white, 0.10f);
        _texNeedle = MakeNeedle(140, 10, Accent);
        _texDot = MakeCircle(64, Color.white);

        BuildCluster();
        BuildMinimapAndIgnition();
        BuildSteeringWheel();
        BuildPedals();

        Layout();
    }

    // ================= graphics helpers =================

    private Texture2D MakeCircle(int size, Color color)
    {
        var tex = new Texture2D(size, size, TextureFormat.RGBA32, false);
        var px = new Color[size * size];
        float r = size * 0.5f, c = size * 0.5f;
        for (int y = 0; y < size; y++)
            for (int x = 0; x < size; x++)
            {
                float dx = x - c, dy = y - c;
                px[y * size + x] = (dx * dx + dy * dy <= r * r) ? color : new Color(0, 0, 0, 0);
            }
        tex.SetPixels(px);
        tex.Apply();
        return tex;
    }

    private Texture2D MakeRing(int size, Color color, float thickness)
    {
        var tex = new Texture2D(size, size, TextureFormat.RGBA32, false);
        var px = new Color[size * size];
        float rOut = size * 0.5f, rIn = rOut * (1f - thickness), c = size * 0.5f;
        for (int y = 0; y < size; y++)
            for (int x = 0; x < size; x++)
            {
                float d = Mathf.Sqrt((x - c) * (x - c) + (y - c) * (y - c));
                px[y * size + x] = (d >= rIn && d <= rOut) ? color : new Color(0, 0, 0, 0);
            }
        tex.SetPixels(px);
        tex.Apply();
        return tex;
    }

    private Texture2D MakeNeedle(int length, int width, Color color)
    {
        var tex = new Texture2D(width, length, TextureFormat.RGBA32, false);
        var px = new Color[width * length];
        int hw = width / 2;
        for (int y = 0; y < length; y++)
            for (int x = 0; x < width; x++)
            {
                // taper toward the tip
                float t = 1f - (float)y / length;
                int halfW = Mathf.Max(1, Mathf.RoundToInt(hw * t));
                px[y * width + x] = (Mathf.Abs(x - hw) <= halfW) ? color : new Color(0, 0, 0, 0);
            }
        tex.SetPixels(px);
        tex.Apply();
        return tex;
    }

    // ================= sub-builders =================

    private void BuildCluster()
    {
        var go = new GameObject("InstrumentCluster");
        go.transform.SetParent(_safePanel, false);
        var rt = go.AddComponent<RectTransform>();
        rt.anchorMin = rt.anchorMax = new Vector2(1f, 1f); // top right
        rt.pivot = new Vector2(1f, 1f);
        rt.sizeDelta = new Vector2(ClusterSize, ClusterSize);
        rt.anchoredPosition = new Vector2(-_safeX - ClusterSize * 0.5f, -_safeY - ClusterSize * 0.5f);

        var ring = go.AddComponent<RawImage>();
        ring.texture = _texRing;
        ring.color = new Color(0.85f, 0.85f, 0.9f, 0.9f);
        ring.raycastTarget = false;
        var ringRt = ring.GetComponent<RectTransform>();
        ringRt.anchorMin = ringRt.anchorMax = Vector2.one * 0.5f;
        ringRt.sizeDelta = new Vector2(ClusterSize * 0.92f, ClusterSize * 0.92f);

        // needle
        var needleGo = new GameObject("Needle");
        needleGo.transform.SetParent(rt, false);
        _clusterNeedle = needleGo.AddComponent<RectTransform>();
        _clusterNeedle.anchorMin = _clusterNeedle.anchorMax = Vector2.one * 0.5f;
        _clusterNeedle.pivot = new Vector2(0.5f, 0.92f); // pivot near bottom
        _clusterNeedle.sizeDelta = new Vector2(10f, ClusterSize * 0.34f);
        var ni = needleGo.AddComponent<RawImage>();
        ni.texture = _texNeedle;
        ni.color = Accent;

        _clusterSpeed = MakeClusterText(rt, "0", 40, new Vector2(0.5f, 0.5f), Vector2.zero, new Vector2(ClusterSize * 0.8f, 50f));
        _clusterSpeed.rectTransform.anchoredPosition = new Vector2(0f, 6f);
        _clusterRpm = MakeClusterText(rt, "0 RPM", 16, new Vector2(0.5f, 0.5f), Vector2.zero, new Vector2(ClusterSize * 0.8f, 24f));
        _clusterRpm.rectTransform.anchoredPosition = new Vector2(0f, -30f);
        _clusterGear = MakeClusterText(rt, "N", 16, new Vector2(0.5f, 0.5f), Vector2.zero, new Vector2(ClusterSize * 0.8f, 24f));
        _clusterGear.rectTransform.anchoredPosition = new Vector2(0f, -54f);
    }

    private Text MakeClusterText(Transform parent, string text, int size, Vector2 anchor, Vector2 offset, Vector2 dim)
    {
        var go = new GameObject("Text");
        go.transform.SetParent(parent, false);
        var t = go.AddComponent<Text>();
        t.font = BuiltinFont();
        t.text = text;
        t.fontSize = size;
        t.alignment = TextAnchor.MiddleCenter;
        t.color = TextWhite;
        var rt = go.GetComponent<RectTransform>();
        rt.anchorMin = rt.anchorMax = anchor;
        rt.pivot = anchor;
        rt.sizeDelta = dim;
        rt.anchoredPosition = offset;
        return t;
    }

    private void BuildMinimapAndIgnition()
    {
        // minimap (top left)
        var mapGo = new GameObject("Minimap");
        mapGo.transform.SetParent(_safePanel, false);
        var mapRt = mapGo.AddComponent<RectTransform>();
        mapRt.anchorMin = mapRt.anchorMax = new Vector2(0f, 1f);
        mapRt.pivot = new Vector2(0f, 1f);
        mapRt.sizeDelta = new Vector2(MinimapSize, MinimapSize);
        mapRt.anchoredPosition = new Vector2(_safeX + MinimapSize * 0.5f, -_safeY - MinimapSize * 0.5f);

        var mapRing = mapGo.AddComponent<RawImage>();
        mapRing.texture = _texRing;
        mapRing.color = new Color(0.85f, 0.85f, 0.9f, 0.8f);
        var mapRingRt = mapRing.GetComponent<RectTransform>();
        mapRingRt.anchorMin = mapRingRt.anchorMax = Vector2.one * 0.5f;
        mapRingRt.sizeDelta = new Vector2(MinimapSize * 0.9f, MinimapSize * 0.9f);

        _mapDotImg = new GameObject("MapDot").AddComponent<RawImage>();
        _mapDotImg.transform.SetParent(mapRt, false);
        _mapDotImg.texture = _texDot;
        _mapDotImg.color = Accent;
        var dotRt = _mapDotImg.GetComponent<RectTransform>();
        dotRt.anchorMin = dotRt.anchorMax = Vector2.one * 0.5f;
        dotRt.sizeDelta = new Vector2(12f, 12f);
        dotRt.anchoredPosition = Vector2.zero;

        _mapHeadingImg = new GameObject("MapHeading").AddComponent<RawImage>();
        _mapHeadingImg.transform.SetParent(mapRt, false);
        _mapHeadingImg.texture = _texNeedle;
        _mapHeadingImg.color = new Color(1f, 0.35f, 0.35f);
        var headRt = _mapHeadingImg.GetComponent<RectTransform>();
        headRt.anchorMin = headRt.anchorMax = Vector2.one * 0.5f;
        headRt.pivot = new Vector2(0.5f, 0.9f);
        headRt.sizeDelta = new Vector2(6f, MinimapSize * 0.32f);

        // ignition button (round, under minimap)
        var ignGo = new GameObject("BtnIgnition");
        ignGo.transform.SetParent(_safePanel, false);
        var ignRt = ignGo.AddComponent<RectTransform>();
        ignRt.anchorMin = ignRt.anchorMax = new Vector2(0f, 1f);
        ignRt.pivot = new Vector2(0f, 1f);
        ignRt.sizeDelta = new Vector2(IgnitionSize, IgnitionSize);
        float ignY = -_safeY - MinimapSize - 24f - IgnitionSize * 0.5f;
        ignRt.anchoredPosition = new Vector2(_safeX + MinimapSize * 0.5f, ignY);

        _ignitionImg = ignGo.AddComponent<Image>();
        _ignitionImg.color = Dim;
        _ignitionImg.sprite = Sprite.Create(_texCircle, new Rect(0, 0, 256, 256), new Vector2(0.5f, 0.5f));
        _ignitionImg.type = Image.Type.Simple;
        _ignitionLabel = new GameObject("Label").AddComponent<Text>();
        _ignitionLabel.transform.SetParent(ignRt, false);
        _ignitionLabel.font = BuiltinFont();
        _ignitionLabel.text = "🔑";
        _ignitionLabel.fontSize = 30;
        _ignitionLabel.alignment = TextAnchor.MiddleCenter;
        _ignitionLabel.color = TextWhite;
        var labRt = _ignitionLabel.GetComponent<RectTransform>();
        labRt.anchorMin = labRt.anchorMax = Vector2.one * 0.5f;
        labRt.sizeDelta = new Vector2(IgnitionSize * 0.8f, IgnitionSize * 0.8f);

        var trigger = ignGo.AddComponent<EventTrigger>();
        var down = new EventTrigger.Entry { eventID = EventTriggerType.PointerDown };
        down.callback.AddListener(_ =>
        {
            _ignitionImg.color = Pressed;
            if (_vehicle != null) _vehicle.SetIgnition(!_vehicle.EngineOn);
            else if (_input != null) _input.ToggleIgnition();
        });
        trigger.triggers.Add(down);
        var up = new EventTrigger.Entry { eventID = EventTriggerType.PointerUp };
        up.callback.AddListener(_ => _ignitionImg.color = Dim);
        trigger.triggers.Add(up);
        var ex = new EventTrigger.Entry { eventID = EventTriggerType.PointerExit };
        ex.callback.AddListener(_ => _ignitionImg.color = Dim);
        trigger.triggers.Add(ex);
    }

    private void BuildSteeringWheel()
    {
        var wheelGo = new GameObject("SteeringWheel");
        wheelGo.transform.SetParent(_safePanel, false);
        var wheelRt = wheelGo.AddComponent<RectTransform>();
        wheelRt.anchorMin = wheelRt.anchorMax = new Vector2(0f, 0f);
        wheelRt.pivot = new Vector2(0f, 0f);
        wheelRt.sizeDelta = new Vector2(WheelSize, WheelSize);
        wheelRt.anchoredPosition = new Vector2(_safeX + WheelSize * 0.5f, _safeY + WheelSize * 0.5f);

        _wheelOuter = new GameObject("Outer").AddComponent<RectTransform>();
        _wheelOuter.transform.SetParent(wheelRt, false);
        _wheelOuter.anchorMin = _wheelOuter.anchorMax = Vector2.one * 0.5f;
        _wheelOuter.sizeDelta = new Vector2(WheelSize, WheelSize);
        var outerImg = _wheelOuter.gameObject.AddComponent<RawImage>();
        outerImg.texture = _texRing;
        outerImg.color = new Color(0.8f, 0.8f, 0.85f, 0.9f);

        _wheelInner = new GameObject("Inner").AddComponent<RectTransform>();
        _wheelInner.transform.SetParent(wheelRt, false);
        _wheelInner.anchorMin = _wheelInner.anchorMax = Vector2.one * 0.5f;
        _wheelInner.sizeDelta = new Vector2(WheelSize * 0.55f, WheelSize * 0.55f);
        var innerImg = _wheelInner.gameObject.AddComponent<RawImage>();
        innerImg.texture = _texCircle;
        innerImg.color = new Color(0.2f, 0.22f, 0.26f, 0.9f);
    }

    private void BuildPedals()
    {
        float baseY = _safeY + PedalHeight * 0.5f + 14f;

        // Gas: tall, bottom right
        _btnGas = MakePedal("BtnGas", "⛽", new Vector2(1f, 0f),
            new Vector2(-_safeX - PedalWidth * 0.5f, baseY),
            new Vector2(PedalWidth, PedalHeight), v => _input.TouchGas = v);
        // Brake: tall, left of gas
        _btnBrake = MakePedal("BtnBrake", "🛑", new Vector2(1f, 0f),
            new Vector2(-_safeX - PedalWidth * 0.5f - PedalWidth - 18f, baseY),
            new Vector2(PedalWidth, PedalHeight), v => _input.TouchBrake = v);
        // Nitro: round, above gas
        _btnNitro = MakeRoundBtn("BtnNitro", "N₂O", new Vector2(1f, 0f),
            new Vector2(-_safeX - PedalWidth * 0.5f, baseY + PedalHeight * 0.5f + 20f + RoundBtnSize * 0.5f),
            RoundBtnSize, v => _input.TouchNitro = v);
        // Drift: round, above brake
        _btnDrift = MakeRoundBtn("BtnDrift", "⏹", new Vector2(1f, 0f),
            new Vector2(-_safeX - PedalWidth * 0.5f - PedalWidth - 18f, baseY + PedalHeight * 0.5f + 20f + RoundBtnSize * 0.5f),
            RoundBtnSize, v => _input.TouchHandbrake = v);

        // Steer arrows: left / right of the steering wheel area, bottom left
        _btnSteerL = MakeRoundBtn("BtnSteerL", "◀", new Vector2(0f, 0f),
            new Vector2(_safeX + RoundBtnSize * 0.5f + 12f, _safeY + RoundBtnSize * 0.5f + 12f),
            RoundBtnSize, v => _input.TouchLeft = v);
        _btnSteerR = MakeRoundBtn("BtnSteerR", "▶", new Vector2(0f, 0f),
            new Vector2(_safeX + RoundBtnSize * 0.5f + 12f + RoundBtnSize + 14f, _safeY + RoundBtnSize * 0.5f + 12f),
            RoundBtnSize, v => _input.TouchRight = v);
    }

    private Image MakePedal(string name, string label, Vector2 anchor, Vector2 pos, Vector2 size, System.Action<bool> setHeld)
    {
        var go = new GameObject(name);
        go.transform.SetParent(_safePanel, false);
        var rt = go.AddComponent<RectTransform>();
        rt.anchorMin = rt.anchorMax = anchor;
        rt.pivot = anchor;
        rt.sizeDelta = size;
        rt.anchoredPosition = pos;

        var img = go.AddComponent<Image>();
        img.color = Dim;

        var txt = new GameObject("Label").AddComponent<Text>();
        txt.transform.SetParent(rt, false);
        txt.font = BuiltinFont();
        txt.text = label;
        txt.fontSize = 30;
        txt.alignment = TextAnchor.MiddleCenter;
        txt.color = TextWhite;
        var labRt = txt.GetComponent<RectTransform>();
        labRt.anchorMin = labRt.anchorMax = Vector2.one * 0.5f;
        labRt.sizeDelta = new Vector2(size.x * 0.7f, size.y * 0.35f);

        var trigger = go.AddComponent<EventTrigger>();
        var down = new EventTrigger.Entry { eventID = EventTriggerType.PointerDown };
        down.callback.AddListener(_ => { setHeld(true); img.color = Pressed; });
        trigger.triggers.Add(down);
        var up = new EventTrigger.Entry { eventID = EventTriggerType.PointerUp };
        up.callback.AddListener(_ => { setHeld(false); img.color = Dim; });
        trigger.triggers.Add(up);
        var ex = new EventTrigger.Entry { eventID = EventTriggerType.PointerExit };
        ex.callback.AddListener(_ => { setHeld(false); img.color = Dim; });
        trigger.triggers.Add(ex);
        return img;
    }

    private Image MakeRoundBtn(string name, string label, Vector2 anchor, Vector2 pos, float size, System.Action<bool> setHeld)
    {
        var go = new GameObject(name);
        go.transform.SetParent(_safePanel, false);
        var rt = go.AddComponent<RectTransform>();
        rt.anchorMin = rt.anchorMax = anchor;
        rt.pivot = anchor;
        rt.sizeDelta = new Vector2(size, size);
        rt.anchoredPosition = pos;

        var img = go.AddComponent<Image>();
        img.color = Dim;
        img.sprite = Sprite.Create(_texCircle, new Rect(0, 0, 256, 256), new Vector2(0.5f, 0.5f));

        var txt = new GameObject("Label").AddComponent<Text>();
        txt.transform.SetParent(rt, false);
        txt.font = BuiltinFont();
        txt.text = label;
        txt.fontSize = 24;
        txt.alignment = TextAnchor.MiddleCenter;
        txt.color = TextWhite;
        var labRt = txt.GetComponent<RectTransform>();
        labRt.anchorMin = labRt.anchorMax = Vector2.one * 0.5f;
        labRt.sizeDelta = new Vector2(size * 0.75f, size * 0.75f);

        var trigger = go.AddComponent<EventTrigger>();
        var down = new EventTrigger.Entry { eventID = EventTriggerType.PointerDown };
        down.callback.AddListener(_ => { setHeld(true); img.color = Pressed; });
        trigger.triggers.Add(down);
        var up = new EventTrigger.Entry { eventID = EventTriggerType.PointerUp };
        up.callback.AddListener(_ => { setHeld(false); img.color = Dim; });
        trigger.triggers.Add(up);
        var ex = new EventTrigger.Entry { eventID = EventTriggerType.PointerExit };
        ex.callback.AddListener(_ => { setHeld(false); img.color = Dim; });
        trigger.triggers.Add(ex);
        return img;
    }

    // ================= layout + update =================

    private void Layout()
    {
        _safeX = Screen.width * SafeWidthPct;
        _safeY = Screen.height * SafeHeightPct;
        if (_safePanel == null) return;
        _safePanel.offsetMin = new Vector2(_safeX, _safeY);
        _safePanel.offsetMax = new Vector2(-_safeX, -_safeY);
    }

    private void Update()
    {
        // re-layout on resize/orientation change
        if (_safePanel != null &&
            (Mathf.Abs(_safePanel.offsetMin.x - Screen.width * SafeWidthPct) > 1f ||
             Mathf.Abs(_safePanel.offsetMin.y - Screen.height * SafeHeightPct) > 1f))
            Layout();

        if (_vehicle == null) return;

        // --- instrument cluster ---
        if (_clusterSpeed != null)
        {
            int speed = Mathf.Abs(Mathf.RoundToInt(_vehicle.SpeedKmh));
            string gear = _vehicle.Gear < 0 ? "R" : (_vehicle.Gear == 0 ? "N" : (_vehicle.Gear + 1).ToString());
            _clusterSpeed.text = speed.ToString();
            _clusterGear.text = gear;
            _clusterRpm.text = _vehicle.EngineOn ? Mathf.RoundToInt(_vehicle.Rpm).ToString() + " RPM" : "OFF";
        }

        // needle: rpm 0..7100 maps to -120..+120 deg
        if (_clusterNeedle != null && _vehicle.EngineOn)
        {
            float t = Mathf.Clamp01(_vehicle.Rpm / 7100f);
            _clusterNeedle.localRotation = Quaternion.Euler(0f, 0f, -120f + 240f * t);
        }
        else if (_clusterNeedle != null)
        {
            _clusterNeedle.localRotation = Quaternion.Euler(0f, 0f, -120f);
        }

        // --- ignition button colour ---
        if (_ignitionImg != null)
            _ignitionImg.color = _vehicle.EngineOn ? new Color(0.2f, 0.7f, 0.25f, 0.85f) : Dim;

        // --- steering wheel rotation ---
        if (_wheelOuter != null && _input != null)
        {
            float deg = _input.Steer * 36f; // ±36° visual
            _wheelOuter.localRotation = Quaternion.Euler(0f, 0f, -deg);
            _wheelInner.localRotation = Quaternion.identity;
        }

        // --- minimap heading follows car yaw; dot stays centred ---
        if (_mapHeadingImg != null && _vehicle != null)
        {
            float yaw = _vehicle.transform.eulerAngles.y;
            _mapHeadingImg.transform.localRotation = Quaternion.Euler(0f, 0f, -yaw);
        }

        // --- button pressed feedback (from DriverInput state) ---
        SetBtnPressed(_btnGas, _input != null && _input.TouchGas);
        SetBtnPressed(_btnBrake, _input != null && _input.TouchBrake);
        SetBtnPressed(_btnNitro, _input != null && _input.TouchNitro);
        SetBtnPressed(_btnDrift, _input != null && _input.TouchHandbrake);
        SetBtnPressed(_btnSteerL, _input != null && _input.TouchLeft);
        SetBtnPressed(_btnSteerR, _input != null && _input.TouchRight);
    }

    private void SetBtnPressed(Image img, bool held)
    {
        if (img == null) return;
        img.color = held ? Pressed : Dim;
    }

    private Font BuiltinFont()
    {
        var f = Resources.GetBuiltinResource<Font>("LegacyRuntime.ttf");
        if (f == null) f = Resources.GetBuiltinResource<Font>("Arial.ttf");
        return f;
    }
}
