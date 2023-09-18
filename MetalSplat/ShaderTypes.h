//
//  ShaderTypes.h
//  MetalSplat
//
//  Created by CC Laan on 9/13/23.
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


typedef struct
{
    matrix_float4x4 projection_matrix;
    matrix_float4x4 model_matrix;
    matrix_float4x4 model_view_matrix;
    matrix_float4x4 inv_model_view_matrix;
    
    simd_float4 camera_pos;
    simd_float4 camera_pos_orig;
    
    float viewport_width;
    float viewport_height;
        
    float focal_x;
    float focal_y;
    float tan_fovx;
    float tan_fovy;
    
    float drag_alpha;
    
    float time;
    
} Uniforms;


// MARK: - Splat stuff


// TODO: pack
typedef struct
{
    simd_float4 center; // xyz_
    simd_float4 color;  // rgba
    simd_float4 scale;  // xyz_
    simd_float4 quat;   // xyzw
    
    // TODO: fix sh
//    simd_float3 sh_0;
//    simd_float3 sh_1_x;
//    simd_float3 sh_1_y;
//    simd_float3 sh_1_z;
        
} Splat;



#endif /* ShaderTypes_h */

