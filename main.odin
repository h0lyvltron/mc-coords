package main

import "core:fmt"
import "core:mem"
import "core:strings"
import "core:strconv"
import "core:os"
import "core:math"
import rl "vendor:raylib"

// Define Dimension enum
Dimension :: enum {
    Overworld,
    Nether,
}

CoordinatePair :: struct {
    x, y: int,
    dimension: Dimension,
}

CoordinateState :: struct {
    source: CoordinatePair,
    converted: CoordinatePair,
    needs_conversion: bool,
}

// Initialize a new coordinate state with default values
init_coordinate_state :: proc() -> CoordinateState {
    return CoordinateState {
        source = CoordinatePair{0, 0, Dimension.Overworld},
        converted = CoordinatePair{0, 0, Dimension.Nether},
        needs_conversion = true,
    }
}

// Update source coordinates and mark for conversion if changed
update_coordinates :: proc(state: ^CoordinateState, x: int, y: int) {
    if x != state.source.x || y != state.source.y {
        state.source.x = x
        state.source.y = y
        state.needs_conversion = true
    }
}

// Update dimension and mark for conversion if changed
update_dimension :: proc(state: ^CoordinateState, dimension: Dimension) {
    if dimension != state.source.dimension {
        state.source.dimension = dimension
        state.needs_conversion = true
    }
}

// Convert coordinates between Overworld and Nether
convert_coordinate_value :: proc(x: int, dimension: Dimension) -> int {
    switch dimension {
    case .Overworld:
        return x / 8
    case .Nether:
        return x * 8
    }
    return x
}

// Convert coordinates from one dimension to another
convert_between_dimensions :: proc(x: int, from: Dimension, to: Dimension) -> int {
    if from == to {
        return x
    }
    return convert_coordinate_value(x, from)
}

// Get converted coordinates, performing conversion if needed
get_converted_coordinates :: proc(state: ^CoordinateState) -> CoordinatePair {
    if state.needs_conversion {
        target_dimension := state.source.dimension == Dimension.Overworld ? Dimension.Nether : Dimension.Overworld
        state.converted = CoordinatePair {
            x = convert_between_dimensions(state.source.x, state.source.dimension, target_dimension),
            y = convert_between_dimensions(state.source.y, state.source.dimension, target_dimension),
            dimension = target_dimension,
        }
        state.needs_conversion = false
    }
    return state.converted
}

// Convert coordinates to string representation
coordinates_to_string :: proc(pair: CoordinatePair) -> string {
    return fmt.tprintf("X: %d, Y: %d (%v)", pair.x, pair.y, pair.dimension)
}

// Key input configuration
KeyConfig :: struct {
    initial_delay: f32,  // Time before first repeat
    repeat_rate: f32,    // Time between repeats
}

KeyState :: struct {
    is_held: bool,
    held_time: f32,
    last_repeat_time: f32,
    config: KeyConfig,
}

DEFAULT_KEY_CONFIG := KeyConfig{
    initial_delay = 0.5,  // 500ms initial delay
    repeat_rate = 0.05,   // 50ms between repeats
}

// Background shader code
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

// Update BackgroundImage struct to include shader
BackgroundImage :: struct {
    texture: rl.Texture2D,
    source_rect: rl.Rectangle,
    dest_rect: rl.Rectangle,
    shader: rl.Shader,
    time_loc: i32,        // Uniform location for time
    resolution_loc: i32,  // Uniform location for resolution
}

// Update load_background_image to include shader initialization
load_background_image :: proc(path: string, window_width, window_height: i32) -> (BackgroundImage, bool) {
    image := rl.LoadImage(strings.clone_to_cstring(path))
    if image.data == nil {
        fmt.eprintln("Failed to load image:", path)
        return BackgroundImage{}, false
    }
    defer rl.UnloadImage(image)
    
    // Calculate optimal crop region
    crop := calculate_image_crop(image.width, image.height, window_width, window_height)
    
    // Create texture from image
    texture := rl.LoadTextureFromImage(image)
    if texture.id == 0 {
        fmt.eprintln("Failed to create texture from image:", path)
        return BackgroundImage{}, false
    }
    
    // Load shader
    shader := rl.LoadShaderFromMemory(BACKGROUND_VERTEX_SHADER, BACKGROUND_FRAGMENT_SHADER)
    if shader.id == 0 {
        fmt.eprintln("Failed to load background shader")
        rl.UnloadTexture(texture)
        return BackgroundImage{}, false
    }
    
    // Get uniform locations
    time_loc := rl.GetShaderLocation(shader, "time")
    resolution_loc := rl.GetShaderLocation(shader, "resolution")
    
    // Set initial resolution uniform
    resolution := [2]f32{f32(window_width), f32(window_height)}
    rl.SetShaderValue(shader, resolution_loc, &resolution, .VEC2)
    
    return BackgroundImage{
        texture = texture,
        source_rect = crop,
        dest_rect = rl.Rectangle{0, 0, f32(window_width), f32(window_height)},
        shader = shader,
        time_loc = time_loc,
        resolution_loc = resolution_loc,
    }, true
}

// Update AppState to include background image
AppState :: struct {
    window_width: i32,
    window_height: i32,
    font: rl.Font,
    font_size: f32,
    input_buffers: [2][10]u8,
    active_input: int,
    coordinates: CoordinateState,
    help_visible: bool,
    should_clear: bool,
    key_states: map[rl.KeyboardKey]KeyState,
    background: BackgroundImage,
}

WindowDefaultFlags :: struct {
    title: string,
    width: i32,
    height: i32,
    pos_x: i32,
    pos_y: i32,
}

FontSettings :: struct {
    font: rl.Font,
    size: f32,
    spacing: f32,
    title_size: f32,
}

Layout :: struct {
    margin: f32,
    spacing: f32,
    section_spacing: f32,
    input_box: struct {
        width: f32,
        height: f32,
        text_padding: f32,
    },
    dimension_button: struct {
        width: f32,
        height: f32,
        text_padding: f32,
        gap: f32,
    },
}

DEFAULT_LAYOUT := Layout {
    margin = 20,
    spacing = 35,
    section_spacing = 45,
    input_box = {
        width = 200,
        height = 32,
        text_padding = 10,
    },
    dimension_button = {
        width = 160,
        height = 40,
        text_padding = 10,
        gap = 10,
    },
}

Position :: struct {
    x, y: f32,
}

UIElement :: struct {
    rect: rl.Rectangle,
    text_pos: Position,
    label_pos: Position,
}

DEFAULT_WINDOW_FLAGS := WindowDefaultFlags {
    title = "Minecraft Location Manager",
    width = 480,
    height = 640,
    pos_x = 100,
    pos_y = 100,
}

DEFAULT_FONT_SETTINGS := FontSettings {
    font = rl.GetFontDefault(),
    size = 20.0,
    spacing = 0.5,
    title_size = 24.0,
}

load_font_with_fallback :: proc() -> rl.Font {
    // Try common paths for Minecraft font
    minecraft_paths := []string{
        "assets/fonts/MinecraftTen-VGORe.ttf",
        "./assets/fonts/MinecraftTen-VGORe.ttf",
        "C:/Windows/Fonts/MinecraftTen-VGORe.ttf",
    }

    // Check user fonts directory
    local_app_data := os.get_env("LOCALAPPDATA", context.temp_allocator)
    if local_app_data != "" {
        user_font_path := fmt.tprintf("%s/Microsoft/Windows/Fonts/MinecraftTen-VGORe.ttf", local_app_data)
        if os.exists(user_font_path) {
            font := rl.LoadFont(strings.clone_to_cstring(user_font_path))
            if font.texture.id != 0 && rl.GetGlyphIndex(font, 'A') != 0 {
                fmt.println("Loaded Minecraft font from:", user_font_path)
                return font
            }
            rl.UnloadFont(font)
        }
    }

    // Try to load Minecraft font from various paths
    for path in minecraft_paths {
        if os.exists(path) {
            font := rl.LoadFont(strings.clone_to_cstring(path))
            if font.texture.id != 0 && rl.GetGlyphIndex(font, 'A') != 0 {
                fmt.println("Loaded Minecraft font from:", path)
                return font
            }
            rl.UnloadFont(font)
        }
    }

    // Fallback to Consolas
    consolas := rl.LoadFont(strings.clone_to_cstring("C:/Windows/Fonts/consola.ttf"))
    if consolas.texture.id != 0 && rl.GetGlyphIndex(consolas, 'A') != 0 {
        fmt.println("Using Consolas as fallback font")
        return consolas
    }

    // Final fallback to default raylib font
    fmt.println("Using default raylib font")
    return rl.GetFontDefault()
}

make_input_box :: proc(layout: Layout, pos: Position, label: string, font: rl.Font, font_size: f32, font_spacing: f32) -> UIElement {
    label_width := rl.MeasureTextEx(font, strings.clone_to_cstring(label), font_size, font_spacing).x
    return UIElement{
        rect = rl.Rectangle{
            pos.x + label_width + layout.margin,
            pos.y,
            layout.input_box.width,
            layout.input_box.height,
        },
        text_pos = Position{
            pos.x + label_width + layout.margin + layout.input_box.text_padding,
            pos.y + layout.input_box.text_padding,
        },
        label_pos = Position{
            pos.x,
            pos.y + layout.input_box.text_padding,
        },
    }
}

make_dimension_buttons :: proc(layout: Layout, pos: Position) -> (overworld: UIElement, nether: UIElement) {
    overworld = UIElement{
        rect = rl.Rectangle{
            pos.x,
            pos.y,
            layout.dimension_button.width,
            layout.dimension_button.height,
        },
        text_pos = Position{
            pos.x + layout.dimension_button.text_padding + 15,
            pos.y + layout.dimension_button.text_padding,
        },
    }

    nether = UIElement{
        rect = rl.Rectangle{
            pos.x + layout.dimension_button.width + layout.dimension_button.gap,
            pos.y,
            layout.dimension_button.width,
            layout.dimension_button.height,
        },
        text_pos = Position{
            pos.x + layout.dimension_button.width + layout.dimension_button.gap + layout.dimension_button.text_padding + 25,
            pos.y + layout.dimension_button.text_padding,
        },
    }

    return
}

// Initialize key state
init_key_state :: proc(config: KeyConfig) -> KeyState {
    return KeyState{
        is_held = false,
        held_time = 0,
        last_repeat_time = 0,
        config = config,
    }
}

// Update key state and check if it should trigger
update_key_state :: proc(state: ^KeyState, is_down: bool, current_time: f32) -> bool {
    if is_down {
        if !state.is_held {
            // Key was just pressed
            state.is_held = true
            state.held_time = 0
            state.last_repeat_time = current_time
            return true
        } else {
            // Key is being held
            state.held_time += rl.GetFrameTime()
            if state.held_time >= state.config.initial_delay {
                time_since_last := current_time - state.last_repeat_time
                if time_since_last >= state.config.repeat_rate {
                    state.last_repeat_time = current_time
                    return true
                }
            }
        }
    } else {
        // Key was released
        state.is_held = false
        state.held_time = 0
    }
    return false
}

// Initialize app with key states
init_app :: proc() -> AppState {
    state := AppState {
        window_width = DEFAULT_WINDOW_FLAGS.width,
        window_height = DEFAULT_WINDOW_FLAGS.height,
        font = load_font_with_fallback(),
        font_size = DEFAULT_FONT_SETTINGS.size,
        input_buffers = {0, 0},
        active_input = 0,
        coordinates = init_coordinate_state(),
        help_visible = false,
        should_clear = false,
        key_states = make(map[rl.KeyboardKey]KeyState),
    }
    
    // Initialize key states
    state.key_states[.BACKSPACE] = init_key_state(DEFAULT_KEY_CONFIG)
    state.key_states[.LEFT] = init_key_state(DEFAULT_KEY_CONFIG)
    state.key_states[.RIGHT] = init_key_state(DEFAULT_KEY_CONFIG)
    state.key_states[.TAB] = init_key_state(KeyConfig{initial_delay = 0.5, repeat_rate = 0.2})
    
    // Load background image
    bg, ok := load_background_image("assets/tree-house.png", state.window_width, state.window_height)
    if ok {
        state.background = bg
    } else {
        fmt.eprintln("Failed to load background image")
    }
    
    return state
}

// Update coordinates based on input
update_input_coordinates :: proc(state: ^AppState) {
    // Convert input buffers to strings
    x_str := string_from_bytes(state.input_buffers[0][:])
    z_str := string_from_bytes(state.input_buffers[1][:])
    
    // Convert strings to integers
    x, x_ok := strconv.parse_int(x_str)
    z, z_ok := strconv.parse_int(z_str)
    
    // Update coordinates even if one is invalid (use 0 as default)
    state.coordinates.source.x = x_ok ? x : 0
    state.coordinates.source.y = z_ok ? z : 0
    state.coordinates.needs_conversion = true
}

// Handle key input with repeat
handle_key_input :: proc(state: ^AppState) {
    current_time := f32(rl.GetTime())
    
    // Handle backspace with repeat
    if state.active_input >= 0 && state.active_input < 2 {
        backspace_state := &state.key_states[.BACKSPACE]
        if update_key_state(backspace_state, rl.IsKeyDown(.BACKSPACE), current_time) {
            buffer := &state.input_buffers[state.active_input]
            if buffer[0] != 0 {
                // Find the end of the string
                i: int = 0
                for i < len(buffer) && buffer[i] != 0 {
                    i += 1
                }
                if i > 0 {
                    buffer[i-1] = 0
                    update_input_coordinates(state)
                }
            }
        }
    }
    
    // Handle arrow keys for dimension toggle
    if state.active_input == 2 {
        left_state := &state.key_states[.LEFT]
        right_state := &state.key_states[.RIGHT]
        
        if update_key_state(left_state, rl.IsKeyDown(.LEFT), current_time) ||
           update_key_state(right_state, rl.IsKeyDown(.RIGHT), current_time) {
            state.coordinates.source.dimension = state.coordinates.source.dimension == Dimension.Overworld ? Dimension.Nether : Dimension.Overworld
            state.coordinates.needs_conversion = true
        }
    }
    
    // Handle tab navigation with repeat
    tab_state := &state.key_states[.TAB]
    if update_key_state(tab_state, rl.IsKeyDown(.TAB), current_time) {
        // Update coordinates before changing focus
        update_input_coordinates(state)
        
        if rl.IsKeyDown(.LEFT_SHIFT) || rl.IsKeyDown(.RIGHT_SHIFT) {
            // Shift+Tab: Move backwards
            if state.active_input > 0 {
                state.active_input -= 1
            } else {
                state.active_input = 2
            }
        } else {
            // Tab: Move forwards
            if state.active_input < 2 {
                state.active_input += 1
            } else {
                state.active_input = 0
            }
        }
        // Set should_clear when focusing input field
        state.should_clear = state.active_input < 2
    }
}

// Update input handling procedures to use new key system
handle_input :: proc(state: ^AppState) {
    // Handle repeatable keys
    handle_key_input(state)
    
    // Handle one-shot keys (no repeat needed)
    if rl.IsKeyPressed(.ESCAPE) {
        update_input_coordinates(state)
        state.active_input = -1
    }
    
    if rl.IsKeyPressed(.ENTER) {
        update_input_coordinates(state)
    }
    
    if rl.IsKeyPressed(.SPACE) && state.active_input == 2 {
        state.coordinates.source.dimension = state.coordinates.source.dimension == Dimension.Overworld ? Dimension.Nether : Dimension.Overworld
        state.coordinates.needs_conversion = true
    }
    
    // Handle numeric input and minus sign
    if state.active_input >= 0 && state.active_input < 2 {
        buffer := &state.input_buffers[state.active_input]
        key := rl.GetCharPressed()
        
        if key != 0 {
            // If this is a valid input character (number or minus)
            if (key >= '0' && key <= '9') || (key == '-') {
                // Find current length of buffer
                i: int = 0
                for i < len(buffer) && buffer[i] != 0 {
                    i += 1
                }
                
                if i < len(buffer) - 1 { // Leave room for null terminator
                    // Clear buffer on first character after focusing if needed
                    if state.should_clear {
                        for j := 0; j < len(buffer); j += 1 {
                            buffer[j] = 0
                        }
                        i = 0
                        state.should_clear = false
                    }
                    
                    // Only allow minus at start
                    if key == '-' && i > 0 do return
                    
                    buffer[i] = u8(key)
                    buffer[i+1] = 0
                    update_input_coordinates(state)
                }
            }
        }
    }
}

// Convert bytes to string
string_from_bytes :: proc(bytes: []u8) -> string {
    i: int = 0
    for i < len(bytes) && bytes[i] != 0 {
        i += 1
    }
    return string(bytes[:i])
}

// Helper function to draw text with outline
draw_outlined_text :: proc(font: rl.Font, text: cstring, position: rl.Vector2, font_size: f32, spacing: f32, thickness: f32 = 1) {
    // Draw outline (white)
    offsets := [][2]f32{
        {-thickness, -thickness},
        {-thickness, 0},
        {-thickness, thickness},
        {0, -thickness},
        {0, thickness},
        {thickness, -thickness},
        {thickness, 0},
        {thickness, thickness},
    }
    
    for offset in offsets {
        pos := rl.Vector2{position.x + offset[0], position.y + offset[1]}
        rl.DrawTextEx(font, text, pos, font_size, spacing, rl.WHITE)
    }
    
    // Draw main text (black)
    rl.DrawTextEx(font, text, position, font_size, spacing, rl.BLACK)
}

// Calculate the optimal crop region for fitting an image while maintaining aspect ratio
calculate_image_crop :: proc(image_width, image_height, target_width, target_height: i32) -> rl.Rectangle {
    source_aspect := f32(image_width) / f32(image_height)
    target_aspect := f32(target_width) / f32(target_height)
    
    // Initialize crop rectangle
    crop := rl.Rectangle{}
    
    if source_aspect > target_aspect {
        // Image is wider than target - crop width
        crop.height = f32(image_height)
        crop.width = crop.height * target_aspect
        // Center horizontally
        crop.x = f32(image_width - i32(crop.width)) / 2
        crop.y = 0
    } else {
        // Image is taller than target - crop height
        crop.width = f32(image_width)
        crop.height = crop.width / target_aspect
        // Center vertically
        crop.x = 0
        crop.y = f32(image_height - i32(crop.height)) / 2
    }
    
    return crop
}

// Update main drawing code to use shader
main :: proc() {
    // Initialize window
    rl.InitWindow(DEFAULT_WINDOW_FLAGS.width, DEFAULT_WINDOW_FLAGS.height, strings.clone_to_cstring(DEFAULT_WINDOW_FLAGS.title))
    defer rl.CloseWindow()
    
    // Set target FPS
    rl.SetTargetFPS(60)
    
    // Initialize app state
    state := init_app()
    defer {
        rl.UnloadFont(state.font)
        rl.UnloadTexture(state.background.texture)
        rl.UnloadShader(state.background.shader)
        delete(state.key_states)
    }
    
    // Initialize layout
    layout := DEFAULT_LAYOUT
    
    // Initialize UI elements
    x_input := make_input_box(layout, Position{20, 140}, "X:", state.font, state.font_size, 1)
    z_input := make_input_box(layout, Position{20, 140 + layout.section_spacing}, "Z:", state.font, state.font_size, 1)
    overworld_button, nether_button := make_dimension_buttons(layout, Position{20, 140 + 2*layout.section_spacing + layout.spacing})

    // Main loop
    for !rl.WindowShouldClose() {
        // Handle input
        handle_input(&state)
        
        // Handle mouse input for dimension toggle and input boxes
        if rl.IsMouseButtonPressed(.LEFT) {
            mouse_pos := rl.GetMousePosition()
            if rl.CheckCollisionPointRec(mouse_pos, x_input.rect) {
                update_input_coordinates(&state)
                state.active_input = 0
                state.should_clear = true
            } else if rl.CheckCollisionPointRec(mouse_pos, z_input.rect) {
                update_input_coordinates(&state)
                state.active_input = 1
                state.should_clear = true
            } else if rl.CheckCollisionPointRec(mouse_pos, overworld_button.rect) {
                update_input_coordinates(&state)
                state.active_input = 2
                state.coordinates.source.dimension = .Overworld
                state.coordinates.needs_conversion = true
            } else if rl.CheckCollisionPointRec(mouse_pos, nether_button.rect) {
                update_input_coordinates(&state)
                state.active_input = 2
                state.coordinates.source.dimension = .Nether
                state.coordinates.needs_conversion = true
            } else {
                update_input_coordinates(&state)
                state.active_input = -1
                state.should_clear = false
            }
        }

        rl.BeginDrawing()
        defer rl.EndDrawing()

        rl.ClearBackground(rl.BLACK)
        
        // Update shader uniforms
        time := f32(rl.GetTime())
        rl.SetShaderValue(state.background.shader, state.background.time_loc, &time, .FLOAT)
        
        // Begin shader mode and draw background
        rl.BeginShaderMode(state.background.shader)
        rl.DrawTexturePro(
            state.background.texture,
            state.background.source_rect,
            state.background.dest_rect,
            rl.Vector2{0, 0},
            0,
            rl.WHITE,
        )
        rl.EndShaderMode()
        
        // Draw title with outline
        title_width := rl.MeasureTextEx(state.font, strings.clone_to_cstring(DEFAULT_WINDOW_FLAGS.title), state.font_size * 1.5, 1).x
        title_x := f32(state.window_width/2) - title_width/2
        draw_outlined_text(state.font, strings.clone_to_cstring(DEFAULT_WINDOW_FLAGS.title), rl.Vector2{title_x, 30}, state.font_size * 1.5, 1)
        
        // Draw input coordinates section
        draw_outlined_text(state.font, "INPUT COORDINATES:", rl.Vector2{20, 95}, state.font_size, 1)
        
        // Draw X input
        draw_outlined_text(state.font, "X:", rl.Vector2{x_input.label_pos.x, x_input.label_pos.y}, state.font_size, 1)
        x_box_color := rl.ColorAlpha(state.active_input == 0 ? rl.BLUE : rl.DARKGRAY, state.active_input == 0 ? 0.7 : 0.5)
        rl.DrawRectangleRec(x_input.rect, x_box_color)
        draw_outlined_text(state.font, strings.clone_to_cstring(string(state.input_buffers[0][:])), rl.Vector2{x_input.text_pos.x, x_input.text_pos.y}, state.font_size, 1)
        
        // Draw Z input
        draw_outlined_text(state.font, "Z:", rl.Vector2{z_input.label_pos.x, z_input.label_pos.y}, state.font_size, 1)
        z_box_color := rl.ColorAlpha(state.active_input == 1 ? rl.BLUE : rl.DARKGRAY, state.active_input == 1 ? 0.7 : 0.5)
        rl.DrawRectangleRec(z_input.rect, z_box_color)
        draw_outlined_text(state.font, strings.clone_to_cstring(string(state.input_buffers[1][:])), rl.Vector2{z_input.text_pos.x, z_input.text_pos.y}, state.font_size, 1)
        
        // Draw dimension selection
        draw_outlined_text(state.font, "STARTING DIMENSION:", rl.Vector2{20, overworld_button.rect.y - layout.spacing}, state.font_size, 1)
        
        // Draw Overworld button
        overworld_color := rl.ColorAlpha(
            state.coordinates.source.dimension == Dimension.Overworld ? rl.BLUE : rl.DARKGRAY,
            0.7,
        )
        if state.active_input == 2 && state.coordinates.source.dimension == Dimension.Overworld {
            overworld_color = rl.ColorAlpha(rl.SKYBLUE, 0.7)
        }
        rl.DrawRectangleRec(overworld_button.rect, overworld_color)
        draw_outlined_text(state.font, "OVERWORLD", rl.Vector2{overworld_button.text_pos.x, overworld_button.text_pos.y}, state.font_size, 1)
        
        // Draw Nether button
        nether_color := rl.ColorAlpha(
            state.coordinates.source.dimension == Dimension.Nether ? rl.BLUE : rl.DARKGRAY,
            0.7,
        )
        if state.active_input == 2 && state.coordinates.source.dimension == Dimension.Nether {
            nether_color = rl.ColorAlpha(rl.SKYBLUE, 0.7)
        }
        rl.DrawRectangleRec(nether_button.rect, nether_color)
        draw_outlined_text(state.font, "NETHER", rl.Vector2{nether_button.text_pos.x, nether_button.text_pos.y}, state.font_size, 1)
        
        // Draw converted coordinates
        converted := get_converted_coordinates(&state.coordinates)
        converted_text := coordinates_to_string(converted)
        draw_outlined_text(
            state.font,
            strings.clone_to_cstring(converted_text),
            rl.Vector2{DEFAULT_LAYOUT.margin, f32(state.window_height/2) + 50},
            state.font_size,
            1,
        )
    }
}
