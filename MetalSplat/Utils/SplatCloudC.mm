//
//  SplatCloudC.m
//  MetalSplat
//
//  Created by CC Laan on 9/20/23.
//

#import "SplatCloudC.h"


#include <stdio.h>
#include <algorithm>
#include <vector>
#include <cstdint>
#include <execution>
#include <fstream>
#include <sstream>
#include <random>

#include <simd/simd.h>
#include <dispatch/dispatch.h>


#import "ShaderTypes.h"


// MARK: - Load PLY


// Define the types and sizes that make up the contents of each Gaussian
// in the trained model.

//typedef sibr::Vector3f Pos;
//typedef simd_float3 Pos;
typedef MTLPackedFloat3 Pos;


template<int D>
struct SHs
{
    float shs[(D+1)*(D+1)*3];
};
struct Scale
{
    float scale[3];
};
struct Rot
{
    float rot[4];
};
template<int D>
struct RichPoint
{
    Pos pos;
    float n[3];
    SHs<D> shs;
    float opacity;
    Scale scale;
    Rot rot;
};

float sigmoid(const float m1)
{
    return 1.0f / (1.0f + exp(-m1));
}

float inverse_sigmoid(const float m1)
{
    return log(m1 / (1.0f - m1));
}


// Load the Gaussians from the given file.
template<int D>
int loadPly(std::string filename,
    std::vector<Pos>& pos,
    std::vector<SHs<3>>& shs,
    std::vector<float>& opacities,
    std::vector<Scale>& scales,
    std::vector<Rot>& rot,
    simd_float3 & minn,
    simd_float3 & maxx,
    PLYLoadParams params)
{
    
    std::ifstream infile(filename, std::ios_base::binary);

    //if (!infile.good())
        //SIBR_ERR << "Unable to find model's PLY file, attempted:\n" << filename << std::endl;

    // "Parse" header (it has to be a specific format anyway)
    std::string buff;
    std::getline(infile, buff);
    std::getline(infile, buff);

    std::string dummy;
    std::getline(infile, buff);
    std::stringstream ss(buff);
    
    int count;
    ss >> dummy >> dummy >> count;
    printf(" ply has %i points \n", count );

    // Output number of Gaussians contained
    //SIBR_LOG << "Loading " << count << " Gaussian splats" << std::endl;

    while (std::getline(infile, buff))
        if (buff.compare("end_header") == 0)
            break;

    // Read all Gaussians at once (AoS)
    std::vector<RichPoint<D>> points(count);
    infile.read((char*)points.data(), count * sizeof(RichPoint<D>));
    
    
    // TODO: Filter points...
    const bool ground_filter = false;
    
    if ( params.random_drop > 0 || ground_filter ) {
        
        std::random_device rd;
        std::mt19937 gen(rd()); // Using the Mersenne Twister 19937 generator
        std::uniform_real_distribution<> dis(0, 1); // Uniform distribution between 0 and 1
        
        // 0.1 = keep 10%
        //const float random_drop = 0.5;
        if ( params.random_drop > 0 ) {
            points.erase(std::remove_if(points.begin(), points.end(), [&](const RichPoint<D>& s) {
                
                return dis(gen) > params.random_drop;
                
            }), points.end());
        }
        
        if ( ground_filter ) {
            points.erase(std::remove_if(points.begin(), points.end(), [&](const RichPoint<D>& s) {
                
                float xz = simd_length( simd_make_float2(s.pos.x, s.pos.z) );
                // filter out ground stage for body anim
                return (s.pos.y <= 3.5) || (xz > 500 && s.pos.y <= 100);
                
            }), points.end());
        }
        
        // update count
        count = (int)points.size();
        
    }
    
    
    // Resize our SoA data
    pos.resize(count);
    shs.resize(count);
    scales.resize(count);
    rot.resize(count);
    opacities.resize(count);
 
    // ..
    minn = {FLT_MAX, FLT_MAX, FLT_MAX};
    maxx = {-FLT_MAX, -FLT_MAX, -FLT_MAX};

    for (int i = 0; i < count; i++)
    {
        maxx = simd_make_float3(
            std::max(maxx.x, points[i].pos.x),
            std::max(maxx.y, points[i].pos.y),
            std::max(maxx.z, points[i].pos.z)
        );

        minn = simd_make_float3(
            std::min(minn.x, points[i].pos.x),
            std::min(minn.y, points[i].pos.y),
            std::min(minn.z, points[i].pos.z)
        );
    }

    std::vector<std::pair<uint64_t, int>> mapp(count);
    for (int i = 0; i < count; i++)
    {
        
        simd_float3 p = simd_make_float3(points[i].pos[0], points[i].pos[1], points[i].pos[2]);
        
        simd_float3 rel = (p - minn) / (maxx - minn);
        simd_float3 scaled = simd_make_float3((float((1 << 21) - 1)) * rel.x,
                                              (float((1 << 21) - 1)) * rel.y,
                                              (float((1 << 21) - 1)) * rel.z);

        int xyz[3] = { (int)round(scaled.x), (int)round(scaled.y), (int)round(scaled.z) };

        uint64_t code = 0;
        for (int j = 0; j < 21; j++) {
            code |= ((uint64_t(xyz[0] & (1 << j))) << (2 * j + 0));
            code |= ((uint64_t(xyz[1] & (1 << j))) << (2 * j + 1));
            code |= ((uint64_t(xyz[2] & (1 << j))) << (2 * j + 2));
        }

        mapp[i].first = code;
        mapp[i].second = i;
    }
    //
    
    
    
    auto sorter = [](const std::pair < uint64_t, int>& a, const std::pair < uint64_t, int>& b) {
        return a.first < b.first;
    };
    std::sort(mapp.begin(), mapp.end(), sorter);

    // Move data from AoS to SoA
    int SH_N = (D + 1) * (D + 1);
    for (int k = 0; k < count; k++)
    {
        int i = mapp[k].second;
        pos[k] = points[i].pos;

        // Normalize quaternion
        float length2 = 0;
        for (int j = 0; j < 4; j++)
            length2 += points[i].rot.rot[j] * points[i].rot.rot[j];
        float length = sqrt(length2);
        for (int j = 0; j < 4; j++)
            rot[k].rot[j] = points[i].rot.rot[j] / length;

        // Exponentiate scale
        for(int j = 0; j < 3; j++)
            scales[k].scale[j] = std::exp(points[i].scale.scale[j]);

        // Activate alpha
        opacities[k] = sigmoid(points[i].opacity);

        shs[k].shs[0] = points[i].shs.shs[0];
        shs[k].shs[1] = points[i].shs.shs[1];
        shs[k].shs[2] = points[i].shs.shs[2];
        for (int j = 1; j < SH_N; j++)
        {
            shs[k].shs[j * 3 + 0] = points[i].shs.shs[(j - 1) + 3];
            shs[k].shs[j * 3 + 1] = points[i].shs.shs[(j - 1) + SH_N + 2];
            shs[k].shs[j * 3 + 2] = points[i].shs.shs[(j - 1) + 2 * SH_N + 1];
        }
    }
    
    return count;
    
}



// MARK: - SplatCloud -

@implementation SplatCloudC {
    // No extra private instance variables needed.
}

- (instancetype)initWithDevice:(id<MTLDevice>)device
                       plyFile:(NSString*)plyFile
                        params:(PLYLoadParams)params {
    
    self = [super init];
    
    if (self) {
                
        
        
        // Load the PLY data (AoS) to the GPU (SoA)
        std::vector<Pos> pos;
        std::vector<Rot> rot;
        std::vector<Scale> scale;
        std::vector<float> opacity;
        std::vector<SHs<3>> shs;
        
        std::string file( plyFile.cString );
        
        simd_float3 _scenemin;
        simd_float3 _scenemax;
        
        int count = 0;
        
        const int sh_degree = 3;
        if (sh_degree == 1)
        {
            count = loadPly<1>(file, pos, shs, opacity, scale, rot, _scenemin, _scenemax, params);
        }
        else if (sh_degree == 2)
        {
            count = loadPly<2>(file, pos, shs, opacity, scale, rot, _scenemin, _scenemax, params);
        }
        else if (sh_degree == 3)
        {
            count = loadPly<3>(file, pos, shs, opacity, scale, rot, _scenemin, _scenemax, params);
        }
        
        // Allocate Metal buffers...
        
        _splatBuffer = [device newBufferWithLength:count * sizeof(Splat) options:MTLResourceStorageModeShared];
        _tempSplatBuffer = [device newBufferWithLength:count * sizeof(Splat) options:MTLResourceStorageModeShared];
        _indicesBuffer = [device newBufferWithLength:count * sizeof(int64_t) options:MTLResourceStorageModeShared];
        
        Splat * splats = (Splat*)_splatBuffer.contents;
        Splat * temp_splats = (Splat*)_tempSplatBuffer.contents;
        
        // TODO: remove extra std::vectors , just go to MTLBuffer
        for ( int i = 0; i < count; ++i ) {
            
            Splat splat;
            
            splat.center = simd_make_float4(pos[i].x, pos[i].y, pos[i].z, 1.0 );
            
            splat.center.x -= params.centroid.x;
            splat.center.y -= params.centroid.y;
            splat.center.z -= params.centroid.z;
            
            const float SH_C0 = 0.28209479177387814;
                                                  
            float r = (0.5 + SH_C0 * shs[i].shs[0] );
            float g = (0.5 + SH_C0 * shs[i].shs[1] );
            float b = (0.5 + SH_C0 * shs[i].shs[2] );
            
            splat.color = simd_make_float4(r, g, b, opacity[i] );
            
            auto q = rot[i].rot;
            auto s = scale[i].scale;
            
            splat.quat = simd_make_float4(q[0], q[1], q[2], q[3]);
            
            splat.scale = simd_make_float4(s[0], s[1], s[2], 1.0);
            
            splats[i] = splat;
            
            temp_splats[i] = splat;
            
        }
        
        
        _numPoints = count;
        
        
    }
    return self;
}





//- (instancetype)initWithDevice:(id<MTLDevice>)device elementCount:(NSUInteger)count {
//    self = [super init];
//    if (self) {
//        _elementSizeInBytes = sizeof(simd_float3);
//        _buffer = [self _createBufferWithDevice:device elementCount:count];
//    }
//    return self;
//}
//
//- (id<MTLBuffer>)_createBufferWithDevice:(id<MTLDevice>)device elementCount:(NSUInteger)count {
//    NSUInteger totalSize = self.elementSizeInBytes * count;
//    void* data = malloc(totalSize);
//    
//    if (!data) {
//        return nil;
//    }
//
//    // Initialize with arbitrary data (in this case, just incrementing values)
//    simd_float3* float3Data = (simd_float3*)data;
//    for (NSUInteger i = 0; i < count; ++i) {
//        float3Data[i] = simd_make_float3((float)i, (float)i + 1, (float)i + 2);
//    }
//    
//    id<MTLBuffer> buffer = [device newBufferWithBytes:data length:totalSize options:MTLResourceStorageModeShared];
//    
//    free(data);
//    
//    return buffer;
//}

@end
