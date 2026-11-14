//
//  Shaders.metal
//

// File for Metal kernel and shader functions

#include <metal_stdlib>
#include <simd/simd.h>

// Including header shared between this Metal shader code and Swift/C code executing Metal API commands
#import "ShaderTypes.h"

using namespace metal;

typedef struct {
    float4 renderedCoordinate [[position]];
    float2 textureCoordinate;
} TextureMappingVertex;

vertex TextureMappingVertex mapTexture(unsigned int vertex_id [[ vertex_id ]]) {
    float4x4 renderedCoordinates = float4x4(float4( -1.0, -1.0, 0.0, 1.0 ),
                                            float4(  1.0, -1.0, 0.0, 1.0 ),
                                            float4( -1.0,  1.0, 0.0, 1.0 ),
                                            float4(  1.0,  1.0, 0.0, 1.0 ));

    float4x2 textureCoordinates = float4x2(float2( 0.0, 1.0 ),
                                           float2( 1.0, 1.0 ),
                                           float2( 0.0, 0.0 ),
                                           float2( 1.0, 0.0 ));
    
    TextureMappingVertex outVertex;
    outVertex.renderedCoordinate = renderedCoordinates[vertex_id];
    outVertex.textureCoordinate = textureCoordinates[vertex_id];
    
    return outVertex;
}

fragment half4 displayTexture(TextureMappingVertex mappingVertex [[ stage_in ]],
                              texture2d<float, access::sample> texture [[ texture(0) ]], texture2d<float, access::sample> texture2 [[ texture(1) ]]) {
    constexpr sampler s(mip_filter::linear,
                        mag_filter::linear,
                        min_filter::linear);
    
    const float4x4 ycbcrToRGBTransform = float4x4(
        float4(+1.0000f, +1.0000f, +1.0000f, +0.0000f),
        float4(+0.0000f, -0.3441f, +1.7720f, +0.0000f),
        float4(+1.4020f, -0.7141f, +0.0000f, +0.0000f),
        float4(-0.7010f, +0.5291f, -0.8860f, +1.0000f)
    );
    
    float4 ycbcr = float4(texture.sample(s, mappingVertex.textureCoordinate).r,
                          texture2.sample(s, mappingVertex.textureCoordinate).rg, 1.0);
    
    float3 rgb_uncorrect = (ycbcrToRGBTransform * ycbcr).rgb;
    
    const float DIV12 = 1. / 12.92;
    const float DIV1 = 1. / 1.055;
    const float THRESHOLD = 0.04045;
    const float3 GAMMA = float3(2.4);
        
    float3 condition = float3(rgb_uncorrect.r < THRESHOLD, rgb_uncorrect.g < THRESHOLD, rgb_uncorrect.b < THRESHOLD);
    float3 lowValues = rgb_uncorrect * DIV12;
    float3 highValues = pow((rgb_uncorrect + 0.055) * DIV1, GAMMA);
    float3 color = condition * lowValues + (1.0 - condition) * highValues;

    return half4(color.r, color.g, color.b, 1.0);
}

// ---- Lens pass ---------------------------------------------------------------
// The phone sits landscape behind two lenses, IPD apart, centered on the screen.
// Each half of the screen is one eye. A screen point at tangent d from its lens
// center is seen at tangent d * (1 + k1 r^2 + k2 r^4) (pincushion lens), so
// drawing each pixel with the scene at that angle cancels the distortion.

struct EyeRay {
    float2 tanAngle;   // where the eye sees this pixel: x right, y up, per unit forward
    float eyeSign;     // -1 left eye, +1 right eye
    bool valid;
};

static EyeRay screenToEye(float2 px, constant VRUniforms &u) {
    EyeRay r;
    float W = u.screen.x, H = u.screen.y, mmPerPx = u.screen.z;
    float2 mm = float2(px.x - 0.5 * W, 0.5 * H - px.y) * mmPerPx;   // from screen center, y up
    r.eyeSign = mm.x < 0.0 ? -1.0 : 1.0;
    float2 lensCenter = float2(r.eyeSign * 0.5 * u.lens.w, u.screen.w);
    float2 d = (mm - lensCenter) / u.lens.z;
    float r2 = dot(d, d);
    r.tanAngle = d * (1.0 + u.lens.x * r2 + u.lens.y * r2 * r2);
    r.valid = abs(mm.x) > 0.5 && length(r.tanAngle) < 2.5;          // 1 mm black divider
    return r;
}

// Test room for test mode: 5 x 3 x 5 m box around the recentered start pose,
// a 0.5 m grid, one color per wall, and two spheres at different depths.
// Front (-Z) blue, right (+X) red, back (+Z) yellow, left (-X) green.
static float3 testRoom(float3 ro, float3 rd) {
    const float3 sphereC[2] = { float3(0.0, 0.0, -1.5), float3(0.5, -0.3, -0.8) };
    const float sphereR[2] = { 0.25, 0.08 };
    const float3 sphereCol[2] = { float3(1.0, 0.8, 0.2), float3(0.9, 0.2, 0.9) };

    float3 bmin = float3(-2.5, -1.6, -2.5), bmax = float3(2.5, 1.4, 2.5);
    float3 tFar = max((bmin - ro) / rd, (bmax - ro) / rd);
    float tHit = min(min(tFar.x, tFar.y), tFar.z);

    int hitSphere = -1;
    for (int i = 0; i < 2; i++) {
        float3 oc = ro - sphereC[i];
        float b = dot(oc, rd);
        float h = b * b - (dot(oc, oc) - sphereR[i] * sphereR[i]);
        if (h > 0.0) {
            float t = -b - sqrt(h);
            if (t > 0.0 && t < tHit) { tHit = t; hitSphere = i; }
        }
    }
    float3 p = ro + rd * tHit;
    if (hitSphere >= 0) {
        float3 n = normalize(p - sphereC[hitSphere]);
        float light = 0.25 + 0.75 * max(dot(n, normalize(float3(0.4, 1.0, 0.3))), 0.0);
        return sphereCol[hitSphere] * light;
    }

    float3 base;
    float2 uv;
    if (tHit == tFar.y) {
        uv = p.xz;
        base = rd.y < 0.0 ? float3(0.25) : float3(0.5);
    } else if (tHit == tFar.x) {
        uv = p.zy;
        base = rd.x < 0.0 ? float3(0.1, 0.45, 0.1) : float3(0.6, 0.12, 0.1);
    } else {
        uv = p.xy;
        base = rd.z < 0.0 ? float3(0.1, 0.2, 0.7) : float3(0.55, 0.5, 0.1);
    }
    float2 g = uv / 0.5;
    float2 lineDist = abs(fract(g - 0.5) - 0.5) / max(fwidth(g), float2(1e-4));
    float line = 1.0 - min(min(lineDist.x, lineDist.y), 1.0);
    return mix(base, float3(1.0), line * 0.85);
}

fragment half4 vrTestScene(TextureMappingVertex in [[ stage_in ]],
                           constant VRUniforms &u [[ buffer(0) ]]) {
    EyeRay e = screenToEye(in.renderedCoordinate.xy, u);
    if (!e.valid) return half4(0.0, 0.0, 0.0, 1.0);
    float3 eyeInHead = float3(e.eyeSign * 0.0005 * u.lens.w, 0.0, 0.0);   // half the IPD, mm -> m
    float3 dirInHead = normalize(float3(e.tanAngle, -1.0));
    float3 ro = (u.headToWorld * float4(eyeInHead, 1.0)).xyz;
    float3 rd = normalize((u.headToWorld * float4(dirInHead, 0.0)).xyz);
    return half4(half3(testRoom(ro, rd)), 1.0);
}
