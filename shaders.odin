package main

BACKGROUND_VERTEX_SHADER :: `
#version 330

in vec3 vertexPosition;
in vec2 vertexTexCoord;
in vec4 vertexColor;

out vec2 fragTexCoord;
out vec4 fragColor;

uniform mat4 mvp;

void main() {
    fragTexCoord = vertexTexCoord;
    fragColor = vertexColor;
    gl_Position = mvp * vec4(vertexPosition, 1.0);
}
`

BACKGROUND_FRAGMENT_SHADER :: `
#version 330

in vec2 fragTexCoord;
in vec4 fragColor;

out vec4 finalColor;

uniform sampler2D texture0;
uniform float time;
uniform vec2 resolution;

// Cloud shadow parameters
const float CLOUD_SPEED = 0.02;
const float CLOUD_SCALE = 4.0;
const float CLOUD_DENSITY = 0.4;
const float CLOUD_LAYERS = 2.0;

// Tree movement parameters
const float TREE_SPEED = 2.0;
const float TREE_AMPLITUDE = 0.004;
const float TREE_WAVE_SCALE = 15.0;

// Color masking parameters
const vec3 TARGET_GREEN = vec3(0.2, 0.8, 0.2);
const float COLOR_THRESHOLD = 0.35;
const float MASK_SOFTNESS = 0.25;

// Enhanced noise function for cloud shadows
float noise(vec2 p) {
    vec2 ip = floor(p);
    vec2 u = fract(p);
    u = u * u * (3.0 - 2.0 * u);
    
    float res = mix(
        mix(sin(dot(ip, vec2(12.9898, 78.233))),
            sin(dot(ip + vec2(1.0, 0.0), vec2(12.9898, 78.233))), u.x),
        mix(sin(dot(ip + vec2(0.0, 1.0), vec2(12.9898, 78.233))),
            sin(dot(ip + vec2(1.0, 1.0), vec2(12.9898, 78.233))), u.x),
        u.y);
    return 0.5 + 0.5 * res;
}

// Layered cloud shadows
float cloudShadows(vec2 uv, float time) {
    float shadow = 0.0;
    float scale = CLOUD_SCALE;
    float speed = CLOUD_SPEED;
    float amplitude = 1.0;
    
    // Add multiple layers of clouds
    for(float i = 0.0; i < CLOUD_LAYERS; i++) {
        // Offset each layer differently
        vec2 offset = vec2(time * speed * (1.0 + i * 0.5), time * speed * 0.3 * (1.0 + i * 0.5));
        shadow += noise((uv * scale + offset)) * amplitude;
        
        // Adjust parameters for next layer
        scale *= 1.8;
        speed *= 0.7;
        amplitude *= 0.5;
    }
    
    return shadow / CLOUD_LAYERS;
}

// Calculate how "green" a color is
float getGreenness(vec3 color) {
    // Check if green is the dominant channel
    bool isGreenDominant = color.g > color.r && color.g > color.b;
    
    // Calculate how close the color is to our target green
    float greenDistance = length(color - TARGET_GREEN);
    
    // Create a soft mask based on the green distance
    float mask = 1.0 - smoothstep(COLOR_THRESHOLD - MASK_SOFTNESS, 
                                COLOR_THRESHOLD + MASK_SOFTNESS, 
                                greenDistance);
    
    // Only return mask value if green is dominant
    return isGreenDominant ? mask : 0.0;
}

void main() {
    vec2 uv = fragTexCoord;
    vec4 texColor = texture(texture0, uv);
    
    // Calculate green mask
    float greenMask = getGreenness(texColor.rgb);
    
    // Enhanced tree movement
    float treeInfluence = 1.0 - smoothstep(0.0, 0.6, uv.y);  // Increased vertical influence
    float windWave = sin(time * TREE_SPEED + uv.y * TREE_WAVE_SCALE) * 
                    cos(time * TREE_SPEED * 0.7 + uv.x * TREE_WAVE_SCALE * 0.5);
    float movement = windWave * TREE_AMPLITUDE;
    
    // Apply movement based on green mask with enhanced effect
    vec2 distortedUV = uv + vec2(movement * treeInfluence * (greenMask + 0.1), 
                                movement * treeInfluence * greenMask * 0.2);  // Added slight vertical movement
    
    // Sample texture with distorted coordinates
    texColor = texture(texture0, distortedUV);
    
    // Enhanced cloud shadows with multiple layers
    float cloudShadow = cloudShadows(uv, time);
    float shadowIntensity = mix(1.0, 0.75, cloudShadow * CLOUD_DENSITY);
    
    // Apply cloud shadows with varying effect based on green mask
    float shadowEffect = mix(
        mix(1.0, shadowIntensity, 0.3),  // Base shadow effect for non-green areas
        mix(1.0, shadowIntensity, 1.0),  // Full shadow effect for green areas
        greenMask
    );
    
    finalColor = texColor * vec4(vec3(shadowEffect), 1.0) * fragColor;
}
`

RAYMARCH_VERTEX_SHADER :: `
#version 330

in vec3 vertexPosition;
in vec2 vertexTexCoord;
in vec4 vertexColor;

out vec2 fragTexCoord;
out vec4 fragColor;

uniform mat4 mvp;

void main() {
    fragTexCoord = vertexTexCoord;
    fragColor = vertexColor;
    gl_Position = mvp * vec4(vertexPosition, 1.0);
}
`

RAYMARCH_FRAGMENT_SHADER :: `
#version 330

in vec2 fragTexCoord;
in vec4 fragColor;

out vec4 finalColor;

uniform sampler2D texture0;
uniform float time;
uniform vec2 resolution;
uniform vec4 tintColor;

// Configurable uniforms for effects
uniform float u_shimmerStrength = 0.4;    // Overall intensity of the shimmer (0.0 - 1.0)
uniform float u_pulseSpeed = 3.0;         // Speed of the pulsing effect
uniform float u_pulseRange = 0.1;         // Range of the pulse effect (0.0 - 1.0)
uniform vec3 u_glowColor = vec3(0.5, 0.8, 1.0);  // Color of the glow effect (RGB)
uniform float u_glowIntensity = 0.4;      // Intensity of the glow (0.0 - 1.0)

// Enhanced parameters
const float MAX_STEPS = 100.0;
const float MAX_DIST = 5.0;
const float SURF_DIST = 0.01;
const float SHIMMER_SPEED = 2.0;

// Improved noise function
vec2 hash22(vec2 p) {
    vec3 p3 = fract(vec3(p.xyx) * vec3(.1031, .1030, .0973));
    p3 += dot(p3, p3.yzx+33.33);
    return fract((p3.xx+p3.yz)*p3.zy);
}

// Enhanced smooth noise
float smoothNoise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0-2.0*f);
    
    float a = dot(hash22(i), f);
    float b = dot(hash22(i + vec2(1.0, 0.0)), f - vec2(1.0, 0.0));
    float c = dot(hash22(i + vec2(0.0, 1.0)), f - vec2(0.0, 1.0));
    float d = dot(hash22(i + vec2(1.0, 1.0)), f - vec2(1.0, 1.0));
    
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// Enhanced flow field
float flowField(vec2 p) {
    float noise1 = smoothNoise(p * 2.0 + time * SHIMMER_SPEED);
    float noise2 = smoothNoise(p * 4.0 - time * SHIMMER_SPEED * 0.5);
    
    return sin(p.x * 2.0 + noise1) * cos(p.y * 2.0 + noise2) * 0.5;
}

// Enhanced raymarch with glow
vec2 raymarch(vec2 ro, vec2 rd) {
    float dO = 0.0;
    float glow = 0.0;
    
    for(float i = 0.0; i < MAX_STEPS; i++) {
        vec2 p = ro + rd * dO;
        float dS = flowField(p);
        
        // Accumulate glow based on field strength
        glow += (1.0 - abs(dS)) / (1.0 + i * 0.1);
        
        dO += abs(dS) * 0.5;
        if(dO > MAX_DIST) break;
    }
    
    return vec2(dO, glow * u_glowIntensity * 0.1);  // Apply glow intensity
}

// Enhanced color cycling function
vec3 cycleColors(float t) {
    t *= 0.2;  // Slow down the color cycle
    
    // Define a rich color palette
    vec3 c1 = vec3(0.0, 0.8, 0.2);   // Emerald green
    vec3 c2 = vec3(0.8, 0.0, 0.2);   // Ruby red
    vec3 c3 = vec3(1.0, 0.8, 0.0);   // Gold
    vec3 c4 = vec3(0.2, 0.8, 0.0);   // Forest green
    vec3 c5 = vec3(0.8, 0.2, 0.0);   // Scarlet
    vec3 c6 = vec3(1.0, 0.6, 0.0);   // Amber
    
    float p = fract(t);
    if (p < 0.166) {
        return mix(c1, c2, p * 6.0);
    } else if (p < 0.333) {
        return mix(c2, c3, (p - 0.166) * 6.0);
    } else if (p < 0.5) {
        return mix(c3, c4, (p - 0.333) * 6.0);
    } else if (p < 0.666) {
        return mix(c4, c5, (p - 0.5) * 6.0);
    } else if (p < 0.833) {
        return mix(c5, c6, (p - 0.666) * 6.0);
    } else {
        return mix(c6, c1, (p - 0.833) * 6.0);
    }
}

void main() {
    vec2 uv = fragTexCoord;
    vec4 texColor = texture(texture0, uv);
    
    // Only apply effects to non-transparent pixels
    if(texColor.a > 0.0) {
        // Center and scale UVs for raymarch
        vec2 centered = (uv * 2.0 - 1.0) * 2.0;
        
        // Get raymarch distance and glow
        vec2 march = raymarch(centered, normalize(vec2(0.0) - centered));
        float d = march.x;
        float glow = march.y;
        
        // Create dynamic shimmer effect with configurable strength
        float shimmer = (1.0 - d/MAX_DIST) * u_shimmerStrength;
        
        // Add time-based color variation with cycling colors
        vec3 shimmerColor = mix(
            vec3(1.0),
            cycleColors(time * 0.1),  // Use the new color cycling function
            shimmer + glow
        );
        
        // Add configurable pulsing with color variation
        float pulse = sin(time * u_pulseSpeed) * u_pulseRange + (1.0 - u_pulseRange);
        shimmerColor *= pulse;
        
        // Add subtle color shift based on UV position
        vec3 uvColor = cycleColors(time * 0.05 + uv.x + uv.y);
        shimmerColor = mix(shimmerColor, uvColor, 0.3);
        
        // Blend with original texture while preserving alpha
        finalColor = vec4(texColor.rgb * shimmerColor, texColor.a) * fragColor;
    } else {
        finalColor = texColor * fragColor;
    }
}
`

HEX_TRUCHET_VERTEX_SHADER :: `
#version 330

in vec3 vertexPosition;
in vec2 vertexTexCoord;
in vec4 vertexColor;

out vec2 fragTexCoord;
out vec4 fragColor;

uniform mat4 mvp;

void main() {
    fragTexCoord = vertexTexCoord;
    fragColor = vertexColor;
    gl_Position = mvp * vec4(vertexPosition, 1.0);
}
`

HEX_TRUCHET_FRAGMENT_SHADER :: `
#version 330

in vec2 fragTexCoord;
in vec4 fragColor;

out vec4 finalColor;

uniform sampler2D texture0;
uniform float time;
uniform vec2 resolution;

// Hexagonal Truchet pattern functions
float heightMap(in vec2 p) { 
    p *= 3.;
    
    // Hexagonal coordinates
    vec2 h = vec2(p.x + p.y*.57735, p.y*1.1547);
    
    // Closest hexagon center
    vec2 fh = floor(h);
    vec2 f = h - fh; h = fh;
    float c = fract((h.x + h.y)/3.);
    h =  c<.666 ?   c<.333 ?  h  :  h + 1.  :  h  + step(f.yx, f); 

    p -= vec2(h.x - h.y*.5, h.y*.8660254);
    
    // Rotate random hexagons
    c = fract(cos(dot(h, vec2(41, 289)))*43758.5453);
    p -= p*step(c, .5)*2.;
    
    // Minimum squared distance to neighbors
    p -= vec2(-1, 0);
    c = dot(p, p);
    p -= vec2(1.5, .8660254);
    c = min(c, dot(p, p));
    p -= vec2(0, -1.73205);
    c = min(c, dot(p, p));
    
    return sqrt(c);
}

// Raymarching functions
float map(vec3 p) {
    float c = heightMap(p.xy);
    c = cos(c*6.2831589) + cos(c*6.2831589*2.);
    c = (clamp(c*.6 +.5, 0., 1.));
    return 1. - p.z - c*.025;
}

vec3 getNormal(vec3 p, inout float edge, inout float crv) { 
    vec2 e = vec2(.01, 0);
    float d1 = map(p + e.xyy), d2 = map(p - e.xyy);
    float d3 = map(p + e.yxy), d4 = map(p - e.yxy);
    float d5 = map(p + e.yyx), d6 = map(p - e.yyx);
    float d = map(p)*2.;
    
    edge = abs(d1 + d2 - d) + abs(d3 + d4 - d) + abs(d5 + d6 - d);
    edge = smoothstep(0., 1., sqrt(edge/e.x*2.));
    crv = clamp((d1 + d2 + d3 + d4 + d5 + d6 - d*3.)*32. + .6, 0., 1.);
    
    e = vec2(.0025, 0);
    d1 = map(p + e.xyy), d2 = map(p - e.xyy);
    d3 = map(p + e.yxy), d4 = map(p - e.yxy);
    d5 = map(p + e.yyx), d6 = map(p - e.yyx); 
    
    return normalize(vec3(d1 - d2, d3 - d4, d5 - d6));
}

float calculateAO(in vec3 p, in vec3 n) {
    float sca = 2., occ = 0.;
    for(float i=0.; i<5.; i++) {
        float hr = .01 + i*.5/4.;        
        float dd = map(n * hr + p);
        occ += (hr - dd)*sca;
        sca *= 0.7;
    }
    return clamp(1.0 - occ, 0., 1.);    
}

// Noise functions
float n3D(vec3 p) {
    const vec3 s = vec3(7, 157, 113);
    vec3 ip = floor(p); p -= ip; 
    vec4 h = vec4(0., s.yz, s.y + s.z) + dot(ip, s);
    p = p*p*(3. - 2.*p);
    h = mix(fract(sin(mod(h, 6.2831589))*43758.5453), 
            fract(sin(mod(h + s.x, 6.2831589))*43758.5453), p.x);
    h.xy = mix(h.xz, h.yw, p.y);
    return mix(h.x, h.y, p.z);
}

// Enhanced spectral color function with more variations
vec3 spectralColor(float t) {
    // Much slower color cycle
    t *= 0.01;  // Even slower color cycle
    
    // Create a rich spectral color palette
    vec3 c1 = vec3(0.5, 0.8, 1.0);   // Light blue
    vec3 c2 = vec3(0.8, 0.5, 1.0);   // Purple
    vec3 c3 = vec3(1.0, 0.5, 0.8);   // Pink
    vec3 c4 = vec3(1.0, 0.8, 0.5);   // Light orange
    vec3 c5 = vec3(0.5, 1.0, 0.8);   // Mint
    vec3 c6 = vec3(0.8, 1.0, 0.5);   // Lime
    vec3 c7 = vec3(0.5, 0.5, 1.0);   // Royal blue
    vec3 c8 = vec3(1.0, 0.5, 0.5);   // Coral
    
    // Smooth transitions between colors
    float p = fract(t);
    if (p < 0.125) {
        return mix(c1, c2, p * 8.0);
    } else if (p < 0.25) {
        return mix(c2, c3, (p - 0.125) * 8.0);
    } else if (p < 0.375) {
        return mix(c3, c4, (p - 0.25) * 8.0);
    } else if (p < 0.5) {
        return mix(c4, c5, (p - 0.375) * 8.0);
    } else if (p < 0.625) {
        return mix(c5, c6, (p - 0.5) * 8.0);
    } else if (p < 0.75) {
        return mix(c6, c7, (p - 0.625) * 8.0);
    } else if (p < 0.875) {
        return mix(c7, c8, (p - 0.75) * 8.0);
    } else {
        return mix(c8, c1, (p - 0.875) * 8.0);
    }
}

vec3 envMap(vec3 rd, vec3 sn) {
    vec3 sRd = rd;
    rd.xy -= time*.01;  // Much slower rotation
    rd *= 3.;
    float c = n3D(rd)*.57 + n3D(rd*2.)*.28 + n3D(rd*4.)*.15;
    c = smoothstep(.4, 1., c);
    vec3 col = spectralColor(c + time * 0.01);  // Use spectral colors with much slower time
    return mix(col, col.yzx, sRd*.25+.25); 
}

void main() {
    vec4 texColor = texture(texture0, fragTexCoord);
    
    // Only apply effect to non-transparent pixels
    if(texColor.a > 0.0) {
        vec2 fragCoord = fragTexCoord * resolution;
        
        // Unit directional ray
        vec3 rd = normalize(vec3(2.*fragCoord - resolution.xy, resolution.y));
        
        float tm = time/32.;  // Much slower overall animation
        vec2 a = sin(vec2(1.570796, 0) + sin(tm/64.)*.3);  // Much slower rotation
        rd.xy = mat2(a, -a.y, a.x)*rd.xy;
        
        // Ray origin
        vec3 ro = vec3(tm, cos(tm/64.), 0.);  // Much slower movement
        
        // Light position
        vec3 lp = ro + vec3(cos(tm/32.)*.5, sin(tm/32.)*.5, -.5);  // Much slower light movement
        
        // Raymarching
        float d, t=0.;
        for(int j=0;j<32;j++) {
            d = map(ro + rd*t);
            t += d*.7;
            if(d<0.001) break;
        }
        
        float edge, crv;
        vec3 sp = ro + rd*t;
        vec3 sn = getNormal(sp, edge, crv);
        vec3 ld = lp - sp;
        
        // Coloring
        float c = heightMap(sp.xy);
        vec3 fold = cos(vec3(1, 2, 4)*c*6.2831589);
        float c2 = heightMap((sp.xy + sp.z*.025)*6.);
        c2 = cos(c2*6.2831589*3.);
        c2 = (clamp(c2 +.5, 0., 1.)); 
        
        vec3 oC = vec3(1);
        if(fold.x>0.) oC = spectralColor(c2 + time * 0.01) * 0.8;  // Use spectral colors with much slower time
        if(fold.x<0.05 && (fold.y)<0.) oC = spectralColor(c2 + time * 0.01 + 0.3) * 0.6;  // Different spectral phase
        else if(fold.x<0.) oC = spectralColor(c2 + time * 0.01 + 0.6) * 0.7;  // Another spectral phase
        
        // Lighting
        float lDist = max(length(ld), 0.001);
        float atten = 1./(1. + lDist*.125);
        ld /= lDist;
        float diff = max(dot(ld, sn), 0.);
        float spec = pow(max(dot(reflect(-ld, sn), -rd), 0.0), 16.);
        float fre = pow(clamp(dot(sn, rd) + 1., .0, 1.), 3.);
        
        crv = crv*.9 + .1;
        float ao = calculateAO(sp, sn);
        
        // Combine lighting
        vec3 col = oC*(diff + .5) + vec3(1., .7, .4)*spec*2. + vec3(.4, .7, 1)*fre;
        col += (oC*.5+.5)*envMap(reflect(rd, sn), sn)*6.;
        col *= 1. - edge*.85;
        col *= (atten*crv*ao);
        
        // Blend with original texture
        vec3 effectColor = sqrt(clamp(col, 0., 1.));
        finalColor = mix(texColor, vec4(effectColor, 1.0) * texColor, 0.7) * fragColor;
    } else {
        finalColor = texColor * fragColor;
    }
}
`

SINE_WAVE_VERTEX_SHADER :: `
#version 330

in vec3 vertexPosition;
in vec2 vertexTexCoord;
in vec4 vertexColor;

out vec2 fragTexCoord;
out vec4 fragColor;

uniform mat4 mvp;

void main() {
    fragTexCoord = vertexTexCoord;
    fragColor = vertexColor;
    gl_Position = mvp * vec4(vertexPosition, 1.0);
}
`

SINE_WAVE_FRAGMENT_SHADER :: `
#version 330

in vec2 fragTexCoord;
in vec4 fragColor;

out vec4 finalColor;

uniform sampler2D texture0;
uniform float time;
uniform vec2 resolution;

// Wave animation parameters as uniforms for dynamic control
uniform float wave_speed = 0.3;
uniform float wave_amplitude = 0.15;
uniform float wave_frequency = 3.0;
uniform float wave_smoothness = 0.3;

void main() {
    vec4 texColor = texture(texture0, fragTexCoord);
    
    // Only apply effect to non-transparent pixels
    if(texColor.a > 0.0) {
        // Calculate wave offset based on position and time
        float waveOffset = sin(fragTexCoord.x * wave_frequency + time * wave_speed) * 
                         cos(fragTexCoord.y * wave_frequency * 0.5 + time * wave_speed * 0.7) * 
                         wave_amplitude;
        
        // Apply wave distortion
        vec2 waveUV = fragTexCoord;
        waveUV.y += waveOffset;
        waveUV.x += waveOffset * 0.5; // Add horizontal movement
        
        // Sample texture with wave offset
        vec4 waveColor = texture(texture0, waveUV);
        
        // Add color variation based on wave position
        vec3 tintColor = vec3(1.0 + sin(time) * 0.2, 
                             1.0 + cos(time * 0.7) * 0.2, 
                             1.0 + sin(time * 0.5) * 0.2);
        
        // Create stronger blend
        float blendFactor = smoothstep(0.0, wave_smoothness, abs(waveOffset));
        finalColor = mix(texColor, waveColor * vec4(tintColor, 1.0), blendFactor) * fragColor;
    } else {
        finalColor = texColor * fragColor;
    }
}
`
