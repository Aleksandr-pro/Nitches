using UnityEngine;
using UnityEngine.EventSystems;
using UnityEngine.UI;

/// <summary>
/// Code-built prototype HUD: speed/rpm/gear readout plus big touch
/// hold-buttons (steer left/right, gas, brake, drift, N2O).
/// Latin labels on purpose: the built-in font has no Cyrillic;
/// a bundled font arrives with the real menu (see MIGRATION_PLAN.md).
/// </summary>
public class Hud : MonoBehaviour
{
    private Text _speedText;
    private Text _statusText;
    private VehicleController _vehicle;
    private Font _font;

    private Font BuiltinFont()
    {
        if (_font != null) return _font;
        _font = Resources.GetBuiltinResource<Font>("LegacyRuntime.ttf");
        if (_font == null) _font = Resources.GetBuiltinResource<Font>("Arial.ttf");
        return _font;
    }

    private Text MakeText(Transform parent, string text, int size, TextAnchor anchor, Vector2 pos, Vector2 dim, Color color)
    {
        var go = new GameObject("Text");
        go.transform.SetParent(parent, false);
        var t = go.AddComponent<Text>();
        t.font = BuiltinFont();
        t.text = text;
        t.fontSize = size;
        t.alignment = anchor;
        t.color = color;
        t.raycastTarget = false;
        var rt = t.rectTransform;
        rt.anchorMin = rt.anchorMax = new Vector2(pos.x, pos.y);
        rt.pivot = new Vector2(pos.x, pos.y);
        rt.sizeDelta = dim;
        rt.anchoredPosition = Vector2.zero;
        return t;
    }

    private void MakeHoldButton(Transform parent, string label, Vector2 anchor, Vector2 offset, Vector2 size,
                                System.Action<bool> setHeld)
    {
        var go = new GameObject("Btn_" + label);
        go.transform.SetParent(parent, false);
        var img = go.AddComponent<Image>();
        img.color = new Color(0.05f, 0.06f, 0.08f, 0.55f);
        var rt = go.GetComponent<RectTransform>();
        rt.anchorMin = rt.anchorMax = anchor;
        rt.pivot = anchor;
        rt.sizeDelta = size;
        rt.anchoredPosition = offset;

        var txt = MakeText(go.transform, label, 26, TextAnchor.MiddleCenter,
                           new Vector2(0.5f, 0.5f), size, Color.white);
        txt.rectTransform.anchorMin = Vector2.zero;
        txt.rectTransform.anchorMax = Vector2.one;
        txt.rectTransform.offsetMin = Vector2.zero;
        txt.rectTransform.offsetMax = Vector2.zero;

        var trigger = go.AddComponent<EventTrigger>();
        var down = new EventTrigger.Entry { eventID = EventTriggerType.PointerDown };
        down.callback.AddListener(_ => { setHeld(true); img.color = new Color(1f, 0.58f, 0.08f, 0.75f); });
        trigger.triggers.Add(down);
        var up = new EventTrigger.Entry { eventID = EventTriggerType.PointerUp };
        up.callback.AddListener(_ => { setHeld(false); img.color = new Color(0.05f, 0.06f, 0.08f, 0.55f); });
        trigger.triggers.Add(up);
        var exit = new EventTrigger.Entry { eventID = EventTriggerType.PointerExit };
        exit.callback.AddListener(_ => { setHeld(false); img.color = new Color(0.05f, 0.06f, 0.08f, 0.55f); });
        trigger.triggers.Add(exit);
    }

    public void Build(DriverInput input, VehicleController vehicle)
    {
        _vehicle = vehicle;

        var canvasGo = new GameObject("HudCanvas");
        canvasGo.transform.SetParent(transform, false);
        var canvas = canvasGo.AddComponent<Canvas>();
        canvas.renderMode = RenderMode.ScreenSpaceOverlay;
        var scaler = canvasGo.AddComponent<CanvasScaler>();
        scaler.uiScaleMode = CanvasScaler.ScaleMode.ScaleWithScreenSize;
        scaler.referenceResolution = new Vector2(1280f, 720f);
        scaler.matchWidthOrHeight = 0.5f;
        canvasGo.AddComponent<GraphicRaycaster>();
        Transform root = canvasGo.transform;

        _speedText = MakeText(root, "0 KM/H", 44, TextAnchor.LowerRight,
                              new Vector2(1f, 0f), new Vector2(460f, 120f), Color.white);
        _speedText.rectTransform.anchoredPosition = new Vector2(-24f, 150f);

        _statusText = MakeText(root, "", 20, TextAnchor.UpperLeft,
                               new Vector2(0f, 1f), new Vector2(900f, 40f), new Color(1f, 0.8f, 0.5f));
        _statusText.rectTransform.anchoredPosition = new Vector2(18f, -14f);

        var help = MakeText(root, "WASD / ARROWS - drive   SPACE - drift   SHIFT - N2O", 18,
                            TextAnchor.UpperLeft, new Vector2(0f, 1f), new Vector2(900f, 34f),
                            new Color(1f, 1f, 1f, 0.75f));
        help.rectTransform.anchoredPosition = new Vector2(18f, -52f);

        // Touch controls: steering bottom-left, pedals bottom-right.
        MakeHoldButton(root, "<", new Vector2(0f, 0f), new Vector2(28f, 36f), new Vector2(120f, 120f),
                       v => input.TouchLeft = v);
        MakeHoldButton(root, ">", new Vector2(0f, 0f), new Vector2(164f, 36f), new Vector2(120f, 120f),
                       v => input.TouchRight = v);
        MakeHoldButton(root, "DRIFT", new Vector2(0f, 0f), new Vector2(96f, 172f), new Vector2(120f, 84f),
                       v => input.TouchHandbrake = v);

        MakeHoldButton(root, "N2O", new Vector2(1f, 0f), new Vector2(-452f, 172f), new Vector2(104f, 104f),
                       v => input.TouchNitro = v);
        MakeHoldButton(root, "BRAKE", new Vector2(1f, 0f), new Vector2(-332f, 36f), new Vector2(140f, 150f),
                       v => input.TouchBrake = v);
        MakeHoldButton(root, "GAS", new Vector2(1f, 0f), new Vector2(-176f, 36f), new Vector2(140f, 180f),
                       v => input.TouchGas = v);
    }

    public void SetStatus(string text)
    {
        if (_statusText != null) _statusText.text = text;
    }

    private void Update()
    {
        if (_vehicle == null || _speedText == null) return;
        string gear = _vehicle.Gear < 0 ? "R" : (_vehicle.Gear + 1).ToString();
        _speedText.text = $"{Mathf.Abs(Mathf.RoundToInt(_vehicle.SpeedKmh))} KM/H\n{gear}  {Mathf.RoundToInt(_vehicle.Rpm)} RPM";
    }
}
