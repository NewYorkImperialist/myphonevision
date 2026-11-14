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
    vector_float4 misc;           // time s, unused, unused, unused
} VRUniforms;

// The frame being shown (an ALVR video frame, or test mode's rendered eyes).
typedef struct
{
    matrix_float4x4 reproject;    // rotation: display-time head -> the head the frame was rendered for
    vector_float4 fovTan[2];      // per eye: tan of left, right, up, down edges (left, down negative)
} VRFrameUniforms;

#endif /* ShaderTypes_h */
