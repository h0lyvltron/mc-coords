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

// Raymarching parameters
const int MAX_STEPS = 100;
const float MAX_DIST = 20.0;
const float SURF_DIST = 0.001;

// Noise function for shimmer effect
float noise(vec2 p) {
    return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

// Smooth noise
float smoothNoise(vec2 p) {
    vec2 ip = floor(p);
    vec2 u = fract(p);
    u = u * u * (3.0 - 2.0 * u);
    
    float a = noise(ip);
    float b = noise(ip + vec2(1.0, 0.0));
    float c = noise(ip + vec2(0.0, 1.0));
    float d = noise(ip + vec2(1.0, 1.0));
    
    return mix(a, b, u.x) + (c - a) * u.y * (1.0 - u.x) + (d - b) * u.x * u.y;
}

// Shimmer effect
float shimmer(vec2 uv, float time) {
    float shimmer = 0.0;
    float scale = 1.0;
    float speed = 1.0;
    
    for(int i = 0; i < 3; i++) {
        shimmer += smoothNoise(uv * scale + time * speed) * 0.5;
        scale *= 2.0;
        speed *= 1.5;
    }
    
    return shimmer * 0.5 + 0.5;
}

// Distance function for raymarching
float sdBox(vec2 p, vec2 b) {
    vec2 d = abs(p) - b;
    return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
}

// Raymarching function
float raymarch(vec2 ro, vec2 rd) {
    float d = 0.0;
    
    for(int i = 0; i < MAX_STEPS; i++) {
        vec2 p = ro + rd * d;
        float ds = sdBox(p, vec2(0.5));
        d += ds;
        if(ds < SURF_DIST || d > MAX_DIST) break;
    }
    
    return d;
}

void main() {
    vec2 uv = fragTexCoord;
    vec4 texColor = texture(texture0, uv);
    
    // Calculate shimmer effect
    float shimmer = shimmer(uv, time);
    
    // Add subtle color shift based on shimmer
    vec3 colorShift = vec3(
        sin(time * 0.5) * 0.1,
        cos(time * 0.3) * 0.1,
        sin(time * 0.7) * 0.1
    );
    
    // Apply shimmer and color shift
    vec3 finalColorRGB = texColor.rgb * (1.0 + shimmer * 0.2) + colorShift * shimmer;
    
    // Add subtle pulsing
    float pulse = sin(time * 2.0) * 0.05 + 0.95;
    finalColorRGB *= pulse;
    
    // Apply tint color
    finalColor = vec4(finalColorRGB, texColor.a) * tintColor;
}
` 