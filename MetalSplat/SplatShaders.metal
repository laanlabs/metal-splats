//
//  SplatShaders.metal
//  MetalSplat
//
//  Created by CC Laan on 9/14/23.
//

#include <metal_stdlib>
#include <simd/simd.h>

// Including header shared between this Metal shader code and Swift/C code executing Metal API commands
#import "ShaderTypes.h"

using namespace metal;

/*
// Spherical harmonics coefficients
constant float SH_C0 = 0.28209479177387814;
constant float SH_C1 = 0.4886025119029199;

constant float SH_C2[] = {
    1.0925484305920792,
    -1.0925484305920792,
    0.31539156525252005,
    -1.0925484305920792,
    0.5462742152960396
};
constant float SH_C3[] = {
    -0.5900435899266435,
    2.890611442640554,
    -0.4570457994644658,
    0.3731763325901154,
    -0.4570457994644658,
    1.445305721320277,
    -0.5900435899266435
};

// NOTE: broken 
inline float3 computeColorFromSH(thread const Splat * splat,
                                 float3 cam_pos) {
    
    
    float3 dir = splat->center.xyz - cam_pos;
    
    dir = dir / length(dir);
    
    float3 result = SH_C0 * splat->sh_0;
    
    const int deg = 1;
    
    if (deg > 0)
    {
        float x = dir.x;
        float y = dir.y;
        float z = dir.z;
        
        //result = result - (SH_C1 * y * sh[1] + SH_C1 * z * sh[2] - SH_C1 * x * sh[3]);
        result = result - (SH_C1 * y * splat->sh_1_x + SH_C1 * z * splat->sh_1_y - SH_C1 * x * splat->sh_1_z );
        
        
        if (deg > 1)
        {
            float xx = x * x, yy = y * y, zz = z * z;
            float xy = x * y, yz = y * z, xz = x * z;
            result = result +
                SH_C2[0] * xy * sh[4] +
                SH_C2[1] * yz * sh[5] +
                SH_C2[2] * (2.0f * zz - xx - yy) * sh[6] +
                SH_C2[3] * xz * sh[7] +
                SH_C2[4] * (xx - yy) * sh[8];

            if (deg > 2)
            {
                result = result +
                    SH_C3[0] * y * (3.0f * xx - yy) * sh[9] +
                    SH_C3[1] * xy * z * sh[10] +
                    SH_C3[2] * y * (4.0f * zz - xx - yy) * sh[11] +
                    SH_C3[3] * z * (2.0f * zz - 3.0f * xx - 3.0f * yy) * sh[12] +
                    SH_C3[4] * x * (4.0f * zz - xx - yy) * sh[13] +
                    SH_C3[5] * z * (xx - yy) * sh[14] +
                    SH_C3[6] * x * (xx - 3.0f * yy) * sh[15];
            }
        }
                 
    }
    
    result += 0.5f;

    return max(result, 0.0f);
    //return max( min(1.0, result), 0.0f);
    
}
*/

 
// Vertex of each quad instance, so will just be [(-1,1), (-1,-1) .. etc ]
// We will transform it into 3d gaussian position via the per instance data
struct VertexIn {
    float2 position;
};

struct VertexOut {
    
    float4 position [[position]];
    
    //float pointSize [[point_size]];
    float4 color;
    float3 conic;
    
    float2 center_screen_pos;
    
    float is_valid;
    
};

struct CameraParameters {
    float focal_x;
    float focal_y;
    float tan_fovx;
    float tan_fovy;
};


// Forward method for converting scale and rotation properties of each
// Gaussian to a 3D covariance matrix in world space. Also takes care
// of quaternion normalization.

float3x3 computeCov3D(float3 scale, float mod, float4 rot) {
    
    // Create scaling matrix
    float3x3 S = float3x3(1.0);
    S[0][0] = mod * scale.x;
    S[1][1] = mod * scale.y;
    S[2][2] = mod * scale.z;

    // Normalize quaternion to get valid rotation
    // (The normalization step is commented out in your CUDA code)
    // float4 q = normalize(rot);
    float4 q = rot;
    float r = q.x;
    float x = q.y;
    float y = q.z;
    float z = q.w;

    // Compute rotation matrix from quaternion
    float3x3 R = float3x3(
        1.f - 2.f * (y * y + z * z), 2.f * (x * y - r * z), 2.f * (x * z + r * y),
        2.f * (x * y + r * z), 1.f - 2.f * (x * x + z * z), 2.f * (y * z - r * x),
        2.f * (x * z - r * y), 2.f * (y * z + r * x), 1.f - 2.f * (x * x + y * y)
    );

    float3x3 M = S * R;

    // Compute 3D world covariance matrix Sigma
    float3x3 Sigma = transpose(M) * M;

    // Since Sigma is symmetric, we would traditionally only store the upper right.
    // But for this Metal conversion, let's just return the whole Sigma matrix for simplicity.
    return Sigma;
}



float3 transformPoint4x3(thread const float3& p, constant const float4x4& matrix) {
    float3 transformed = {
        matrix[0][0] * p.x + matrix[1][0] * p.y + matrix[2][0] * p.z + matrix[3][0],
        matrix[0][1] * p.x + matrix[1][1] * p.y + matrix[2][1] * p.z + matrix[3][1],
        matrix[0][2] * p.x + matrix[1][2] * p.y + matrix[2][2] * p.z + matrix[3][2]
    };
    return transformed;
}

float3 computeCov2D(thread const float3& mean,
                    thread const CameraParameters& params,
                    thread const float3x3& cov3D,
                    constant const float4x4& viewmatrix)
{
    
    // Initialize transformation matrix and perform point transformation
    float3 t = transformPoint4x3(mean, viewmatrix);

    const float limx = 1.3f * params.tan_fovx;
    const float limy = 1.3f * params.tan_fovy;
    const float txtz = t.x / t.z;
    const float tytz = t.y / t.z;
    t.x = min(limx, max(-limx, txtz)) * t.z;
    t.y = min(limy, max(-limy, tytz)) * t.z;

    // Compute Jacobian (J) and viewport scaling (W) matrices
    float3x3 J = float3x3(
        params.focal_x / t.z, 0.0f, -(params.focal_x * t.x) / (t.z * t.z),
        0.0f, params.focal_y / t.z, -(params.focal_y * t.y) / (t.z * t.z),
        0, 0, 0
    );

    float3x3 W = float3x3(
        viewmatrix[0][0], viewmatrix[1][0], viewmatrix[2][0],
        viewmatrix[0][1], viewmatrix[1][1], viewmatrix[2][1],
        viewmatrix[0][2], viewmatrix[1][2], viewmatrix[2][2]
    );

    // Compute transformed covariance matrix (T)
    float3x3 T = W * J;

    // Create covariance matrix (Vrk)
    float3x3 Vrk = cov3D;

    // Compute final covariance matrix (cov)
    float3x3 cov = transpose(T) * transpose(Vrk) * T;

    // Apply low-pass filter
    cov[0][0] += 0.3f;
    cov[1][1] += 0.3f;

    return float3(cov[0][0], cov[0][1], cov[1][1]);
    
}



// MARK: - Vertex -
vertex VertexOut splat_vertex(device VertexIn const *vertices [[buffer(0)]],
                             const device Splat *instances [[buffer(1)]],
                             constant Uniforms & uniforms [[ buffer(2) ]],
                             uint vertexID [[vertex_id]],
                             uint instanceID [[instance_id]])
{
    
    VertexIn vertexIn = vertices[vertexID];
    Splat instance = instances[instanceID];
    
    VertexOut out;
    out.position = float4(0,0,0,1);
    out.is_valid = 0.0;
    
    float2 quad_pos = vertexIn.position;
    float2 viewport(uniforms.viewport_width, uniforms.viewport_height);
        
    // Project gaussian center into clip, then NDC by dividing by w
    float3 p_orig = instance.center.xyz;// * float3(1,1,-1);
    float4 p_world = uniforms.model_matrix * float4(p_orig, 1);
    //const float4 p_cam = uniforms.modelViewMatrix * float4(p_orig, 1);
    
    // uniforms.invModelView
    //const float camera_pos_in_splat = uniforms.invModelMatrix * float4(uniforms.cameraPos);
    
    const float4 center_clip_pos = uniforms.projection_matrix * uniforms.model_view_matrix * float4(p_orig, 1);
            
    const float proj_x = -1.0;
    out.center_screen_pos = (center_clip_pos.xy / center_clip_pos.w * float2(0.5, 0.5*proj_x) + 0.5) * viewport;
    
    
    // Compute 3d covariance matrix from scaling and rotation parameters
    //const float3x3 cov3D = computeCov3D(scales[idx], scale_modifier, rotations[idx], cov3Ds + idx * 6);
    const float scale_modifier = 1.0;
    const float3x3 cov3D = computeCov3D(instance.scale.xyz, scale_modifier, instance.quat);
    
    CameraParameters cam_params;
    //cam_params = extractCameraParameters(viewport, uniforms.projectionMatrix);
    cam_params.focal_x = uniforms.focal_x;
    cam_params.focal_y = uniforms.focal_y;
    cam_params.tan_fovx = uniforms.tan_fovx;
    cam_params.tan_fovy = uniforms.tan_fovy;
    
    // Compute 2D screen-space covariance matrix
    float3 cov = computeCov2D(p_orig, cam_params, cov3D, uniforms.model_view_matrix);
            
    // Invert covariance (EWA algorithm)
    float det = (cov.x * cov.z - cov.y * cov.y);
    
    if (det == 0.0f)
        return out;
    
    float det_inv = 1.f / det;
    float3 conic = { cov.z * det_inv, -cov.y * det_inv, cov.x * det_inv };
    out.conic = conic;
        
    // Compute extent in screen space (by finding eigenvalues of
    // 2D covariance matrix). Use extent to compute a bounding rectangle
    // of screen-space tiles that this Gaussian overlaps with. Quit if
    // rectangle covers 0 tiles.
    float mid = 0.5f * (cov.x + cov.z);
    float lambda1 = mid + sqrt(max(0.1f, mid * mid - det));
    float lambda2 = mid - sqrt(max(0.1f, mid * mid - det));
    float radius = ceil(3.f * sqrt(max(lambda1, lambda2)));
    
    
    
    float2 deltaScreenPos = quad_pos * radius * 2 / viewport;
    
    out.position = center_clip_pos;
    out.position.xy += deltaScreenPos * center_clip_pos.w;
    
    out.is_valid = true;
    
    
    //out.color = instance.color;
    
    
    float4 splat_color = instance.color; // rgb is SH degree 0, opacity is
    
    // TODO: fix
    //float3 rgb = computeColorFromSH(&instance, uniforms.camera_pos_orig.xyz );
    //splat_color.rgb = rgb;
    
    // mix in neon drag color
    float4 drag_color(0, 1, 0.16, 0.85);
    float w = 0.5 + 0.5 * sin(p_world.y * 20 + uniforms.time * 10 );
    w = pow(w, 2);
    float mix_amount = min( uniforms.drag_alpha * w, 0.88 );
    out.color = mix(splat_color, drag_color, mix_amount );
    
    
    return out;
    
}


inline float CalcPowerFromConic(float3 conic, float2 d)
{
    return -0.5 * (conic.x * d.x*d.x + conic.z * d.y*d.y) + conic.y * d.x*d.y;
}

inline float2 CalcScreenSpaceDelta(float2 svPositionXY,
                                   float2 centerXY,
                                   float proj_x)
                                   //float4 projectionParams)
{
    float2 d = svPositionXY - centerXY;
    d.y *= proj_x;
    return d;
}

// MARK: - Fragment

fragment float4 splat_fragment(VertexOut in [[stage_in]],
                               constant Uniforms & uni [[ buffer(2) ]] )
{
    
    if ( in.is_valid < 0.5 ) {
        discard_fragment();
    }
        
    const float proj_x = 1.0;
    const float2 d = CalcScreenSpaceDelta(in.position.xy, in.center_screen_pos, proj_x);
    
    float power = CalcPowerFromConic(in.conic, d);
    
    // float alpha = min(0.99f, con_o.w * exp(power));
    in.color.a *= saturate(exp(power));
    //in.color.a = 0.2;
    
    if ( in.color.a < 1.0/255.0 ) {
        discard_fragment();
    }
    
    
    const float alpha = in.color.a;
    return float4(in.color.rgb * alpha, alpha);
    
}


// MARK: - Compute

// Set the index along with camera depth for sorting on CPU
kernel void splat_set_depths(device int64_t * splat_indices [[buffer(0)]],
                             const device Splat * splats [[buffer(1)]],
                             constant Uniforms & uniforms [[ buffer(2) ]],
                             uint index [[thread_position_in_grid]] )
{
            
    Splat splat = splats[index];
    
    float x = splat.center.x;
    float y = splat.center.y;
    float z = splat.center.z;

    float depth = 0;
    
    float4x4 mat = uniforms.inv_model_view_matrix;
    
    depth = mat.columns[2].x * x + mat.columns[2].y * y + mat.columns[2].z * z;
    
    depth = -depth;
    depth = depth * 1000.0f;
            
    int32_t depthInt = static_cast<int32_t>(depth);
    int64_t packed = static_cast<int64_t>(depthInt) << 32 | index;

    splat_indices[index] = packed;
        
}
