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

constexpr sampler linearSampler(mip_filter::linear, mag_filter::linear, min_filter::linear,
                                address::clamp_to_edge);

// Decoded video (Y + CbCr planes) to linear RGB, for the sRGB drawable.
static float3 yuvToLinear(float y, float2 cbcr) {
    const float4x4 ycbcrToRGBTransform = float4x4(
        float4(+1.0000f, +1.0000f, +1.0000f, +0.0000f),
        float4(+0.0000f, -0.3441f, +1.7720f, +0.0000f),
        float4(+1.4020f, -0.7141f, +0.0000f, +0.0000f),
        float4(-0.7010f, +0.5291f, -0.8860f, +1.0000f)
    );
    float3 rgb = (ycbcrToRGBTransform * float4(y, cbcr, 1.0)).rgb;
    float3 condition = float3(rgb < 0.04045);
    float3 lowValues = rgb / 12.92;
    float3 highValues = pow((rgb + 0.055) / 1.055, float3(2.4));
    return condition * lowValues + (1.0 - condition) * highValues;
}

// Upstream full-screen video display (no lens pass). Unused; kept for comparison.
fragment half4 displayTexture(TextureMappingVertex mappingVertex [[ stage_in ]],
                              texture2d<float, access::sample> texture [[ texture(0) ]], texture2d<float, access::sample> texture2 [[ texture(1) ]]) {
    float3 color = yuvToLinear(texture.sample(linearSampler, mappingVertex.textureCoordinate).r,
                               texture2.sample(linearSampler, mappingVertex.textureCoordinate).rg);
    return half4(half3(color), 1.0);
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

// Reprojection + frame lookup: rotate the eye ray from the display-time head into
// the head the frame was rendered for, then find it in that eye's half of the frame
// (side by side, left eye on the left). False if it falls outside the frame.
static bool frameUV(EyeRay e, constant VRFrameUniforms &f, thread float2 &uv) {
    float3 dir = (f.reproject * float4(normalize(float3(e.tanAngle, -1.0)), 0.0)).xyz;
    if (dir.z > -1e-3) return false;
    float2 t = dir.xy / -dir.z;
    int eye = e.eyeSign < 0.0 ? 0 : 1;
    float4 fov = f.fovTan[eye];
    float2 local = float2((t.x - fov.x) / (fov.y - fov.x), (fov.z - t.y) / (fov.z - fov.w));
    if (any(local < 0.0) || any(local > 1.0)) return false;
    uv = float2((float(eye) + local.x) * 0.5, local.y);
    return true;
}

// AR passthrough: where this eye ray lands in the rear camera image. The ray
// starts at the eye (6 cm behind the camera, half an IPD to the side) and is
// assumed to hit something at a fixed depth, which keeps the parallax between
// eye and camera roughly right for a room-scale scene.

// A camera-space point to camera image UV. ARKit camera axes are x right, y up,
// -z forward; image pixels are x right, y down.
static float2 projectToCamera(float3 p, constant VRCameraUniforms &c) {
    float2 px = float2(c.intrinsics.x * (p.x / -p.z) + c.intrinsics.z,
                       c.intrinsics.y * (-p.y / -p.z) + c.intrinsics.w);
    return px / c.imageSize.xy;
}

// The assumed depth is c.imageSize.z: 1.5 m, or the LiDAR scene average. With
// the smoothed LiDAR grid (c.key.w = 1) it's refined along the eye ray: guess a
// distance, read the grid where that point lands in the camera image, move the
// guess to that depth, repeat. The grid is smooth, so this converges and the warp
// bends at edges instead of tearing. Each eye gets its own parallax (stereo).
static float3 cameraColor(EyeRay e, constant VRCameraUniforms &c,
                          texture2d<float, access::sample> camLuma, texture2d<float, access::sample> camChroma,
                          texture2d<float, access::sample> camDepth) {
    if (c.imageSize.w < 0.5) return float3(0.0);
    float3 dirCam = (c.headToCamera * float4(normalize(float3(e.tanAngle, -1.0)), 0.0)).xyz;
    float3 eyeCam = c.eyeCenter.xyz + e.eyeSign * c.eyeRight.xyz;
    float d = c.imageSize.z;
    if (c.key.w > 0.5 && dirCam.z < -1e-3) {
        for (int i = 0; i < 4; i++) {
            float3 p = eyeCam + dirCam * d;
            if (p.z > -1e-3) break;
            float measured = camDepth.sample(linearSampler, projectToCamera(p, c)).r;   // meters along -z
            if (measured < 0.05) break;
            d = clamp((-measured - eyeCam.z) / dirCam.z, 0.1, 10.0);
        }
    }
    float3 p = eyeCam + dirCam * d;
    if (p.z > -1e-3) return float3(0.0);
    float2 uv = projectToCamera(p, c);
    if (any(uv < 0.0) || any(uv > 1.0)) return float3(0.0);
    return yuvToLinear(camLuma.sample(linearSampler, uv).r, camChroma.sample(linearSampler, uv).rg);
}

// How opaque a stream pixel is: key-colored pixels (near-black or magenta) let the camera through.
static float keyAlpha(float3 rgb, constant VRCameraUniforms &c) {
    float tolerance = c.key.y, softness = max(c.key.z, 1e-3);
    if (c.key.x > 1.5) return smoothstep(tolerance, tolerance + softness, distance(rgb, float3(1.0, 0.0, 1.0)));
    if (c.key.x > 0.5) return smoothstep(tolerance, tolerance + softness, dot(rgb, float3(0.2126, 0.7152, 0.0722)));
    return 1.0;
}

// The ALVR stream through the lens pass and reprojection, optionally over the camera.
fragment half4 vrStreamYUV(TextureMappingVertex in [[ stage_in ]],
                           constant VRUniforms &u [[ buffer(0) ]],
                           constant VRFrameUniforms &f [[ buffer(1) ]],
                           constant VRCameraUniforms &c [[ buffer(2) ]],
                           texture2d<float, access::sample> lumaTexture [[ texture(0) ]],
                           texture2d<float, access::sample> chromaTexture [[ texture(1) ]],
                           texture2d<float, access::sample> camLuma [[ texture(2) ]],
                           texture2d<float, access::sample> camChroma [[ texture(3) ]],
                           texture2d<float, access::sample> camDepth [[ texture(4) ]]) {
    EyeRay e = screenToEye(in.renderedCoordinate.xy, u);
    if (!e.valid) return half4(0.0, 0.0, 0.0, 1.0);
    bool passthrough = c.imageSize.w > 0.5;
    float3 background = passthrough ? cameraColor(e, c, camLuma, camChroma, camDepth) : float3(0.0);
    float2 uv;
    if (!frameUV(e, f, uv)) return half4(half3(background), 1.0);
    float3 color = yuvToLinear(lumaTexture.sample(linearSampler, uv).r, chromaTexture.sample(linearSampler, uv).rg);
    float alpha = passthrough ? keyAlpha(color, c) : 1.0;
    return half4(half3(mix(background, color, alpha)), 1.0);
}

// Test mode's rendered eyes through the same lens pass and reprojection; in
// passthrough, the eye texture's alpha says where the camera shows through.
fragment half4 vrStreamRGB(TextureMappingVertex in [[ stage_in ]],
                           constant VRUniforms &u [[ buffer(0) ]],
                           constant VRFrameUniforms &f [[ buffer(1) ]],
                           constant VRCameraUniforms &c [[ buffer(2) ]],
                           texture2d<float, access::sample> frameTexture [[ texture(0) ]],
                           texture2d<float, access::sample> camLuma [[ texture(2) ]],
                           texture2d<float, access::sample> camChroma [[ texture(3) ]],
                           texture2d<float, access::sample> camDepth [[ texture(4) ]]) {
    EyeRay e = screenToEye(in.renderedCoordinate.xy, u);
    if (!e.valid) return half4(0.0, 0.0, 0.0, 1.0);
    bool passthrough = c.imageSize.w > 0.5;
    float3 background = passthrough ? cameraColor(e, c, camLuma, camChroma, camDepth) : float3(0.0);
    float2 uv;
    if (!frameUV(e, f, uv)) return half4(half3(background), 1.0);
    float4 frame = frameTexture.sample(linearSampler, uv);
    float alpha = passthrough ? frame.a : 1.0;
    return half4(half3(mix(background, frame.rgb, alpha)), 1.0);
}

// ---- Test mode ----------------------------------------------------------------
// Test room: 5 x 3 x 5 m box around the recentered start pose (floor at y = 0),
// a 0.5 m grid, one color per wall, and two spheres at different depths.
// Front (-Z) blue, right (+X) red, back (+Z) yellow, left (-X) green.
// In passthrough there are no walls (alpha 0 lets the camera through); instead a
// 0.8 x 0.5 m panel floats 1.3 m ahead, left of center, like a Desktop+ window.
static float4 testRoom(float3 ro, float3 rd, bool passthrough) {
    const float3 sphereC[2] = { float3(0.0, 1.6, -1.5), float3(0.5, 1.3, -0.8) };
    const float sphereR[2] = { 0.25, 0.08 };
    const float3 sphereCol[2] = { float3(1.0, 0.8, 0.2), float3(0.9, 0.2, 0.9) };

    float3 bmin = float3(-2.5, 0.0, -2.5), bmax = float3(2.5, 3.0, 2.5);
    float3 tFar = max((bmin - ro) / rd, (bmax - ro) / rd);
    float tHit = passthrough ? 1e9 : min(min(tFar.x, tFar.y), tFar.z);

    if (passthrough && rd.z < -1e-4) {
        float t = (-1.3 - ro.z) / rd.z;
        float3 p = ro + rd * t;
        float2 local = (p.xy - float2(-0.45, 1.55)) / float2(0.8, 0.5) + 0.5;   // 0..1 on the panel
        if (t > 0.0 && t < tHit && all(local >= 0.0) && all(local <= 1.0)) {
            tHit = t;
            float2 g = local * float2(16.0, 10.0);
            float2 lineDist = abs(fract(g - 0.5) - 0.5) / max(fwidth(g), float2(1e-4));
            float line = 1.0 - min(min(lineDist.x, lineDist.y), 1.0);
            float titleBar = step(0.9, local.y);
            float3 color = mix(float3(0.08, 0.1, 0.16), float3(0.25, 0.45, 0.9), titleBar);
            return float4(mix(color, float3(0.9), line * 0.35), 1.0);
        }
    }

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
        return float4(sphereCol[hitSphere] * light, 1.0);
    }
    if (passthrough) return float4(0.0);

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
    return float4(mix(base, float3(1.0), line * 0.85), 1.0);
}

// Renders the room into a side-by-side eye texture, like the PC renders a frame:
// u.headToWorld is the (possibly delayed) render pose, f.fovTan each eye's FOV.
fragment half4 vrTestEyes(TextureMappingVertex in [[ stage_in ]],
                          constant VRUniforms &u [[ buffer(0) ]],
                          constant VRFrameUniforms &f [[ buffer(1) ]]) {
    float2 uv = in.textureCoordinate;
    int eye = uv.x < 0.5 ? 0 : 1;
    float4 fov = f.fovTan[eye];
    float2 local = float2(fract(uv.x * 2.0), uv.y);
    float2 tanAngle = float2(mix(fov.x, fov.y, local.x), mix(fov.z, fov.w, local.y));
    float3 eyeInHead = float3((eye == 0 ? -0.0005 : 0.0005) * u.lens.w, 0.0, 0.0);   // half the IPD, mm -> m
    float3 ro = (u.headToWorld * float4(eyeInHead, 1.0)).xyz;
    float3 rd = normalize((u.headToWorld * float4(normalize(float3(tanAngle, -1.0)), 0.0)).xyz);
    return half4(testRoom(ro, rd, u.misc.y > 0.5));
}
