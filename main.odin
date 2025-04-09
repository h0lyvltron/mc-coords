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
    x, z: int,
    dimension: Dimension,
}

CoordinateState :: struct {
    source: CoordinatePair,
    converted: CoordinatePair,
    source_dimension: Dimension,
    needs_conversion: bool,
}

// Initialize a new coordinate state with default values
init_coordinate_state :: proc() -> CoordinateState {
    return CoordinateState {
        source = CoordinatePair{0, 0, Dimension.Overworld},
        converted = CoordinatePair{0, 0, Dimension.Nether},
        source_dimension = Dimension.Overworld,
        needs_conversion = true,
    }
}

// Update source coordinates and mark for conversion if changed
update_coordinates :: proc(state: ^CoordinateState, x: int, z: int) {
    if x != state.source.x || z != state.source.z {
        state.source.x = x
        state.source.z = z
        state.needs_conversion = true
    }
}

// Update dimension and mark for conversion if changed
update_dimension :: proc(state: ^CoordinateState, dimension: Dimension) {
    if dimension != state.source_dimension {
        state.source_dimension = dimension
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
    switch from {
    case .Overworld:
        return x / 8
    case .Nether:
        return x * 8
    }
    return x
}

// Get converted coordinates
get_converted_coordinates :: proc(coords: ^CoordinateState) -> (converted: bool) {
    if coords.needs_conversion {
        fmt.println("Conversion needed - Source:", coords.source.x, coords.source.z, coords.source_dimension)
        
        // Convert coordinates between dimensions
        target_dimension := coords.source_dimension == Dimension.Overworld ? Dimension.Nether : Dimension.Overworld
        converted_x := convert_between_dimensions(coords.source.x, coords.source_dimension, target_dimension)
        converted_z := convert_between_dimensions(coords.source.z, coords.source_dimension, target_dimension)
        
        // Update destination coordinates
        coords.converted.x = converted_x
        coords.converted.z = converted_z
        coords.converted.dimension = target_dimension
        
        fmt.println("Conversion complete - Converted:", coords.converted.x, coords.converted.z, coords.converted.dimension)
        
        // Conversion complete
        coords.needs_conversion = false
        converted = true
    }
    return
}

// Convert coordinates to string representation
coordinates_to_string :: proc(pair: CoordinatePair) -> string {
    return fmt.tprintf("X: %d, Z: %d (%v)", pair.x, pair.z, pair.dimension)
}

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

// Location management
Location :: struct {
    name: string,
    x: int,
    z: int,
    dimension: Dimension,
    description: string,
    tags: []string,
}

LocationDatabase :: struct {
    locations: [dynamic]Location,
    current_filter: string,
    selected_index: int,
}

// Settings management
Settings :: struct {
    theme: string,
    font_size: f32,
    auto_save: bool,
    default_dimension: Dimension,
}

// UI element types
UIElement_ID :: distinct int
UIElementState :: struct {
    bounds: rl.Rectangle,
    is_active: bool,
    is_visible: bool,
    is_hovered: bool,
}

Modal_State :: enum {
    None,
    SaveLocation,
    LoadLocation,
    Settings,
    Help,
}

// UI state management
UIState :: struct {
    elements: map[UIElement_ID]UIElementState,
    active_element: UIElement_ID,
    previous_element: UIElement_ID,
    modal_state: Modal_State,
}

// Update AppState to use new input system
AppState :: struct {
    window_width: i32,
    window_height: i32,
    font: rl.Font,
    font_size: f32,
    coordinates: CoordinateState,
    help_visible: bool,
    input: InputState,
    background: BackgroundImage,
    // Future enhancements
    locations: LocationDatabase,
    settings: Settings,
    ui_state: UIState,
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

WINDOW_DEFAULT_FLAGS := WindowDefaultFlags {
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

// Initialize app with input system
init_app :: proc() -> AppState {
    state := AppState {
        window_width = WINDOW_DEFAULT_FLAGS.width,
        window_height = WINDOW_DEFAULT_FLAGS.height,
        font = load_font_with_fallback(),
        font_size = DEFAULT_FONT_SETTINGS.size,
        coordinates = init_coordinate_state(),
        help_visible = false,
    }
    
    // Initialize input system
    init_input_state(&state.input)
    
    // Load background image
    bg, ok := load_background_image("assets/tree-house.png", state.window_width, state.window_height)
    if ok {
        state.background = bg
    } else {
        fmt.eprintln("Failed to load background image")
    }
    
    // Initialize future enhancement systems
    state.locations = LocationDatabase {
        locations = make([dynamic]Location),
        current_filter = "",
        selected_index = -1,
    }
    
    state.settings = Settings {
        theme = "default",
        font_size = DEFAULT_FONT_SETTINGS.size,
        auto_save = true,
        default_dimension = .Overworld,
    }
    
    state.ui_state = UIState {
        elements = make(map[UIElement_ID]UIElementState),
        active_element = -1,
        previous_element = -1,
        modal_state = .None,
    }
    
    return state
}

// Update main loop to handle dimension toggling
main :: proc() {
    // Initialize window
    rl.InitWindow(WINDOW_DEFAULT_FLAGS.width, WINDOW_DEFAULT_FLAGS.height, strings.clone_to_cstring(WINDOW_DEFAULT_FLAGS.title))
    defer rl.CloseWindow()

    // Set target FPS
    rl.SetTargetFPS(60)

    // Initialize app state
    state := init_app()
    defer {
        rl.UnloadFont(state.font)
        delete(state.input.key_states)
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
        update_input_state(&state.input)
        
        // Handle keyboard input for coordinate updates
        if state.input.active_input == .X || state.input.active_input == .Z {
            // Update on any key press for active input
            if rl.IsKeyPressed(.ENTER) || rl.IsKeyPressed(.TAB) || rl.IsKeyPressed(.BACKSPACE) || 
               (rl.IsKeyPressed(.ZERO) || rl.IsKeyPressed(.ONE) || rl.IsKeyPressed(.TWO) || 
                rl.IsKeyPressed(.THREE) || rl.IsKeyPressed(.FOUR) || rl.IsKeyPressed(.FIVE) || 
                rl.IsKeyPressed(.SIX) || rl.IsKeyPressed(.SEVEN) || rl.IsKeyPressed(.EIGHT) || 
                rl.IsKeyPressed(.NINE) || rl.IsKeyPressed(.MINUS)) {
                fmt.println("Updating coordinates from input")
                update_coordinates_from_input(&state.input, &state.coordinates)
            }
        }

        // Handle dimension toggle
        if state.input.needs_dimension_toggle {
            state.coordinates.source_dimension = state.coordinates.source_dimension == Dimension.Overworld ? Dimension.Nether : Dimension.Overworld
            state.coordinates.needs_conversion = true
            state.input.needs_dimension_toggle = false
        }

        // Handle mouse input
        if rl.IsMouseButtonPressed(.LEFT) {
            mouse_pos := rl.GetMousePosition()
            
            // Check if clicking on dimension buttons
            if rl.CheckCollisionPointRec(mouse_pos, overworld_button.rect) {
                state.input.active_input = .Dimension
                state.coordinates.source_dimension = Dimension.Overworld
                state.coordinates.needs_conversion = true
            } else if rl.CheckCollisionPointRec(mouse_pos, nether_button.rect) {
                state.input.active_input = .Dimension
                state.coordinates.source_dimension = Dimension.Nether
                state.coordinates.needs_conversion = true
            }
            
            // Check if clicking on input boxes
            if rl.CheckCollisionPointRec(mouse_pos, x_input.rect) {
                state.input.active_input = .X
                state.input.should_clear = true
            } else if rl.CheckCollisionPointRec(mouse_pos, z_input.rect) {
                state.input.active_input = .Z
                state.input.should_clear = true
            } else {
                state.input.active_input = .None
            }
        }

        // Ensure coordinate conversion happens
        if state.coordinates.needs_conversion {
            fmt.println("Attempting conversion")
            get_converted_coordinates(&state.coordinates)
        }

        rl.BeginDrawing()
        defer rl.EndDrawing()

        rl.ClearBackground(rl.BLACK)
        
        // Update shader uniforms and draw background
        time := f32(rl.GetTime())
        rl.SetShaderValue(state.background.shader, state.background.time_loc, &time, .FLOAT)
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
        title_width := rl.MeasureTextEx(state.font, strings.clone_to_cstring(WINDOW_DEFAULT_FLAGS.title), state.font_size * 1.5, 1).x
        title_x := f32(state.window_width/2) - title_width/2
        draw_outlined_text(state.font, strings.clone_to_cstring(WINDOW_DEFAULT_FLAGS.title), rl.Vector2{title_x, 30}, state.font_size * 1.5, 1)
        
        // Draw input coordinates section
        draw_outlined_text(state.font, "INPUT COORDINATES:", rl.Vector2{20, 95}, state.font_size, 1)
        
        // Draw X input
        draw_outlined_text(state.font, "X:", rl.Vector2{x_input.label_pos.x, x_input.label_pos.y}, state.font_size, 1)
        x_box_color := rl.ColorAlpha(state.input.active_input == .X ? rl.BLUE : rl.DARKGRAY, state.input.active_input == .X ? 0.7 : 0.5)
        rl.DrawRectangleRec(x_input.rect, x_box_color)
        draw_outlined_text(state.font, strings.clone_to_cstring(string(state.input.input_buffers[0][:])), rl.Vector2{x_input.text_pos.x, x_input.text_pos.y}, state.font_size, 1)
        
        // Draw Z input
        draw_outlined_text(state.font, "Z:", rl.Vector2{z_input.label_pos.x, z_input.label_pos.y}, state.font_size, 1)
        z_box_color := rl.ColorAlpha(state.input.active_input == .Z ? rl.BLUE : rl.DARKGRAY, state.input.active_input == .Z ? 0.7 : 0.5)
        rl.DrawRectangleRec(z_input.rect, z_box_color)
        draw_outlined_text(state.font, strings.clone_to_cstring(string(state.input.input_buffers[1][:])), rl.Vector2{z_input.text_pos.x, z_input.text_pos.y}, state.font_size, 1)
        
        // Draw dimension selection
        draw_outlined_text(state.font, "STARTING DIMENSION:", rl.Vector2{20, overworld_button.rect.y - layout.spacing}, state.font_size, 1)
        
        // Draw Overworld button
        overworld_color := rl.ColorAlpha(
            state.coordinates.source_dimension == Dimension.Overworld ? rl.SKYBLUE : rl.DARKGRAY,
            0.7,
        )
        if state.input.active_input == .Dimension && state.coordinates.source_dimension == Dimension.Overworld {
            overworld_color = rl.ColorAlpha(rl.BLUE, 0.7)
        }
        rl.DrawRectangleRec(overworld_button.rect, overworld_color)
        draw_outlined_text(state.font, "OVERWORLD", rl.Vector2{overworld_button.text_pos.x, overworld_button.text_pos.y}, state.font_size, 1)
        
        // Draw Nether button
        nether_color := rl.ColorAlpha(
            state.coordinates.source_dimension == Dimension.Nether ? rl.SKYBLUE : rl.DARKGRAY,
            0.7,
        )
        if state.input.active_input == .Dimension && state.coordinates.source_dimension == Dimension.Nether {
            nether_color = rl.ColorAlpha(rl.BLUE, 0.7)
        }
        rl.DrawRectangleRec(nether_button.rect, nether_color)
        draw_outlined_text(state.font, "NETHER", rl.Vector2{nether_button.text_pos.x, nether_button.text_pos.y}, state.font_size, 1)
        
        // Draw converted coordinates
        converted := get_converted_coordinates(&state.coordinates)
        converted_text := coordinates_to_string(state.coordinates.converted)
        draw_outlined_text(
            state.font,
            strings.clone_to_cstring(converted_text),
            rl.Vector2{DEFAULT_LAYOUT.margin, f32(state.window_height/2) + 50},
            state.font_size,
            1,
        )
    }
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
