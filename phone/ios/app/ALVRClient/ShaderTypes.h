//
//  ShaderTypes.h
//

//
//  Header containing types and enum constants shared between Metal shaders and Swift/ObjC source
//
#ifndef ShaderTypes_h
#define ShaderTypes_h

#ifdef __METAL_VERSION__
#define NS_ENUM(_type, _name) enum _name : _type _name; enum _name : _type
typedef metal::int32_t EnumBackingType;
#else
#import <Foundation/Foundation.h>
typedef NSInteger EnumBackingType;
#endif

#include <simd/simd.h>

typedef NS_ENUM(EnumBackingType, BufferIndex)
{
    BufferIndexMeshPositions = 0,
    BufferIndexMeshGenerics  = 1,
    BufferIndexUniforms      = 2
};

typedef NS_ENUM(EnumBackingType, VertexAttribute)
{
    VertexAttributePosition  = 0,
    VertexAttributeTexcoord  = 1,
};

typedef NS_ENUM(EnumBackingType, TextureIndex)
{
    TextureIndexColor    = 0,
};

typedef struct
{
    matrix_float4x4 projectionMatrix;
    matrix_float4x4 modelViewMatrix;
    simd_float4 tangents;
} Uniforms;

typedef struct
{
    Uniforms uniforms[2];
} UniformsArray;

// Lens pass inputs (Renderer.swift fills it, Shaders.metal reads it).
typedef struct
{
    matrix_float4x4 headToWorld;  // head pose between the eyes, meters, recentered
    vector_float4 lens;           // k1, k2, screen-to-lens mm, IPD mm
    vector_float4 screen;         // drawable width px, height px, mm per px, lens center y offset mm
    vector_float4 misc;           // time s, passthrough (1/0), unused, unused
} VRUniforms;

// AR passthrough: the rear camera image behind the frame.
typedef struct
{
    matrix_float4x4 headToCamera; // rotation: display-time head -> camera axes when the image was captured
    vector_float4 intrinsics;     // fx, fy, cx, cy in camera image pixels (ARKit intrinsics)
    vector_float4 imageSize;      // width px, height px, assumed scene depth m, enabled (1/0)
    vector_float4 eyeCenter;      // the eyes' center in camera axes, m
    vector_float4 eyeRight;       // half the IPD along the head's right axis, in camera axes, m
    vector_float4 key;            // stream key: mode (0 none, 1 near-black, 2 magenta), tolerance, softness, unused
} VRCameraUniforms;

// The frame being shown (an ALVR video frame, or test mode's rendered eyes).
typedef struct
{
    matrix_float4x4 reproject;    // rotation: display-time head -> the head the frame was rendered for
    vector_float4 fovTan[2];      // per eye: tan of left, right, up, down edges (left, down negative)
} VRFrameUniforms;

#endif /* ShaderTypes_h */
