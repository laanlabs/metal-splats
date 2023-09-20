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
    
    float a = contentSample.a;
    a = pow(a, 1.2);
    float3 color = (1.0 - a) * bgSample.rgb + contentSample.rgb;
    return float4(color, 1.0);
    
    
}





