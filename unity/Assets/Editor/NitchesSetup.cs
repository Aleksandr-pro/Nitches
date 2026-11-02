using System.IO;
using UnityEditor;
using UnityEditor.Build;
using UnityEditor.SceneManagement;
using UnityEngine;
using UnityEngine.SceneManagement;

/// <summary>
/// One-click project setup + dev Android build for the Unity port.
/// Runtime content is code-built (GameBootstrap), so the scene this
/// creates is intentionally empty - it exists for Build Settings.
/// </summary>
public static class NitchesSetup
{
    private const string ScenePath = "Assets/Scenes/Main.unity";
    private const string BundleId = "io.nitches.horizon";

    [MenuItem("Nitches/1. Setup project (scene, player, input)")]
    public static void SetupProject()
    {
        // --- scene + build settings ---
        Directory.CreateDirectory("Assets/Scenes");
        if (!File.Exists(ScenePath))
        {
            Scene scene = EditorSceneManager.NewScene(NewSceneSetup.EmptyScene, NewSceneMode.Single);
            EditorSceneManager.SaveScene(scene, ScenePath);
        }
        EditorBuildSettings.scenes = new[] { new EditorBuildSettingsScene(ScenePath, true) };

        // --- player settings ---
        PlayerSettings.companyName = "Nitches";
        PlayerSettings.productName = "Nitches Horizon";
        PlayerSettings.bundleVersion = "0.1.0";
        PlayerSettings.SetApplicationIdentifier(NamedBuildTarget.Android, BundleId);
        PlayerSettings.Android.bundleVersionCode = 1;
        PlayerSettings.Android.minSdkVersion = AndroidSdkVersions.AndroidApiLevel26;
        PlayerSettings.defaultInterfaceOrientation = UIOrientation.LandscapeLeft;
        PlayerSettings.allowedAutorotateToLandscapeLeft = true;
        PlayerSettings.allowedAutorotateToLandscapeRight = true;
        PlayerSettings.allowedAutorotateToPortrait = false;
        PlayerSettings.allowedAutorotateToPortraitUpsideDown = false;

        // --- active input handling = Both (classic Input + Input System) ---
        bool inputChanged = false;
        var playerAssets = AssetDatabase.LoadAllAssetsAtPath("ProjectSettings/ProjectSettings.asset");
        if (playerAssets != null && playerAssets.Length > 0)
        {
            var so = new SerializedObject(playerAssets[0]);
            var prop = so.FindProperty("activeInputHandler");
            if (prop != null && prop.intValue != 2)
            {
                prop.intValue = 2;
                so.ApplyModifiedProperties();
                inputChanged = true;
            }
        }

        // --- physics timestep 100 Hz for the raycast suspension ---
        var timeAssets = AssetDatabase.LoadAllAssetsAtPath("ProjectSettings/TimeManager.asset");
        if (timeAssets != null && timeAssets.Length > 0)
        {
            var so = new SerializedObject(timeAssets[0]);
            var prop = so.FindProperty("Fixed Timestep");
            if (prop != null)
            {
                prop.floatValue = 0.01f;
                so.ApplyModifiedProperties();
            }
        }

        // --- keep the runtime-created materials' shader in builds ---
        var graphicsAssets = AssetDatabase.LoadAllAssetsAtPath("ProjectSettings/GraphicsSettings.asset");
        if (graphicsAssets != null && graphicsAssets.Length > 0)
        {
            var so = new SerializedObject(graphicsAssets[0]);
            var shaders = so.FindProperty("m_AlwaysIncludedShaders");
            Shader standard = Shader.Find("Standard");
            if (shaders != null && standard != null)
            {
                bool present = false;
                for (int i = 0; i < shaders.arraySize; i++)
                    if (shaders.GetArrayElementAtIndex(i).objectReferenceValue == standard) present = true;
                if (!present)
                {
                    int idx = shaders.arraySize;
                    shaders.InsertArrayElementAtIndex(idx);
                    shaders.GetArrayElementAtIndex(idx).objectReferenceValue = standard;
                    so.ApplyModifiedProperties();
                }
            }
        }

        AssetDatabase.SaveAssets();
        string note = inputChanged
            ? "\n\nIMPORTANT: input handling changed to 'Both'. Please RESTART the editor, then press Play."
            : "\n\nPress Play - the prototype builds itself from code.";
        EditorUtility.DisplayDialog("Nitches setup complete",
            "Scene: " + ScenePath + "\nBundle ID: " + BundleId + "\nOrientation: landscape\nPhysics: 100 Hz" + note, "OK");
        Debug.Log("[Nitches] Setup complete." + note);
    }

    [MenuItem("Nitches/2. Build Android APK (development)")]
    public static void BuildAndroid()
    {
        if (!File.Exists(ScenePath))
        {
            EditorUtility.DisplayDialog("Nitches", "Run '1. Setup project' first (it creates the scene).", "OK");
            return;
        }
        string outDir = Path.GetFullPath(Path.Combine(Application.dataPath, "../Builds/Android"));
        Directory.CreateDirectory(outDir);
        string apk = Path.Combine(outDir, "NitchesHorizon-unity.apk");

        var options = new BuildPlayerOptions
        {
            scenes = new[] { ScenePath },
            locationPathName = apk,
            target = BuildTarget.Android,
            options = BuildOptions.Development
        };
        var report = BuildPipeline.BuildPlayer(options);
        if (report.summary.result == UnityEditor.Build.Reporting.BuildResult.Succeeded)
        {
            Debug.Log("[Nitches] APK built: " + apk);
            EditorUtility.RevealInFinder(apk);
        }
        else
        {
            EditorUtility.DisplayDialog("Nitches build failed",
                "Result: " + report.summary.result + "\nSee Console for errors. " +
                "Make sure the Android Build Support module (SDK/NDK/OpenJDK) is installed in Unity Hub.", "OK");
        }
    }
}
