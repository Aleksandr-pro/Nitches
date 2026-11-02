using System.Collections;
using UnityEngine;
using UnityEngine.Networking;

/// <summary>
/// Recorded-bank engine audio, same recipe as the Godot build:
/// rpm anchors (on-throttle / off-throttle loops) crossfaded in
/// pairs, pitch tied to rpm. No synthesized tone. Clips stream from
/// StreamingAssets/Audio/bugatti_chiron (see scripts/sync-unity-assets.mjs).
/// </summary>
public class EngineAudio : MonoBehaviour
{
    public VehicleController Vehicle;

    private static readonly int[] AnchorRpms = { 900, 1602, 2000, 3735, 5000, 6478, 7000 };

    private AudioSource _onA, _onB, _offA, _offB, _idle;
    private readonly AudioClip[] _onClips = new AudioClip[AnchorRpms.Length];
    private readonly AudioClip[] _offClips = new AudioClip[AnchorRpms.Length];
    private bool _loaded;

    private AudioSource MakeLoopSource(string name)
    {
        var go = new GameObject(name);
        go.transform.SetParent(transform, false);
        var src = go.AddComponent<AudioSource>();
        src.loop = true;
        src.playOnAwake = false;
        src.spatialBlend = 0f;
        src.volume = 0f;
        return src;
    }

    private void Start()
    {
        _onA = MakeLoopSource("EngineOnA");
        _onB = MakeLoopSource("EngineOnB");
        _offA = MakeLoopSource("EngineOffA");
        _offB = MakeLoopSource("EngineOffB");
        _idle = MakeLoopSource("EngineIdle");
        StartCoroutine(LoadBank());
    }

    private string BankUri(string file)
    {
        string basePath = System.IO.Path.Combine(Application.streamingAssetsPath, "Audio", "bugatti_chiron", file);
#if UNITY_ANDROID && !UNITY_EDITOR
        return basePath; // jar path works with UnityWebRequest as-is
#else
        return "file://" + basePath.Replace("\\", "/");
#endif
    }

    private IEnumerator LoadClip(string file, System.Action<AudioClip> done)
    {
        using (UnityWebRequest req = UnityWebRequestMultimedia.GetAudioClip(BankUri(file), AudioType.WAV))
        {
            yield return req.SendWebRequest();
            if (req.result == UnityWebRequest.Result.Success)
                done(DownloadHandlerAudioClip.GetContent(req));
            else
                Debug.LogWarning("[Nitches] Engine clip failed: " + file + " (" + req.error + ")");
        }
    }

    private IEnumerator LoadBank()
    {
        for (int i = 0; i < AnchorRpms.Length; i++)
        {
            int idx = i;
            yield return LoadClip($"engine_on_{AnchorRpms[idx]:D4}.wav", c => _onClips[idx] = c);
            yield return LoadClip($"engine_off_{AnchorRpms[idx]:D4}.wav", c => _offClips[idx] = c);
        }
        yield return LoadClip("engine_idle.wav", c => _idle.clip = c);

        foreach (var src in new[] { _onA, _onB, _offA, _offB, _idle })
            if (src != null && src.clip != null) src.Play();
        _loaded = true;
        Debug.Log("[Nitches] Engine bank loaded: bugatti_chiron");
    }

    private void SetPair(AudioSource a, AudioSource b, AudioClip[] clips, int lo, int hi, float blend, float rpm, float gain)
    {
        if (clips[lo] != null && a.clip != clips[lo]) { a.clip = clips[lo]; if (!a.isPlaying) a.Play(); }
        if (clips[hi] != null && b.clip != clips[hi]) { b.clip = clips[hi]; if (!b.isPlaying) b.Play(); }
        a.pitch = Mathf.Clamp(rpm / AnchorRpms[lo], 0.8f, 1.25f);
        b.pitch = Mathf.Clamp(rpm / AnchorRpms[hi], 0.8f, 1.25f);
        a.volume = gain * Mathf.Sqrt(1f - blend);
        b.volume = gain * Mathf.Sqrt(blend);
    }

    private void Update()
    {
        if (!_loaded || Vehicle == null) return;
        float rpm = Mathf.Max(Vehicle.Rpm, AnchorRpms[0]);
        float throttle = Vehicle.ThrottleNow;

        int hi = 1;
        while (hi < AnchorRpms.Length - 1 && AnchorRpms[hi] < rpm) hi++;
        int lo = hi - 1;
        float blend = Mathf.Clamp01((rpm - AnchorRpms[lo]) / Mathf.Max(1f, AnchorRpms[hi] - AnchorRpms[lo]));

        float onGain = 0.85f * Mathf.Clamp01(throttle * 1.6f);
        float offGain = 0.55f * (1f - Mathf.Clamp01(throttle * 1.6f));
        SetPair(_onA, _onB, _onClips, lo, hi, blend, rpm, onGain);
        SetPair(_offA, _offB, _offClips, lo, hi, blend, rpm, offGain);

        if (_idle.clip != null)
        {
            float idleBlend = 1f - Mathf.Clamp01((rpm - 900f) / 500f);
            _idle.volume = 0.7f * idleBlend;
            _idle.pitch = Mathf.Clamp(rpm / 950f, 0.9f, 1.15f);
            if (!_idle.isPlaying) _idle.Play();
        }
    }
}
