//
//  splat_utils.cpp
//  MetalSplat
//
//  Created by CC Laan on 9/15/23.
//

#include <stdio.h>
#include <algorithm>
#include <vector>
#include <cstdint>
#include <execution>


#include <simd/simd.h>
#include <dispatch/dispatch.h>

#include <vector>

#import "ShaderTypes.h"


extern "C" void sort_splats( void * splat_buffer,
                             void * temp_splat_buffer,
                             void * splat_index_buffer,
                             Uniforms uniforms,
                             int num_splats ) {
    
    
    
    Splat * splats = (Splat*)splat_buffer;
    Splat * temp_splats = (Splat*)temp_splat_buffer;
    
    int64_t * splat_index = (int64_t*)splat_index_buffer;
    
    //NSDate * d1 = [NSDate date];
    
    std::sort(splat_index, splat_index + num_splats);
        
    //NSLog(@"  std::sort took %.2f ms ", d1.timeIntervalSinceNow * -1000.0 );
    
    for (int i = 0; i < num_splats; ++i) {
        int index = static_cast<int>(splat_index[i] & 0xFFFFFFFF);
        temp_splats[i] = splats[index];
    }
    
    memcpy(splats, temp_splats, num_splats * sizeof(Splat) );
    
}

