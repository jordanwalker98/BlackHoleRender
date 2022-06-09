Shader "Custom/Planet"
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

          #define PI 3.1415926535
          #define INV_PI (1 / PI)
          #define colorSpaceDielectricSpec half4(0.04, 0.04, 0.04, 1.0 - 0.04) // standard dielectric reflectivity coef at incident angle (= 4%)

          inline half OneMinusReflectivityFromMetallic(half metallic)
          {
            half oneMinusDielectricSpec = colorSpaceDielectricSpec.a;
            return oneMinusDielectricSpec - metallic * oneMinusDielectricSpec;
          }

          half SpecularStrength(half3 specular)
          {
            return max(max(specular.r, specular.g), specular.b);
          }

          inline float Pow2(float x) {
            return x * x;
          }

          inline float Pow3(float x) {
            return x * x * x;
          }

          inline float4 Pow5(float4 x)
          {
            return x * x * x * x * x;
          }

          //most of this is taken from unity builtin shaders
          float PerceptualRoughnessToRoughness(float perceptualRoughness)
          {
            return perceptualRoughness * perceptualRoughness;
          }

          inline half3 FresnelTerm(half3 F0, half cosA)
          {
            half t = Pow5(1 - cosA);   // ala Schlick interpoliation
            return F0 + (1 - F0) * t;
          }

          inline half3 FresnelLerp(half3 F0, half3 F90, half cosA)
          {
            half t = Pow5(1 - cosA);   // ala Schlick interpoliation
            return lerp(F0, F90, t);
          }

          inline float GGXTerm(float NdotH, float roughness)
          {
            float a2 = roughness * roughness;
            float d = (NdotH * a2 - NdotH) * NdotH + 1.0f;
            return INV_PI * a2 / (d * d + 1e-7f);
          }

          // Ref: http://jcgt.org/published/0003/02/03/paper.pdf
          inline float SmithJointGGXVisibilityTerm(float NdotL, float NdotV, float roughness)
          {
          #if 0
            // Original formulation:
            //  lambda_v    = (-1 + sqrt(a2 * (1 - NdotL2) / NdotL2 + 1)) * 0.5f;
            //  lambda_l    = (-1 + sqrt(a2 * (1 - NdotV2) / NdotV2 + 1)) * 0.5f;
            //  G           = 1 / (1 + lambda_v + lambda_l);

            // Reorder code to be more optimal
            half a = roughness;
            half a2 = a * a;

            half lambdaV = NdotL * sqrt((-NdotV * a2 + NdotV) * NdotV + a2);
            half lambdaL = NdotV * sqrt((-NdotL * a2 + NdotL) * NdotL + a2);

            // Simplify visibility term: (2.0f * NdotL * NdotV) /  ((4.0f * NdotL * NdotV) * (lambda_v + lambda_l + 1e-5f));
            return 0.5f / (lambdaV + lambdaL + 1e-5f);  // This function is not intended to be running on Mobile,
                                                        // therefore epsilon is smaller than can be represented by half
          #else
            // Approximation of the above formulation (simplify the sqrt, not mathematically correct but close enough)
            float a = roughness;
            float lambdaV = NdotL * (NdotV * (1 - a) + a);
            float lambdaL = NdotV * (NdotL * (1 - a) + a);

          #if defined(SHADER_API_SWITCH)
                      return 0.5f / (lambdaV + lambdaL + 1e-4f); // work-around against hlslcc rounding error
          #else
                      return 0.5f / (lambdaV + lambdaL + 1e-5f);
          #endif

          #endif
          }

          half DisneyDiffuse(half NdotV, half NdotL, half LdotH, half perceptualRoughness)
          {
            half fd90 = 0.5 + 2 * LdotH * LdotH * perceptualRoughness;
            // Two schlick fresnel term
            half lightScatter = (1 + (fd90 - 1) * Pow5(1 - NdotL));
            half viewScatter = (1 + (fd90 - 1) * Pow5(1 - NdotV));

            return lightScatter * viewScatter;
          }

          float SmoothnessToPerceptualRoughness(float smoothness)
          {
            return (1 - smoothness);
          }

          float3 BRDF_DIRECT(float3 diffColor, float3 specColor, float oneMinusReflectivity, float smoothness,
            float3 normal, float3 viewDir,
            float3 lightDir, float3 lightColor)
          {
            float perceptualRoughness = SmoothnessToPerceptualRoughness(smoothness);
            float3 halfDir = normalize(float3(lightDir)+viewDir);

            float nv = abs(dot(normal, viewDir));    // This abs allow to limit artifact

            float nl = saturate(dot(normal, lightDir));
            float nh = saturate(dot(normal, halfDir));

            half lv = saturate(dot(lightDir, viewDir));
            half lh = saturate(dot(lightDir, halfDir));

            // Diffuse term
            half diffuseTerm = DisneyDiffuse(nv, nl, lh, perceptualRoughness) * nl;

            // Specular term
            float roughness = PerceptualRoughnessToRoughness(perceptualRoughness);
            // GGX with roughtness to 0 would mean no specular at all, using max(roughness, 0.002) here to match HDrenderloop roughtness remapping.
            roughness = max(roughness, 0.002);
            float V = SmithJointGGXVisibilityTerm(nl, nv, roughness);
            float D = GGXTerm(nh, roughness);

            float specularTerm = V * D * PI; // Torrance-Sparrow model, Fresnel is applied later
            // specularTerm * nl can be NaN on Metal in some cases, use max() to make sure it's a sane value
            specularTerm = max(0, specularTerm * nl);

            // surfaceReduction = Int D(NdotH) * NdotH * Id(NdotL>0) dH = 1/(roughness^2+1)
            half surfaceReduction;
            //#   ifdef UNITY_COLORSPACE_GAMMA
            //    surfaceReduction = 1.0 - 0.28 * roughness * perceptualRoughness;      // 1-0.28*x^3 as approximation for (1/(x^4+1))^(1/2.2) on the domain [0;1]
            //#   else
            surfaceReduction = 1.0 / (roughness * roughness + 1.0);           // fade \in [0.5;1]
        //#   endif

            // To provide true Lambert lighting, we need to be able to kill specular completely.
            specularTerm *= any(specColor) ? 1.0 : 0.0;

            half grazingTerm = saturate(smoothness + (1 - oneMinusReflectivity));
            float3 color = diffColor * (lightColor * diffuseTerm)
              + specularTerm * lightColor * FresnelTerm(specColor, lh);

            return color;
          }

          [shader("closesthit")]
          void MyHitShader(inout Payload payload : SV_RayPayload,
            AttributeData attributeData : SV_IntersectionAttributes)
          {
              IVertex lerpV;
              GetIntersectionVertex(attributeData, lerpV);
              float3 wp = WorldRayOrigin() + RayTCurrent() * WorldRayDirection();
              float3 viewDir = WorldRayDirection();

              float metallic = 0;
              float3 albedo = float3(1, 1, 1);
              float oneMinusReflectivity = OneMinusReflectivityFromMetallic(metallic);
              float3 diffuseColor = albedo * oneMinusReflectivity;
              float3 specularColor = lerp(colorSpaceDielectricSpec.rgb, albedo, metallic);

              float3 normal = normalize(mul((float3x3)ObjectToWorld3x4(), lerpV.normalOS));
              float3 lightDir = normalize(-wp);
              float3 light = float3(0.7, 0.3, 0.1) * 150000;
              payload.irradiance += BRDF_DIRECT(diffuseColor, specularColor, oneMinusReflectivity, 0.9, normal, viewDir, lightDir, light);
              payload.atten *= 0;
          }
          ENDCG
        } 
    }
    FallBack "Diffuse"
}
