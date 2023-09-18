#include "Library/Random.metal"

typedef struct {
    float time;
} BlendUniforms;

static constexpr sampler s = sampler( min_filter::linear, mag_filter::linear );

fragment float4 blendFragment
(
    VertexData in [[stage_in]],
    constant BlendUniforms &uniforms [[buffer( FragmentBufferMaterialUniforms )]],
    texture2d<float, access::sample> bgTex [[texture( FragmentTextureCustom0 )]],
    texture2d<float, access::sample> contentTex [[texture( FragmentTextureCustom1 )]]
)
{
    
    const float4 bgSample = bgTex.sample( s, in.uv );
 
    float4 contentSample = contentTex.sample( s, in.uv );

    // bit softer AR edges
    contentSample.a = pow(contentSample.a, 3);
    
    float4 color = mix(bgSample, contentSample, contentSample.a);
    
    return color;
    
}





