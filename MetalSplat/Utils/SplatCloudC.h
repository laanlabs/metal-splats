//
//  SplatCloudC.h
//  MetalSplat
//
//  Created by CC Laan on 9/20/23.
//

#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import <simd/simd.h>


NS_ASSUME_NONNULL_BEGIN

typedef struct PLYLoadParams {
    float random_drop;
    simd_float3 centroid;
} PLYLoadParams;


@interface SplatCloudC : NSObject

@property (nonatomic, readonly) id<MTLBuffer> splatBuffer;
@property (nonatomic, readonly) id<MTLBuffer> tempSplatBuffer;
@property (nonatomic, readonly) id<MTLBuffer> indicesBuffer;

//@property (nonatomic, readonly) NSUInteger elementSizeInBytes;

@property (nonatomic, readonly) NSUInteger numPoints;


- (instancetype)initWithDevice:(id<MTLDevice>)device
                       plyFile:(NSString*)plyFile
                        params:(PLYLoadParams)params;


@end


NS_ASSUME_NONNULL_END
