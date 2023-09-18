//
//  BridgingHeader.h
//  MetalSplat
//
//  Created by CC Laan on 9/15/23.
//

#import "ShaderTypes.h"


void sort_splats( void * splat_buffer, 
                  void * temp_splat_buffer,
                  void * splat_index_buffer, 
                  Uniforms uniforms,
                  int num_splats );

