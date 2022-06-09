Shader "Custom/AccretionDisk"
{
    Properties
    {
        _Color ("Color", Color) = (1,1,1,1)
        _MainTex ("Albedo (RGB)", 2D) = "white" {}
    }
      SubShader
    {
        Tags { "RenderType" = "Opaque" }
        LOD 200
        Pass {

        }

        Pass
        {
          Name "MainRayPass"

          CGPROGRAM

          #pragma raytracing MyHitShader
          #include "RaytraceHelper.cginc"

          Texture2D _MainTex;
          SamplerState sampler_MainTex;

          struct Payload {
            float3 irradiance;
            float atten;
          };

          //https://www.shadertoy.com/view/tsBXW3
          float hash(float x) { return frac(sin(x) * 152754.742); }
          float hash(float2 x) { return hash(x.x + hash(x.y)); }

          float value(float2 p, float f) //value noise
          {
            float bl = hash(floor(p * f + float2(0., 0.)));
            float br = hash(floor(p * f + float2(1., 0.)));
            float tl = hash(floor(p * f + float2(0., 1.)));
            float tr = hash(floor(p * f + float2(1., 1.)));

            float2 fr = frac(p * f);
            fr = (3. - 2. * fr) * fr * fr;
            float b = lerp(bl, br, fr.x);
            float t = lerp(tl, tr, fr.x);
            return lerp(b, t, fr.y);
          }

          //https://www.shadertoy.com/view/4dS3Wd
          float value3D(float3 p) {
            const float3 step = float3(110, 241, 171);

            float3 i = floor(p);
            float3 f = frac(p);

            // For performance, compute the base input to a 1D hash from the integer part of the argument and the 
            // incremental change to the 1D based on the 3D -> 1D wrapping
            float n = dot(i, step);

            float3 u = f * f * (3.0 - 2.0 * f);
            return lerp(lerp(lerp(hash(n + dot(step, float3(0, 0, 0))), hash(n + dot(step, float3(1, 0, 0))), u.x),
              lerp(hash(n + dot(step, float3(0, 1, 0))), hash(n + dot(step, float3(1, 1, 0))), u.x), u.y),
              lerp(lerp(hash(n + dot(step, float3(0, 0, 1))), hash(n + dot(step, float3(1, 0, 1))), u.x),
                lerp(hash(n + dot(step, float3(0, 1, 1))), hash(n + dot(step, float3(1, 1, 1))), u.x), u.y), u.z);
          }

          float fbm(float3 p, float f, int o) {
            float v = 0;
            float a = 0.5;
            for (int i = 0; i < o; i++) {
              v += value3D(p * f) * a;
              f *= 2;
              a *= 0.5;
            }
            return v;
          }

          #define PI 3.1415926535

          float4 raymarchDisk(float3 ray, float3 origin)
          {
            float3 position = origin;
            float lengthPos = length(position.xz);
            int _Steps = 64;

            float thickness = 0.01;
            float stepSize = thickness / _Steps;
            float innerRadius = 1.8;
            float outerRadius = 10;

            float3 l = 0;
            float atten = 1;

            for (int i = 0; i < _Steps; i++)
            {
                position += stepSize * ray;
                float radial = length(position.xz);
                float density = 0;
                density += max(0, fbm(float3(radial, abs(atan2(position.z, position.x) / PI), position.y * 2), 4, 16) * 0.1 - 0.01);
                density += (fbm(float3(position.xz, position.y * 4), 2, 16) * 2 - 1) * 0.02;
                density = max(0, density);
                density *= smoothstep(outerRadius, 4, radial) * smoothstep(2, 2.5, radial);
                density *= 3000;
                float3 emission = float3(0.7, 0.3, 0.1) * (smoothstep(3.5, innerRadius, radial) * 150000 + smoothstep(outerRadius, 2, radial) * 50000 + 100);
                l += 2 * emission * stepSize * density * atten;
                atten *= exp(-density * 2 * stepSize);
            }

            return float4(l, atten);
          }

          [shader("closesthit")]
          void MyHitShader(inout Payload payload : SV_RayPayload,
            AttributeData attributeData : SV_IntersectionAttributes)
          {
              IVertex lerpV;
              GetIntersectionVertex(attributeData, lerpV);
              float3 wp = WorldRayOrigin() + RayTCurrent() * WorldRayDirection();

              float2 uv = lerpV.texCoord0;
              float4 accDisk = raymarchDisk(WorldRayDirection(), wp);
              payload.irradiance += accDisk.rgb * payload.atten;//_MainTex.SampleLevel(sampler_MainTex, uv, 0).rgb * 2;
              payload.atten *= accDisk.a;
          }
          ENDCG
        } 
    }
    FallBack "Diffuse"
}
