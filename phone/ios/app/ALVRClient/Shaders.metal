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
constexpr sampler nearestSampler(filter::nearest, address::clamp_to_edge);

struct CameraSample {
    float3 color;
    float realDistance;     // real surface along the eye ray (LiDAR), m; very far if unknown
    float personMatte;      // 1 where ARKit's person segmentation sees a person (hands, arms)
    float personDistance;   // that person along the eye ray, m; very far if unknown
};

static CameraSample cameraSample(EyeRay e, constant VRCameraUniforms &c,
                                 texture2d<float, access::sample> camLuma, texture2d<float, access::sample> camChroma,
                                 texture2d<float, access::sample> camDepth, texture2d<float, access::sample> camDepthFull,
                                 texture2d<float, access::sample> personMatte, texture2d<float, access::sample> personDepth) {
    CameraSample s;
    s.color = float3(0.0);
    s.realDistance = 1e4;
    s.personMatte = 0.0;
    s.personDistance = 1e4;
    if (c.imageSize.w < 0.5) return s;
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
    if (p.z > -1e-3) return s;
    float2 uv = projectToCamera(p, c);
    if (any(uv < 0.0) || any(uv > 1.0)) return s;
    s.color = yuvToLinear(camLuma.sample(linearSampler, uv).r, camChroma.sample(linearSampler, uv).rg);
    // Occlusion, looked up at the same spot in the camera image: c.occlusion.w is
    // 1 for ARKit's person matte (sharp, people and hands only), 2 for raw LiDAR.
    if (c.occlusion.x > 0.5 && dirCam.z < -1e-3) {
        if (c.occlusion.w > 1.5) {
            float z = camDepthFull.sample(linearSampler, uv).r;
            if (z > 0.05) s.realDistance = (-z - eyeCam.z) / dirCam.z;
        } else {
            s.personMatte = personMatte.sample(linearSampler, uv).r;
            float z = personDepth.sample(nearestSampler, uv).r;   // dilated past the matte's edge
            if (z > 0.05) s.personDistance = (-z - eyeCam.z) / dirCam.z;
        }
    }
    return s;
}

// How much of the virtual content survives: 0 where something real is in front of it.
static float occlusionAlpha(CameraSample cam, float virtualDistance, constant VRCameraUniforms &c) {
    if (c.occlusion.x < 0.5) return 1.0;
    float soft = max(c.occlusion.z, 1e-3);
    if (c.occlusion.w > 1.5) return smoothstep(-soft, soft, cam.realDistance - virtualDistance);
    float personInFront = 1.0 - smoothstep(-soft, soft, cam.personDistance - virtualDistance);
    return 1.0 - cam.personMatte * personInFront;
}

// How opaque a stream pixel is: key-colored pixels (near-black or magenta) let the camera through.
static float keyAlpha(float3 rgb, constant VRCameraUniforms &c) {
    float tolerance = c.key.y, softness = max(c.key.z, 1e-3);
    if (c.key.x > 1.5) return smoothstep(tolerance, tolerance + softness, distance(rgb, float3(1.0, 0.0, 1.0)));
    if (c.key.x > 0.5) return smoothstep(tolerance, tolerance + softness, dot(rgb, float3(0.2126, 0.7152, 0.0722)));
    return 1.0;
}

// The ALVR stream through the lens pass and reprojection, optionally over the camera.
// The stream has no depth, so occlusion treats it as c.occlusion.y away: hands closer cut through.
fragment half4 vrStreamYUV(TextureMappingVertex in [[ stage_in ]],
                           constant VRUniforms &u [[ buffer(0) ]],
                           constant VRFrameUniforms &f [[ buffer(1) ]],
                           constant VRCameraUniforms &c [[ buffer(2) ]],
                           texture2d<float, access::sample> lumaTexture [[ texture(0) ]],
                           texture2d<float, access::sample> chromaTexture [[ texture(1) ]],
                           texture2d<float, access::sample> camLuma [[ texture(2) ]],
                           texture2d<float, access::sample> camChroma [[ texture(3) ]],
                           texture2d<float, access::sample> camDepth [[ texture(4) ]],
                           texture2d<float, access::sample> camDepthFull [[ texture(5) ]],
                           texture2d<float, access::sample> personMatte [[ texture(6) ]],
                           texture2d<float, access::sample> personDepth [[ texture(7) ]]) {
    EyeRay e = screenToEye(in.renderedCoordinate.xy, u);
    if (!e.valid) return half4(0.0, 0.0, 0.0, 1.0);
    bool passthrough = c.imageSize.w > 0.5;
    CameraSample cam = cameraSample(e, c, camLuma, camChroma, camDepth, camDepthFull, personMatte, personDepth);
    float2 uv;
    if (!frameUV(e, f, uv)) return half4(half3(cam.color), 1.0);
    float3 color = yuvToLinear(lumaTexture.sample(linearSampler, uv).r, chromaTexture.sample(linearSampler, uv).rg);
    float alpha = passthrough ? keyAlpha(color, c) * occlusionAlpha(cam, c.occlusion.y, c) : 1.0;
    return half4(half3(mix(cam.color, color, alpha)), 1.0);
}

// Test mode's rendered eyes through the same lens pass and reprojection; in
// passthrough, the eye texture's alpha says where the camera shows through, and
// its distance texture lets real things in front hide the virtual ones.
fragment half4 vrStreamRGB(TextureMappingVertex in [[ stage_in ]],
                           constant VRUniforms &u [[ buffer(0) ]],
                           constant VRFrameUniforms &f [[ buffer(1) ]],
                           constant VRCameraUniforms &c [[ buffer(2) ]],
                           texture2d<float, access::sample> frameTexture [[ texture(0) ]],
                           texture2d<float, access::sample> frameDistance [[ texture(1) ]],
                           texture2d<float, access::sample> camLuma [[ texture(2) ]],
                           texture2d<float, access::sample> camChroma [[ texture(3) ]],
                           texture2d<float, access::sample> camDepth [[ texture(4) ]],
                           texture2d<float, access::sample> camDepthFull [[ texture(5) ]],
                           texture2d<float, access::sample> personMatte [[ texture(6) ]],
                           texture2d<float, access::sample> personDepth [[ texture(7) ]]) {
    EyeRay e = screenToEye(in.renderedCoordinate.xy, u);
    if (!e.valid) return half4(0.0, 0.0, 0.0, 1.0);
    bool passthrough = c.imageSize.w > 0.5;
    CameraSample cam = cameraSample(e, c, camLuma, camChroma, camDepth, camDepthFull, personMatte, personDepth);
    float2 uv;
    if (!frameUV(e, f, uv)) return half4(half3(cam.color), 1.0);
    float4 frame = frameTexture.sample(linearSampler, uv);
    float alpha = 1.0;
    if (passthrough) {
        float virtualDistance = frameDistance.sample(linearSampler, uv).r;
        alpha = frame.a * occlusionAlpha(cam, virtualDistance, c);
    }
    return half4(half3(mix(cam.color, frame.rgb, alpha)), 1.0);
}

// ---- Test mode ----------------------------------------------------------------
// Test room: 5 x 3 x 5 m box around the recentered start pose (floor at y = 0),
// a 0.5 m grid, one color per wall, and two spheres at different depths.
// Front (-Z) blue, right (+X) red, back (+Z) yellow, left (-X) green.
// In passthrough there are no walls (alpha 0 lets the camera through); instead a
// 0.8 x 0.5 m panel floats 1.3 m ahead, left of center, like a Desktop+ window.
// `distance` gets the hit distance along rd (m), or 1e4 where nothing is hit.
static float4 testRoom(float3 ro, float3 rd, bool passthrough, thread float &distance) {
    distance = 1e4;
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
            distance = t;
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
        distance = tHit;
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
    distance = tHit;
    return float4(mix(base, float3(1.0), line * 0.85), 1.0);
}

struct TestEyesOut {
    half4 color [[ color(0) ]];
    float distance [[ color(1) ]];   // along the eye ray, m (for occlusion)
};

// Renders the room into a side-by-side eye texture, like the PC renders a frame:
// u.headToWorld is the (possibly delayed) render pose, f.fovTan each eye's FOV.
fragment TestEyesOut vrTestEyes(TextureMappingVertex in [[ stage_in ]],
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
    TestEyesOut out;
    float distance;
    out.color = half4(testRoom(ro, rd, u.misc.y > 0.5, distance));
    out.distance = distance;
    return out;
}

// ---- Sword game (no SteamVR) --------------------------------------------------
// Emergency mode: the phone draws the sword game itself, ray traced per eye pixel,
// then shows it through the same lens pass as test mode. Renderer.swift's
// SaberGame fills the scene (an array of float4):
//   0-1 blade emitter (w: 1 if the hand is tracked), 2-3 blade tip, 4-5 blade color,
//   6 info (box count, time, score, combo), 7-10 flash center + radius,
//   11-14 flash color + strength, 15-16 hilt base, 17 scoreboard center, 18 its right axis,
//   19+ boxes, 5 each: center (w: cut face code), three half-axes, color.
constant int SABER_BOX0 = 19;

static float3 saberSky(float3 d) {
    float3 c = mix(float3(0.07, 0.045, 0.15), float3(0.015, 0.015, 0.035), smoothstep(0.0, 0.5, d.y));
    return c + float3(0.32, 0.16, 0.5) * exp(-abs(d.y) * 30.0) * 0.3;
}

static float3 saberFog(float3 c, float3 rd, float t) {
    return mix(c, saberSky(rd), 1.0 - exp(-t * 0.07));
}

// Ray against a capsule (pa to pb, radius r): distance along the ray, or -1.
static float saberCapsule(float3 ro, float3 rd, float3 pa, float3 pb, float r) {
    float3 ba = pb - pa, oa = ro - pa;
    float baba = dot(ba, ba), bard = dot(ba, rd), baoa = dot(ba, oa), rdoa = dot(rd, oa), oaoa = dot(oa, oa);
    float a = baba - bard * bard, b = baba * rdoa - baoa * bard, c = baba * oaoa - baoa * baoa - r * r * baba;
    float h = b * b - a * c;
    if (h >= 0.0 && a > 1e-8) {
        float t = (-b - sqrt(h)) / a;
        float y = baoa + t * bard;
        if (y > 0.0 && y < baba) return t;
        float3 oc = (y <= 0.0) ? oa : ro - pb;
        b = dot(rd, oc);
        c = dot(oc, oc) - r * r;
        h = b * b - c;
        if (h > 0.0) return -b - sqrt(h);
    }
    return -1.0;
}

static float saberSeg(float2 p, float2 a, float2 b) {
    float2 pa = p - a, ba = b - a;
    return length(pa - ba * clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0));
}

// Seven-segment digit in units of its height (y from -0.5 to 0.5): distance to the lit segments.
static float saberDigit(float2 p, int digit, thread float &unlit) {
    int masks[10] = { 0x3F, 0x06, 0x5B, 0x4F, 0x66, 0x6D, 0x7D, 0x07, 0x7F, 0x6F };
    int m = digit < 0 ? 0 : masks[digit];
    float w = 0.27;
    float2 A[7] = { float2(-w, 0.5), float2(w, 0.5), float2(w, 0.0), float2(-w, -0.5), float2(-w, 0.0), float2(-w, 0.5), float2(-w, 0.0) };
    float2 B[7] = { float2(w, 0.5), float2(w, 0.0), float2(w, -0.5), float2(w, -0.5), float2(-w, -0.5), float2(-w, 0.0), float2(w, 0.0) };
    float lit = 1e3;
    unlit = 1e3;
    for (int i = 0; i < 7; i++) {
        float d = saberSeg(p, A[i] * 0.86, B[i] * 0.86);
        if ((m >> i) & 1) lit = min(lit, d); else unlit = min(unlit, d);
    }
    return lit;
}

static float4 saberScene(float3 ro, float3 rd, constant float4 *S, thread float &distance) {
    float tHit = 1e4;
    float3 col = saberSky(rd);

    // Floor: dark with a blue grid, fading into the horizon glow.
    if (rd.y < -1e-4) {
        float t = -ro.y / rd.y;
        if (t > 0.0 && t < 60.0) {
            tHit = t;
            float2 p = (ro + rd * t).xz;
            float2 g1 = p / 0.5, g2 = p / 2.0;
            float2 l1 = abs(fract(g1 - 0.5) - 0.5) / max(fwidth(g1), float2(1e-4));
            float2 l2 = abs(fract(g2 - 0.5) - 0.5) / max(fwidth(g2), float2(1e-4));
            float3 c = float3(0.025, 0.03, 0.06)
                     + float3(0.10, 0.18, 0.35) * (1.0 - min(min(l1.x, l1.y), 1.0)) * 0.5
                     + float3(0.20, 0.35, 0.70) * (1.0 - min(min(l2.x, l2.y), 1.0)) * 0.6;
            col = saberFog(c, rd, t);
        }
    }

    // Boxes: target cubes and sliced halves (dark glass, glowing edges, hot cut face).
    int count = int(S[6].x);
    int hitBox = -1, hitAxis = 0;
    float hitSide = 1.0;
    for (int i = 0; i < count; i++) {
        int o = SABER_BOX0 + i * 5;
        float3 c = S[o].xyz;
        float tmin = 0.0, tmax = 1e4;
        int axis = 0;
        float side = 1.0;
        for (int k = 0; k < 3; k++) {
            float3 A = S[o + 1 + k].xyz;
            float h = length(A);
            float3 u = A / h;
            float oc = dot(ro - c, u), d = dot(rd, u);
            d = abs(d) < 1e-6 ? 1e-6 : d;
            float t1 = (-h - oc) / d, t2 = (h - oc) / d;
            float tn = min(t1, t2), tf = max(t1, t2);
            if (tn > tmin) { tmin = tn; axis = k; side = d > 0.0 ? -1.0 : 1.0; }
            tmax = min(tmax, tf);
        }
        if (tmin < tmax && tmin > 0.0 && tmin < tHit) { tHit = tmin; hitBox = i; hitAxis = axis; hitSide = side; }
    }
    if (hitBox >= 0) {
        int o = SABER_BOX0 + hitBox * 5;
        float3 c = S[o].xyz, color = S[o + 4].xyz;
        float3 p = ro + rd * tHit;
        float3 q, hs;
        for (int k = 0; k < 3; k++) {
            float3 A = S[o + 1 + k].xyz;
            hs[k] = length(A);
            q[k] = dot(p - c, A / hs[k]) / hs[k];
        }
        float3 n = normalize(S[o + 1 + hitAxis].xyz) * hitSide;
        float3 dm = (1.0 - abs(q)) * hs;
        float e = dm.x + dm.y + dm.z - min(dm.x, min(dm.y, dm.z)) - max(dm.x, max(dm.y, dm.z));
        float w = fwidth(e) + 1e-5;
        float edge = 1.0 - smoothstep(0.0055 - w, 0.0055 + w, e);
        float halo = exp(-e * 70.0);
        float inset = (1.0 - smoothstep(0.0, w * 1.5, abs(e - 0.026))) * 0.35;
        float diff = max(dot(n, normalize(float3(0.35, 1.0, 0.25))), 0.0) * 0.55 + 0.18;
        float3 r = reflect(rd, n);
        float spec = pow(max(dot(r, normalize(float3(0.35, 1.0, 0.25))), 0.0), 40.0);
        float fres = pow(1.0 - max(dot(n, -rd), 0.0), 2.5);
        float3 glow = color * 1.7 + 0.12;
        float3 bc = color * (0.05 + 0.09 * diff) + color * fres * 0.55 + spec * 0.5 + glow * (edge + halo * 0.45 + inset);
        float code = S[o].w;
        if (abs(code) > 0.5) {
            int k = int(abs(code)) - 1;
            float heat = fract(abs(code)) / 0.9;
            if (k == hitAxis && sign(code) == hitSide) {
                bc = mix(color * 0.5, float3(1.0, 0.92, 0.75) * 2.2, heat) * (0.35 + heat) + glow * edge;
            }
        }
        col = saberFog(bc, rd, tHit);
    }

    // Hilts: metal capsules behind each blade.
    for (int h = 0; h < 2; h++) {
        if (S[h].w < 0.5) continue;
        float3 pa = S[15 + h].xyz, pb = S[h].xyz;
        float t = saberCapsule(ro, rd, pa, pb, 0.017);
        if (t > 0.0 && t < tHit) {
            tHit = t;
            float3 p = ro + rd * t;
            float3 ba = pb - pa;
            float y = clamp(dot(p - pa, ba) / dot(ba, ba), 0.0, 1.0);
            float3 n = normalize(p - (pa + ba * y));
            float3 r = reflect(rd, n);
            float env = 0.08 + 0.6 * exp(-abs(r.y) * 10.0) + pow(max(dot(r, normalize(float3(0.35, 1.0, 0.25))), 0.0), 50.0) * 1.5;
            float band = step(0.5, fract(y * 9.0)) * step(y, 0.55);   // ribbed grip
            float3 metal = mix(float3(0.55, 0.57, 0.62), float3(0.05), band) * env;
            col = metal + S[4 + h].xyz * 0.15;
        }
    }

    // Scoreboard: glowing seven-segment digits floating ahead.
    {
        float3 C = S[17].xyz, R = S[18].xyz;
        float3 N = normalize(cross(R, float3(0.0, 1.0, 0.0)));
        float dn = dot(rd, N);
        if (abs(dn) > 1e-4) {
            float t = dot(C - ro, N) / dn;
            if (t > 0.0 && t < tHit) {
                float3 p = ro + rd * t;
                float H = 0.38;
                float2 l = float2(dot(p - C, R), p.y - C.y) / H;
                int score = int(S[6].z);
                float pitch = 0.85;
                float best = 1e3, dim = 1e3;
                for (int i = 0; i < 4; i++) {
                    float2 dp = l - float2((float(i) - 1.5) * pitch, 0.0);
                    if (abs(dp.x) > 0.45 || abs(dp.y) > 0.6) continue;
                    int place = 3 - i;
                    int v = score;
                    for (int j = 0; j < place; j++) v /= 10;
                    int digit = (v == 0 && place > 0) ? -1 : v % 10;
                    float un;
                    best = min(best, saberDigit(dp, digit, un));
                    dim = min(dim, un);
                }
                float aa = fwidth(l.x) * 1.5;
                float on = 1.0 - smoothstep(0.05 - aa, 0.05 + aa, best);
                float off = 1.0 - smoothstep(0.05 - aa, 0.05 + aa, dim);
                col += float3(0.6, 0.9, 1.0) * on * 1.4 + float3(0.05, 0.07, 0.12) * off;
                col += float3(0.3, 0.6, 1.0) * exp(-best * 25.0) * 0.25;
            }
        }
    }

    // Blades: a white-hot core and a colored glow, hidden behind anything nearer.
    for (int h = 0; h < 2; h++) {
        if (S[h].w < 0.5) continue;
        float3 A = S[h].xyz, B = S[2 + h].xyz, bcol = S[4 + h].xyz;
        float3 ab = B - A, w0 = ro - A;
        float bb = dot(rd, ab), cc = dot(ab, ab), dd = dot(rd, w0), ee = dot(ab, w0);
        float den = cc - bb * bb;
        float s = den > 1e-8 ? clamp((ee - bb * dd) / den, 0.0, 1.0) : 0.0;
        float3 P = A + ab * s;
        float tr = max(dot(P - ro, rd), 0.0);
        float dist = length(ro + rd * tr - P);
        if (tr < tHit) {
            float core = 1.0 - smoothstep(0.008, 0.012, dist);
            col = mix(col, mix(bcol, float3(1.0), 0.75) * 1.3, core);
            col += bcol * (0.9 * exp(-dist * 60.0) + 0.35 * exp(-dist * 14.0));
            if (core > 0.5) tHit = tr;
        }
    }

    // Slice flashes.
    for (int i = 0; i < 4; i++) {
        float4 F = S[7 + i], FC = S[11 + i];
        if (FC.w <= 0.0) continue;
        float tr = max(dot(F.xyz - ro, rd), 0.0);
        float dist = length(ro + rd * tr - F.xyz);
        if (tr < tHit + F.w) col += FC.rgb * FC.w * exp(-(dist * dist) / (F.w * F.w));
    }

    distance = tHit;
    return float4(col, 1.0);
}

fragment TestEyesOut vrSaberEyes(TextureMappingVertex in [[ stage_in ]],
                                 constant VRUniforms &u [[ buffer(0) ]],
                                 constant VRFrameUniforms &f [[ buffer(1) ]],
                                 constant float4 *scene [[ buffer(2) ]]) {
    float2 uv = in.textureCoordinate;
    int eye = uv.x < 0.5 ? 0 : 1;
    float4 fov = f.fovTan[eye];
    float2 local = float2(fract(uv.x * 2.0), uv.y);
    float2 tanAngle = float2(mix(fov.x, fov.y, local.x), mix(fov.z, fov.w, local.y));
    float3 eyeInHead = float3((eye == 0 ? -0.0005 : 0.0005) * u.lens.w, 0.0, 0.0);
    float3 ro = (u.headToWorld * float4(eyeInHead, 1.0)).xyz;
    float3 rd = normalize((u.headToWorld * float4(normalize(float3(tanAngle, -1.0)), 0.0)).xyz);
    TestEyesOut out;
    float distance;
    out.color = half4(saberScene(ro, rd, scene, distance));
    out.distance = distance;
    return out;
}
