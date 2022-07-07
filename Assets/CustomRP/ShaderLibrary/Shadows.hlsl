﻿//阴影采样
#ifndef CUSTOM_SHADOWS_INCLUDED
#define CUSTOM_SHADOWS_INCLUDED

#include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Shadow/ShadowSamplingTent.hlsl"
//如果使用的是 PCF 3x3
#if defined(_DIRECTIONAL_PCF3)
//需要4个滤波样本
    #define DIRECTIONAL_FILTER_SAMPLES 4
    #define DIRECTIONAL_FILTER_SETUP SampleShadow_ComputeSamples_Tent_3x3
#elif defined(_DIRECTIONAL_PCF5)
    #define DIRECTIONAL_FILTER_SAMPLES 9
    #define DIRECTIONAL_FILTER_SETUP SampleShadow_ComputeSamples_Tent_5x5
#elif defined(_DIRECTIONAL_PCF7)
    #define DIRECTIONAL_FILTER_SAMPLES 16
    #define DIRECTIONAL_FILTER_SETUP SampleShadow_ComputeSamples_Tent_7x7
#endif

#define MAX_SHADOWD_DIRECTIONAL_LIGHT_COUNT 4
//阴影图集
TEXTURE2D_SHADOW(_DirectionalShadowAtlas);
#define SHADOW_SAMPLER sampler_linear_clamp_compare
SAMPLER_CMP(SHADOW_SAMPLER);

//阴影数据
struct ShadowData
{
    int cascadeIndex; 
    //是否采样阴影标识
    float strength;
};

#define MAX_CASCADE_COUNT 4
CBUFFER_START(_CustomShadows)
//级联数量和包围球数据
int _CascadeCount;
float4 _CascadeCullingSpheres[MAX_CASCADE_COUNT];
//级联数据
float4 _CascadeData[MAX_CASCADE_COUNT];
//阴影转换矩阵
float4x4 _DirectionalShadowMatrices[MAX_SHADOWD_DIRECTIONAL_LIGHT_COUNT * MAX_CASCADE_COUNT];
//float _ShadowDistance;
//阴影过渡
float4 _ShadowDistanceFade;
float4 _ShadowAtlasSize;
CBUFFER_END

//阴影的数据信息
struct DirectionalShadowData{
    float strength;
    int tileIndex;
    //法线偏差
    float normalBias;
};

//采样阴影图集
float SampleDirectionalShadowAtlas(float3 positionSTS)  //阴影纹理空间中的表面位置
{
    return SAMPLE_TEXTURE2D_SHADOW(_DirectionalShadowAtlas,SHADOW_SAMPLER,positionSTS);
}

//通过 DIRECTIONAL_FILTER_SETUP 方法获取多个采样权重和位置，然后根据这些信息采样
float FilterDirectionalShadow(float3 positionSTS)
{
#if defined(DIRECTIONAL_FILTER_SETUP)
    //样本权重
    float weights[DIRECTIONAL_FILTER_SAMPLES];
    //样本位置
    float2 positions[DIRECTIONAL_FILTER_SAMPLES];
    float4 size = _ShadowAtlasSize.yyxx;    //xy分量是图集纹素大小，zw分量是图集尺寸
    DIRECTIONAL_FILTER_SETUP(size,positionSTS.xy,weights,positions);
    float shadow = 0;
    for(int i = 0 ; i < DIRECTIONAL_FILTER_SAMPLES; i++)
    {
        //遍历所有样本得到权重和
        shadow += weights[i] * SampleDirectionalShadowAtlas(float3(positions[i].xy,positionSTS.z));
    }
    return shadow;
#else
    return SampleDirectionalShadowAtlas(positionSTS);
#endif
}

//计算阴影衰减
float GetDirectionalShadowAttenuation(DirectionalShadowData directional,ShadowData global, Surface surfaceWS)
{
    if(directional.strength <= 0.0)
    {
        return 1.0;
    }
    //计算法线偏差
    float3 normalBias = surfaceWS.normal * (directional.normalBias * _CascadeData[global.cascadeIndex].y);
    
    //通过阴影转换矩阵和表面位置得到阴影纹理（图块）空间的位置，然后对图集进行采样
    float3 positionSTS = mul(_DirectionalShadowMatrices[directional.tileIndex],float4(surfaceWS.position + normalBias,1.0)).xyz;
    //float shadow = SampleDirectionalShadowAtlas(positionSTS);
    float shadow = FilterDirectionalShadow(positionSTS);
    //最终阴影衰减值是阴影强度和衰减因子的插值
    return lerp(1.0,shadow,directional.strength);
}

//公式计算阴影过渡时的强度
float FadeShadowStrength(float distance,float scale,float fade)
{
    return saturate((1.0 - distance * scale) * fade);
}

//得到世界空间的表面阴影数据
ShadowData GetShadowData(Surface surfaceWS)
{
    ShadowData data;
    //阴影最大距离的过渡阴影强度
    data.strength = FadeShadowStrength(surfaceWS.depth,_ShadowDistanceFade.x , _ShadowDistanceFade.y);
    int i;
    //如果物体表面到球心的平方距离小于球体半径的平方，就说明该物体在这层级联包围球中，得到合适的级联层级索引
    for(i = 0; i<_CascadeCount; i++)
    {
        float4 sphere = _CascadeCullingSpheres[i];
        float distanceSqr = DistanceSquared(surfaceWS.position,sphere.xyz);
        if(distanceSqr < sphere.w)
        {
            //如果绘制的对象在最后一个级联的范围内，计算级联的过渡阴影强度，和阴影最大距离的过渡阴影强度相乘得到最终阴影强度
            if(i == _CascadeCount - 1)
            {   
                data.strength *= FadeShadowStrength(distanceSqr , _CascadeData[i].x,_ShadowDistanceFade.z);
            }
            break;
        }
    }
    if(i == _CascadeCount) 
    {
        data.strength = 0.0;
    }
    data.cascadeIndex = i;
    return data;
}

#endif