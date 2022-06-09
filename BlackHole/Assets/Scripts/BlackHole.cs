using System.Collections;
using System.Collections.Generic;
using UnityEngine;
using UnityEngine.Experimental.Rendering;

public class BlackHole : MonoBehaviour
{
    public BloomEffect bloom;
    public RenderTexture render, back, final;
    public Texture space;
    public RayTracingShader blackHoleShader;
    public RayTracingAccelerationStructure accelStruct;
    public LayerMask layerMask;
    Material tonemapping;

    void Start()
    {

        var settings = new RayTracingAccelerationStructure.RASSettings();
        settings.layerMask = layerMask;
        settings.managementMode = RayTracingAccelerationStructure.ManagementMode.Automatic;
        settings.rayTracingModeMask = RayTracingAccelerationStructure.RayTracingModeMask.Everything;

        accelStruct = new RayTracingAccelerationStructure(settings);
        accelStruct.Build();

        render = new RenderTexture(3840, 2160, 0, RenderTextureFormat.ARGBHalf);
        render.enableRandomWrite = true;
        render.Create();

        back = new RenderTexture(3840, 2160, 0, RenderTextureFormat.ARGBHalf);
        back.Create();

        final = new RenderTexture(1920, 1080, 0, RenderTextureFormat.ARGBHalf);
        final.Create();

        tonemapping = new Material(Shader.Find("Hidden/Tonemapping"));
    }

    private void LateUpdate()
    {
        accelStruct.Build();
        Matrix4x4 inverseVP = (GL.GetGPUProjectionMatrix(Camera.main.projectionMatrix, false)
            * Camera.main.worldToCameraMatrix).inverse;
        blackHoleShader.SetShaderPass("MainRayPass");
        blackHoleShader.SetMatrix("UNITY_MATRIX_I_VP", inverseVP);
        blackHoleShader.SetAccelerationStructure("accelerationStructure", accelStruct);
        blackHoleShader.SetTexture("Irradiance", render);
        blackHoleShader.SetTexture("Space", space);
        blackHoleShader.Dispatch("Main", render.width, render.height, 1, Camera.main);

        bloom.ProcessBloom(render, back);

        tonemapping.SetTexture("_Frame", back);
        Graphics.Blit(render, render, tonemapping);
        Graphics.Blit(render, final);
    }

    private void OnGUI()
    {
        GUI.DrawTexture(new Rect(0, 0, Screen.width, Screen.height), final);
    }

    public void OnDestroy()
    {
        render.Release();
        accelStruct.Dispose();
    }
}
