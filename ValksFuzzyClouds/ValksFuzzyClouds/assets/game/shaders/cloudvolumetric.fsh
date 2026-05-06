#version 330 core
#extension GL_ARB_explicit_attrib_location: enable

// ============================================================
// DEBUG TOGGLES  ?  flip any of these to 0 to disable a feature
// ============================================================

#define DBG_ENABLE_SURFACE_TURBULENCE   1   // Warps cloud top/base with time-animated noise
#define DBG_ENABLE_EDGE_EROSION         1   // Erodes cloud edges with noise (coverage mask) Does it do anything ?
#define DBG_ENABLE_CLOUD_SHADOW         1   // Vertical self-shadow raycast upward through cloud
#define DBG_ENABLE_TOP_BRIGHTENING      1   // Bright rim at cloud tops
#define DBG_ENABLE_BASE_DARKENING       1   // Dark underside shading
#define DBG_ENABLE_RIM_HIGHLIGHT        1   // Thin bright rim at very top when unoccluded
#define DBG_ENABLE_DIRECTION_CURVE      1   // Barrel-curve applied to ray direction
#define DBG_ENABLE_DIRECTION_WARP       1   // Perception-effect warp on ray direction
#define DBG_ENABLE_SMOOTH_SAMPLE_MAP    1   // clouds dont tower anymore 
#define DBG_ENABLE_SMOOTH_SAMPLE_COL    1   // Better k gradient
#define DBG_ENABLE_STEP_SKIP            0   // Adaptive step-size multiplier in empty space


// Visualisation modes (pick at most one ? set others to 0)
#define DBG_VIS_NONE        1   // Normal render
#define DBG_VIS_DENSITY     0   // Greyscale raw density
#define DBG_VIS_HEIGHT      0   // Red = bottom, green = top (h value)
#define DBG_VIS_SHADOW      0   // White = fully occluded from above
#define DBG_VIS_COVERAGE    0   // Coverage mask only (no vertical profile)
#define DBG_VIS_NORMALS     0   // World-space normal approximated from density gradient

#define DBG_OVERRIDE_DENSITY_VALUE  4.0     // Density multiplier when enabled

#define DBG_CLOUD_HEIGHT_VALUE  50

// ============================================================

uniform mat4 iMvpMatrix;
uniform sampler2D depthTex;
uniform sampler2D cloudMap;
uniform sampler2D cloudCol;
uniform sampler2D liquidDepth;
uniform float cloudMapWidth;
uniform vec3 cloudOffset;
uniform int frame;
uniform float time;
uniform int FrameWidth;
uniform float PerceptionEffectIntensity;

in vec2 uv;
in vec2 ndc;

#include dither.fsh
#include oit.fsh

const float cloudTileSize = 50.0;

vec3 hash(vec3 p){
    const uint k = 1103515245U;
    uvec3 x = floatBitsToUint(p);
    x = ((x>>8U)^x.yzx)*k;
    x = ((x>>8U)^x.yzx)*k;
    x = ((x>>8U)^x.yzx)*k;
    return vec3(x)/float(0xffffffffU);
}

float noise(vec3 p){
    vec3 f = smoothstep(0.0, 1.0, fract(p));
    vec3 x = floor(p);
    return mix(mix(mix(hash(x + vec3(0, 0, 0)).x,
    hash(x + vec3(1, 0, 0)).x, f.x),
    mix(hash(x + vec3(0, 1, 0)).x,
    hash(x + vec3(1, 1, 0)).x, f.x), f.y),
    mix(mix(hash(x + vec3(0, 0, 1)).x,
    hash(x + vec3(1, 0, 1)).x, f.x),
    mix(hash(x + vec3(0, 1, 1)).x,
    hash(x + vec3(1, 1, 1)).x, f.x), f.y), f.z);
}

float octave(vec3 p){
    return (noise(p * 2.0) * 0.66 + noise(p * 6.0) * 0.33) * 2.0 - 1.0;
}

mat2 rot(float n){
    return mat2(cos(n), -sin(n), sin(n), cos(n));
}

vec3 warp(vec3 d, float f){
    if(f < 0.0001) return d;
    d.xz *= rot(octave(d * 2.0 + time * 0.05) * f);
    d.xy *= rot(octave(d * 1.5 + time * 0.04) * f);
    d.zy *= rot(octave(d * 1.5 - time * 0.04) * f);
    return normalize(d);
}

vec3 curve(vec3 d, float f){
    d.xy *= rot(d.x * f);
    d.zy *= rot(d.z * f);
    return normalize(d);
}

float luma(vec3 c){
    return dot(c, vec3(0.3, 0.6, 0.1));
}

vec3 unproject(vec4 x){
    return x.xyz / x.w;
}

vec2 intersect(float o, float d, vec2 m){
    m = (m - o) / d;
    float near = min(m.x, m.y);
    float far  = max(m.x, m.y);
    if(near > far || far < 0.0) return vec2(-1.0);
    return vec2(max(0.0, near), max(0.0, far - max(0.0, near)));
}


float halfsmooth(float x, float t){
    return x > t ? (x - t / 2.0) : (x * x * x * (1.0 - x * 0.5 / t) / t / t);
}

// -------------------------------------------------------
// Smooth sampling: 3x3 Gaussian over hardware bilinear taps
// -------------------------------------------------------

vec4 sampleSmooth(vec2 pos) {
    #if DBG_ENABLE_SMOOTH_SAMPLE_MAP
    vec2 texSize = vec2(textureSize(cloudMap, 0));
    vec2 uv      = pos / texSize;
    vec2 texel   = 1.0 / texSize;

    vec4 center = texture(cloudMap, uv);
    vec4 a      = texture(cloudMap, uv + texel * vec2( 1.0,  1.0));
    vec4 b      = texture(cloudMap, uv + texel * vec2(-1.0, -1.0));

    return mix(center, (a + b) * 0.5, 0.35);
    #else
    vec2 texSize = vec2(textureSize(cloudMap, 0));
    return texture(cloudMap, pos / texSize);
    #endif
}

vec4 sampleColSmooth(vec2 pos) {
    #if DBG_ENABLE_SMOOTH_SAMPLE_COL
    vec2 texSize = vec2(textureSize(cloudCol, 0));
    vec2 uv      = pos / texSize;
    vec2 texel   = 1.0 / texSize;

    vec4 center = texture(cloudCol, uv);
    vec4 a      = texture(cloudCol, uv + texel * vec2( 1.0,  1.0));
    vec4 b      = texture(cloudCol, uv + texel * vec2(-1.0, -1.0));


    return mix(center, (a + b) * 0.5, 0.15);
    #else
    vec2 texSize = vec2(textureSize(cloudCol, 0));
    return texture(cloudCol, pos / texSize);
    #endif
}


// -------------------------------------------------------
// Density at a continuous 3D position
// -------------------------------------------------------
float sampleDensity(vec3 pos, vec4 map) {
    if(map.r <= 0.0) return 0.0;

    float base      = map.b;
    float top       = map.a * 0.5;
    float thickness = max(top - base, 1.0);

    vec3 worldPos;
    worldPos.xz = (pos.xz - cloudMapWidth * 0.5) * cloudTileSize + cloudOffset.xz;
    worldPos.y  = pos.y * cloudTileSize * 1.2;

    vec3 noisePos = worldPos / 120.0;

    // --- Surface turbulence ---
    #if DBG_ENABLE_SURFACE_TURBULENCE
    float hRaw = clamp((pos.y - base) / max(top - base, 1.0), 0.0, 1.0);

    vec3 tp = noisePos + vec3(time * 0.018);
    float surfaceTurb = noise(tp * 2.0) * 1.7 + noise(tp * 4.5) * 0.78;
    float heightInfluence = mix(0.0, 1.0, pow(hRaw, 1.2));
    float turbDisplace = (surfaceTurb - 0.5) * thickness * 0.5 * heightInfluence;



    float surfaceTurbBottom =  noise(tp * 4.5) * 0.28;
    float turbDisplaceBottom = (surfaceTurbBottom - 0.2)  * thickness;


    float effectiveTop  = top  + turbDisplace;
    float effectiveBase = base + turbDisplaceBottom;
    #else
    float effectiveTop  = top;
    float effectiveBase = base;
    #endif

    float h = clamp((pos.y - effectiveBase * 0.3) / max(effectiveTop - effectiveBase, 0.3), 0.0, 1.0);

    float vertProfile = smoothstep(0.0, 0.08, h)
    * (1.0 - smoothstep(0.08, 1.0, h));
    vertProfile = pow(vertProfile, 3.0);

    // --- Edge erosion ---
    float edgeDist = map.r;
    #if DBG_ENABLE_EDGE_EROSION
    vec3 ep = noisePos + vec3(time * 0.01);
    float erosion = noise(ep *  4.0) * 0.50;

    const float erosionStrength = 0.55;
    const float edgeBand        = 1.5;
    float coverage = smoothstep(0.0, edgeBand, edgeDist - (1.0 - erosion) * erosionStrength);
    #else
    float coverage = smoothstep(0.0, 0.5, edgeDist);
    #endif

    return coverage * vertProfile;
}


float cloudShadow(vec3 pos) {
    vec4 map = sampleSmooth(pos.xz);

    float base      = map.b;
    float top       = map.a * 0.5;
    float coverage  = map.r;

    if(coverage <= 0.0) return 0.0;

    float h = clamp((pos.y - base) / max(top - base, 1.0), 0.0, 1.0);
    float overhead = (1.0 - h) * coverage;

    return smoothstep(0.0, 1.0, clamp(overhead * 1.4, 0.0, 1.0));
}


vec4 shadedCloudColour(vec3 pos, float h, float shadow,float thickness ) {
    vec4 baseCol = sampleColSmooth(pos.xz);
    vec3 src = baseCol.rgb;

    float dayBrightness = clamp(luma(src) * 1.5, 0.0, 1.0);

    float brightness = 1.0;

    brightness += smoothstep(0.25, 1.0, h) * dayBrightness;

    brightness += (1.0 - smoothstep(0.0, 0.55, h)) * 0.1;
    
    
    
    brightness -= shadow * 0.25 * (1.0 - 0.55);
    
    brightness += smoothstep(0.75, 0.98, h) * (1.0 - shadow) * (0.5 + dayBrightness * 0.4) * 0.3;

    return vec4(src * brightness, baseCol.a);
}


float igNoise(vec2 co) {
    return fract(52.9829189 * fract(dot(co, vec2(0.06711056, 0.00583715))));
}

vec4 traverse(vec3 o, vec3 d, float far, float T) {


    float verticalBias = 1.0 + 3.0 * abs(d.y);
    int STEPS = clamp(int(far * 3.0 * verticalBias), 4, 128);

    float DENSITY = DBG_OVERRIDE_DENSITY_VALUE;



    float stepSize = far / float(STEPS);
    vec4  k        = vec4(0.0);


    float tOffset = igNoise(gl_FragCoord.xy + float(frame & 7) * 0.61803);
    float t = stepSize * (0.5 + tOffset);
    float stepMult  = 1.0;

    
    
    
    for(int i = 0; i < STEPS; i++){
        if(t >= far || k.a > 0.99) break;

        vec3 pos = o + d * t;

        float cheapDensity = texture(cloudMap, pos.xz / cloudMapWidth).r;

        if(cheapDensity > 0.0){
            stepMult = 1.0;

            vec4 map = sampleSmooth(pos.xz);
            float density = sampleDensity(pos,map);

            if(density > 0.0){
                float base = map.b;
                float top  = map.a * 0.5;
                float h    = clamp((pos.y - base) / max(top - base, 1.0), 0.0, 1.0);

                float shadow = cloudShadow(pos);
                vec4 col   = shadedCloudColour(pos, h, shadow, map.r);

                float densityBoost = mix(2.5, 1.0, clamp(far / 4.0, 0.0, 1.0));

                
                float tmpDENSITY =  DENSITY;
                if((col.r + col.g + col.b )/3.0 < 0.5){
                    tmpDENSITY += (col.r + col.g + col.b );
                }
                
                
                float alpha = 1.0 - exp(-density  * tmpDENSITY);
                
              
                
                k.rgb += (1.0 - k.a) * col.rgb * alpha;

               
                
                k.a   += (1.0 - k.a) * alpha;

                float bin = log(halfsmooth(( T  + t) * 50.0, 500.0) / OIT_BIN_SCALE + 1.0);
                for(int i = 0; i < OIT_BINS; i++){
                    float b = OITbellcurve(bin - float(i));
                    if(i == (OIT_BINS-1) && bin > float(OIT_BINS-1)) b = 1.0;
                    OITreveal[i] *= 1.0 - col.a * alpha * b;
                }
                
                
            }
        }else{
            #if DBG_ENABLE_STEP_SKIP
            stepMult = min(stepMult * 1.2, 4);
            #else
            stepMult = 1.0;
            #endif
        }

        t += stepSize * stepMult;
    }

    return k;
}

void main(){

    vec3 origin    = unproject(iMvpMatrix * vec4(ndc, -1.0, 1.0));
    vec3 direction = normalize(unproject(iMvpMatrix * vec4(ndc, 1.0, 1.0)) - origin);
    vec3 world     = unproject(iMvpMatrix * vec4(ndc, texture(depthTex, uv).r * 2.0 - 1.0, 1.0));
    vec3 liquid = unproject(iMvpMatrix * vec4(ndc, texelFetch(liquidDepth, ivec2(gl_FragCoord / 4.0), 0).r * 2.0 - 1.0, 1.0));

    float far = min(
    distance(origin, world),
    distance(origin, liquid)
    );

    #if DBG_ENABLE_DIRECTION_CURVE
    direction = curve(direction, 0.11);
    #endif
    #if DBG_ENABLE_DIRECTION_WARP
    direction = warp(direction, PerceptionEffectIntensity * 0.03);
    #endif

    origin.y -= cloudOffset.y + DBG_CLOUD_HEIGHT_VALUE;

    vec2 plane = intersect(
    origin.y,
    direction.y,
    vec2(-12.5 - 500.0 * 0.1-15.0, 12.5 + 500.0)
    );

    float near = plane.x;

    if(near < 0.0 || far < near) discard;

    origin += direction * near;
    origin.xz -= cloudOffset.xz;
    origin /= cloudTileSize;
    origin.xz += cloudMapWidth / 2.0;

    far -= near;
    far  = min(far, plane.y);
    far  = min(far, cloudMapWidth * cloudTileSize / 2.0 - near);
    far /= cloudTileSize;


    outGlow = OITaccumulation0 = OITaccumulation1 = OITaccumulation2 = vec4(0.0);
    OITreveal = outReveal = vec4(1.0);
    
    vec4 k = traverse(origin, direction, far, plane.x / cloudTileSize);

    if(k.a <= 0.0) discard;
    
    
    float s = FrameWidth / 240.0 / 11.0;
    float n = NoiseFromPixelPosition(ivec2(gl_FragCoord.xy), frame + 256, FrameWidth).r * s;
    
    k =  exp(log(k + 1.0) + n) - 1.0;

    if(k.a <= 0.0) discard;

    for(int i = 0; i < OIT_BINS; i++)
        OITaccumulate(i, k * (1.0 - OITreveal[i]));


    outReveal = vec4(1.0 - k.a);
    outGlow.a = k.a;
}
