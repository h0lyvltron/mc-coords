package main

import "core:fmt"
import "core:mem"
import "core:strings"
import "core:strconv"
import "core:os"
import "core:math"
import rl "vendor:raylib"

AppState :: struct {
    window_width: i32,
    window_height: i32,
    font: rl.Font,
    font_size: f32,
    coordinates: CoordinateState,
    help_visible: bool,
    input: InputState,
    background: BackgroundImage,
    title: TitleImage,
    clipboard: struct {
        hovered: bool,
        last_copied: f32,
    },
    // Future enhancements
    locations: LocationDatabase,
    settings: Settings,
    layout: Layout,
    debug_view: bool,  // Toggle for debug visualizations
    state_tracking: struct {
        has_unsaved_changes: bool,
        last_auto_save: f64,  // Time of last auto-save
        auto_save_interval: f64,  // Minimum time between auto-saves in seconds
    },
}

Modal_State :: enum {
    None,
    ConvertCoordinates,
    SaveLocation,
    LoadLocation,
    Settings,
    Help,
}

Settings :: struct {
    theme: string,
    font_size: f32,
    auto_save: bool,
    default_dimension: Dimension,
}

WindowDefaultFlags :: struct {
    title: string,
    width: i32,
    height: i32,
    pos_x: i32,
    pos_y: i32,
}

WINDOW_DEFAULT_FLAGS := WindowDefaultFlags {
    title = "Minecraft Location Manager",
    width = 480,
    height = 640,
    pos_x = 100,
    pos_y = 100,
}

BackgroundImage :: struct {
    texture: rl.Texture2D,
    source_rect: rl.Rectangle,
    dest_rect: rl.Rectangle,
    shader: rl.Shader,
    time_loc: i32,        // Uniform location for time
    resolution_loc: i32,  // Uniform location for resolution
}

WindowState :: struct {
    width: i32,
    height: i32,
    min_width: i32,
    min_height: i32,
    is_resizing: bool,
    last_width: i32,
    last_height: i32,
    position: struct {
        x: i32,
        y: i32,
    },
}

init_window_state :: proc() -> WindowState {
    return WindowState {
        width = WINDOW_DEFAULT_FLAGS.width,
        height = WINDOW_DEFAULT_FLAGS.height,
        min_width = 400,  // Minimum window width
        min_height = 300, // Minimum window height
        is_resizing = false,
        last_width = WINDOW_DEFAULT_FLAGS.width,
        last_height = WINDOW_DEFAULT_FLAGS.height,
        position = {
            x = WINDOW_DEFAULT_FLAGS.pos_x,
            y = WINDOW_DEFAULT_FLAGS.pos_y,
        },
    }
}

handle_window_resize :: proc(window: ^WindowState) {
    current_width := rl.GetScreenWidth()
    current_height := rl.GetScreenHeight()
    
    // Check if window is being resized
    if current_width != window.width || current_height != window.height {
        window.is_resizing = true
        
        // Enforce minimum size
        if current_width < window.min_width {
            rl.SetWindowSize(window.min_width, current_height)
            current_width = window.min_width
        }
        if current_height < window.min_height {
            rl.SetWindowSize(current_width, window.min_height)
            current_height = window.min_height
        }
        
        // Update window state
        window.width = current_width
        window.height = current_height
        
        // Store last valid size
        window.last_width = current_width
        window.last_height = current_height
    } else {
        window.is_resizing = false
    }
    
    // Update window position
    pos := rl.GetWindowPosition()
    window.position.x = i32(pos.x)
    window.position.y = i32(pos.y)
}

update_window_state :: proc(window: ^WindowState, state: ^AppState) {
    handle_window_resize(window)
    
    // Update app state with new dimensions
    state.window_width = window.width
    state.window_height = window.height
    
    // Update layout
    update_layout(&state.layout, window.width, window.height)
    
    // Update background image
    if window.is_resizing {
        // Calculate aspect ratio preserving dimensions
        bg_width := f32(state.background.texture.width)
        bg_height := f32(state.background.texture.height)
        window_aspect := f32(window.width) / f32(window.height)
        bg_aspect := bg_width / bg_height
        
        dest_width: f32
        dest_height: f32
        
        if window_aspect > bg_aspect {
            // Window is wider than background
            dest_height = f32(window.height)
            dest_width = dest_height * bg_aspect
        } else {
            // Window is taller than background
            dest_width = f32(window.width)
            dest_height = dest_width / bg_aspect
        }
        
        // Center the background
        x_offset := (f32(window.width) - dest_width) / 2
        y_offset := (f32(window.height) - dest_height) / 2
        
        // Update background destination rectangle
        state.background.dest_rect = rl.Rectangle{
            x = x_offset,
            y = y_offset,
            width = dest_width,
            height = dest_height,
        }
        
        // Update shader resolution
        resolution := [2]f32{f32(window.width), f32(window.height)}
        rl.SetShaderValue(state.background.shader, state.background.resolution_loc, &resolution, .VEC2)
        
        // Update title shader resolutions
        for i in 0..<len(state.title.shaders) {
            rl.SetShaderValue(state.title.shaders[i].shader, state.title.shaders[i].resolution_loc, &resolution, .VEC2)
        }
    }
}

calculate_image_crop :: proc(image_width, image_height, target_width, target_height: i32) -> rl.Rectangle {
    source_aspect := f32(image_width) / f32(image_height)
    target_aspect := f32(target_width) / f32(target_height)
    crop := rl.Rectangle{}
    
    if source_aspect > target_aspect {
        crop.height = f32(image_height)
        crop.width = crop.height * target_aspect
        crop.x = f32(image_width - i32(crop.width)) / 2
        crop.y = 0
    } else {
        crop.width = f32(image_width)
        crop.height = crop.width / target_aspect
        crop.x = 0
        crop.y = f32(image_height - i32(crop.height)) / 2
    }
    
    return crop
}

load_background_image :: proc(path: string, window_width, window_height: i32) -> (BackgroundImage, bool) {
    image := rl.LoadImage(strings.clone_to_cstring(path))
    if image.data == nil {
        fmt.eprintln("Failed to load image:", path)
        return BackgroundImage{}, false
    }
    defer rl.UnloadImage(image)
    
    crop := calculate_image_crop(image.width, image.height, window_width, window_height)
    
    texture := rl.LoadTextureFromImage(image)
    if texture.id == 0 {
        fmt.eprintln("Failed to create texture from image:", path)
        return BackgroundImage{}, false
    }
    
    shader := rl.LoadShaderFromMemory(BACKGROUND_VERTEX_SHADER, BACKGROUND_FRAGMENT_SHADER)
    if shader.id == 0 {
        fmt.eprintln("Failed to load background shader")
        rl.UnloadTexture(texture)
        return BackgroundImage{}, false
    }
    
    time_loc := rl.GetShaderLocation(shader, "time")
    resolution_loc := rl.GetShaderLocation(shader, "resolution")
    
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

TitleImage :: struct {
    texture: rl.Texture2D,
    char_width: i32,
    char_height: i32,
    chars: [10]rl.Rectangle, // 9 letters + 1 empty
    padding: f32,
    shaders: [3]struct { 
        shader: rl.Shader,
        time_loc: i32,
        resolution_loc: i32,
        blend_factor: f32,  // How much this shader contributes to the final result
        // Digital noise parameters
        noise_scale_loc: i32,
        glitch_intensity_loc: i32,
        scan_line_density_loc: i32,
        tear_frequency_loc: i32,
        rgb_split_amount_loc: i32,
        static_amount_loc: i32,
        pulse_speed_loc: i32,
        pulse_intensity_loc: i32,
        glitch_color_loc: i32,
    },
    hover_state: struct {
        index: i32,
        time: f32,
        rotation: [9]f32,
        scale: [9]f32,
        tint_color: [9]rl.Color,
    },
    // Digital noise parameters
    digital_noise_params: struct {
        noise_scale: f32,
        glitch_intensity: f32,
        scan_line_density: f32,
        tear_frequency: f32,
        rgb_split_amount: f32,
        static_amount: f32,
        pulse_speed: f32,
        pulse_intensity: f32,
        glitch_color: [3]f32,
    },
}

init_app :: proc() -> AppState {
    state := AppState {
        window_width = WINDOW_DEFAULT_FLAGS.width,
        window_height = WINDOW_DEFAULT_FLAGS.height,
        font = load_font_with_fallback(),
        font_size = DEFAULT_FONT_SETTINGS.size,
        coordinates = init_coordinate_state(),
        help_visible = false,
        debug_view = false,
        state_tracking = {
            has_unsaved_changes = false,
            last_auto_save = 0,
            auto_save_interval = 5.0,
        },
    }
    
    init_input_state(&state.input)
    
    // Try to load previous state first
    if load_state(&state) {
        fmt.println("* Previous state loaded successfully")
    }
    
    bg, ok := load_background_image("assets/tree-house.png", state.window_width, state.window_height)
    if ok {
        state.background = bg
    } else {
        fmt.eprintln("Failed to load background image")
    }

    // Load title image
    title_img := rl.LoadImage(strings.clone_to_cstring("assets/title.png"))
    if title_img.data == nil {
        fmt.eprintln("! Failed to load title image")
        return state
    }
    defer rl.UnloadImage(title_img)

    state.title.texture = rl.LoadTextureFromImage(title_img)
    if state.title.texture.id == 0 {
        fmt.eprintln("! Failed to create texture from title image")
        return state
    }
    
    state.title.char_width = 32
    state.title.char_height = 32
    state.title.padding = 0
    
    // Initialize title character rectangles - each sprite is 32x32
    for i in 0..<10 {
        state.title.chars[i] = rl.Rectangle{
            x = f32(i32(i) * state.title.char_width),
            y = 0,
            width = f32(state.title.char_width),
            height = f32(state.title.char_height),
        }
    }
    
    // Print texture dimensions for debugging
    fmt.println("* Title texture dimensions:", title_img.width, "x", title_img.height)
    
    // Initialize hover state
    state.title.hover_state.index = -1
    state.title.hover_state.time = 0
    for i in 0..<9 {
        state.title.hover_state.rotation[i] = 0
        state.title.hover_state.scale[i] = 1.0
        state.title.hover_state.tint_color[i] = rl.WHITE
    }
    
    // Initialize shaders
    state.title.shaders[0].shader = rl.LoadShaderFromMemory(DIGITAL_NOISE_VERTEX_SHADER, DIGITAL_NOISE_FRAGMENT_SHADER)  // Digital noise shader
    state.title.shaders[1].shader = rl.LoadShaderFromMemory(HEX_TRUCHET_VERTEX_SHADER, HEX_TRUCHET_FRAGMENT_SHADER)
    state.title.shaders[2].shader = rl.LoadShaderFromMemory(RAYMARCH_VERTEX_SHADER, RAYMARCH_FRAGMENT_SHADER)

    // Check if shaders loaded successfully
    for i in 0..<3 {
        if state.title.shaders[i].shader.id == 0 {
            fmt.eprintln("! Failed to load shader", i)
            return state
        }
    }

    // Get shader locations
    for i in 0..<3 {
        state.title.shaders[i].time_loc = rl.GetShaderLocation(state.title.shaders[i].shader, "time")
        state.title.shaders[i].resolution_loc = rl.GetShaderLocation(state.title.shaders[i].shader, "resolution")
        
        // Get digital noise shader locations for the first shader
        if i == 0 {
            state.title.shaders[i].noise_scale_loc = rl.GetShaderLocation(state.title.shaders[i].shader, "noise_scale")
            state.title.shaders[i].glitch_intensity_loc = rl.GetShaderLocation(state.title.shaders[i].shader, "glitch_intensity")
            state.title.shaders[i].scan_line_density_loc = rl.GetShaderLocation(state.title.shaders[i].shader, "scan_line_density")
            state.title.shaders[i].tear_frequency_loc = rl.GetShaderLocation(state.title.shaders[i].shader, "tear_frequency")
            state.title.shaders[i].rgb_split_amount_loc = rl.GetShaderLocation(state.title.shaders[i].shader, "rgb_split_amount")
            state.title.shaders[i].static_amount_loc = rl.GetShaderLocation(state.title.shaders[i].shader, "static_amount")
            state.title.shaders[i].pulse_speed_loc = rl.GetShaderLocation(state.title.shaders[i].shader, "pulse_speed")
            state.title.shaders[i].pulse_intensity_loc = rl.GetShaderLocation(state.title.shaders[i].shader, "pulse_intensity")
            state.title.shaders[i].glitch_color_loc = rl.GetShaderLocation(state.title.shaders[i].shader, "glitch_color")
            
            // Set default values from state.json
            state.title.digital_noise_params = {
                noise_scale = 0.1,
                glitch_intensity = 0.95,
                scan_line_density = 10.0,
                tear_frequency = 0.2,
                rgb_split_amount = 0.011,
                static_amount = 0.5,
                pulse_speed = 5.0,
                pulse_intensity = 1.0,
                glitch_color = {1.1, 1.0, 1.2},
            }
            
            // Apply parameters
            rl.SetShaderValue(state.title.shaders[i].shader, state.title.shaders[i].noise_scale_loc, &state.title.digital_noise_params.noise_scale, .FLOAT)
            rl.SetShaderValue(state.title.shaders[i].shader, state.title.shaders[i].glitch_intensity_loc, &state.title.digital_noise_params.glitch_intensity, .FLOAT)
            rl.SetShaderValue(state.title.shaders[i].shader, state.title.shaders[i].scan_line_density_loc, &state.title.digital_noise_params.scan_line_density, .FLOAT)
            rl.SetShaderValue(state.title.shaders[i].shader, state.title.shaders[i].tear_frequency_loc, &state.title.digital_noise_params.tear_frequency, .FLOAT)
            rl.SetShaderValue(state.title.shaders[i].shader, state.title.shaders[i].rgb_split_amount_loc, &state.title.digital_noise_params.rgb_split_amount, .FLOAT)
            rl.SetShaderValue(state.title.shaders[i].shader, state.title.shaders[i].static_amount_loc, &state.title.digital_noise_params.static_amount, .FLOAT)
            rl.SetShaderValue(state.title.shaders[i].shader, state.title.shaders[i].pulse_speed_loc, &state.title.digital_noise_params.pulse_speed, .FLOAT)
            rl.SetShaderValue(state.title.shaders[i].shader, state.title.shaders[i].pulse_intensity_loc, &state.title.digital_noise_params.pulse_intensity, .FLOAT)
            rl.SetShaderValue(state.title.shaders[i].shader, state.title.shaders[i].glitch_color_loc, &state.title.digital_noise_params.glitch_color[0], .VEC3)
        }
    }

    // Set blend factors
    state.title.shaders[0].blend_factor = 1.0  // Digital noise shader - reduced for subtle glitch effect
    state.title.shaders[1].blend_factor = 0.4  // Hex Truchet shader - medium contribution
    state.title.shaders[2].blend_factor = 0.3  // Raymarch shader - reduced for subtle depth

    // Set initial shader values
    resolution := [2]f32{f32(state.window_width), f32(state.window_height)}
    for i in 0..<3 {
        rl.SetShaderValue(state.title.shaders[i].shader, state.title.shaders[i].resolution_loc, &resolution, .VEC2)
    }

    fmt.println("* Shader parameters applied from loaded state:")
    fmt.println("  Digital Noise: Scale=", state.title.digital_noise_params.noise_scale,
                " Intensity=", state.title.digital_noise_params.glitch_intensity,
                " Scan Line Density=", state.title.digital_noise_params.scan_line_density,
                " Tear Frequency=", state.title.digital_noise_params.tear_frequency,
                " RGB Split Amount=", state.title.digital_noise_params.rgb_split_amount,
                " Static Amount=", state.title.digital_noise_params.static_amount,
                " Pulse Speed=", state.title.digital_noise_params.pulse_speed,
                " Pulse Intensity=", state.title.digital_noise_params.pulse_intensity)
    
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
    
    state.layout = DEFAULT_LAYOUT
    
    return state
}

main :: proc() {
    // Enable window resizing and other window flags
    rl.SetConfigFlags({.WINDOW_RESIZABLE, .WINDOW_HIGHDPI})
    rl.InitWindow(WINDOW_DEFAULT_FLAGS.width, WINDOW_DEFAULT_FLAGS.height, strings.clone_to_cstring(WINDOW_DEFAULT_FLAGS.title))
    defer rl.CloseWindow()

    rl.SetTargetFPS(60)

    state := init_app()
    window := init_window_state()
    defer {
        rl.UnloadFont(state.font)
        rl.UnloadTexture(state.title.texture)
        delete(state.input.key_states)
        
        // Clean up shaders
        for i in 0..<len(state.title.shaders) {
            if state.title.shaders[i].shader.id != 0 {
                rl.UnloadShader(state.title.shaders[i].shader)
            }
        }
        
        // Clean up background shader
        if state.background.shader.id != 0 {
            rl.UnloadShader(state.background.shader)
        }
        if state.background.texture.id != 0 {
            rl.UnloadTexture(state.background.texture)
        }
        
        // Clean up locations array
        delete(state.locations.locations)
    }
    
    // Initialize layout sections
    converter_section := add_section(&state.layout, "converter", 300)
    locations_section := add_section(&state.layout, "locations", 400)
    
    // Create UI elements in the converter section
    x_input := make_input_box(&state.layout, converter_section, Position{20, 140}, "X:", state.font, state.font_size, 1)
    z_input := make_input_box(&state.layout, converter_section, Position{20, 140 + state.layout.section_spacing}, "Z:", state.font, state.font_size, 1)
    overworld_button, nether_button := make_dimension_buttons(&state.layout, converter_section, Position{20, 140 + 2*state.layout.section_spacing + state.layout.spacing})
    
    // Create converted coordinates display
    converted_coords := UIElement{
        rect = rl.Rectangle{
            x = state.layout.margin,
            y = 140 + 3*state.layout.section_spacing + state.layout.spacing,
            width = 200,
            height = state.font_size * 2,
        },
        text_pos = Position{
            x = state.layout.margin + 10,
            y = 140 + 3*state.layout.section_spacing + state.layout.spacing + state.font_size/2,
        },
    }
    
    // Add UI elements to section's element map
    converter_section.elements[UIElement_ID(0)] = UIElementState{
        bounds = x_input.rect,
        is_active = false,
        is_visible = true,
        is_hovered = false,
    }
    converter_section.elements[UIElement_ID(1)] = UIElementState{
        bounds = z_input.rect,
        is_active = false,
        is_visible = true,
        is_hovered = false,
    }
    converter_section.elements[UIElement_ID(2)] = UIElementState{
        bounds = overworld_button.rect,
        is_active = false,
        is_visible = true,
        is_hovered = false,
    }
    converter_section.elements[UIElement_ID(3)] = UIElementState{
        bounds = nether_button.rect,
        is_active = false,
        is_visible = true,
        is_hovered = false,
    }
    converter_section.elements[UIElement_ID(4)] = UIElementState{
        bounds = converted_coords.rect,
        is_active = false,
        is_visible = true,
        is_hovered = false,
    }

    for !rl.WindowShouldClose() {
        // Update window state and handle resizing
        update_window_state(&window, &state)
        
        // Handle scrolling
        handle_scroll(&state.layout, rl.GetMousePosition())
        
        // Get current mouse position
        mouse_pos := rl.GetMousePosition()
        
        // Update UI element positions based on section scroll
        for i in 0..<5 {
            element := &converter_section.elements[UIElement_ID(i)]
            if element.is_visible {
                element.bounds.y -= converter_section.scroll_offset
            }
        }
        
        if rl.IsMouseButtonPressed(.LEFT) {
            handled_click := false
            
            // Check clicks against section elements
            for i in 0..<5 {
                element := &converter_section.elements[UIElement_ID(i)]
                if element.is_visible && rl.CheckCollisionPointRec(mouse_pos, element.bounds) {
                    switch i {
                    case 0: // X input
                        if state.input.active_input != .X {
                            fmt.println("State change: Clicked X input")
                            state.input.active_input = .X
                            state.input.should_clear = true
                        }
                    case 1: // Z input
                        if state.input.active_input != .Z {
                            fmt.println("State change: Clicked Z input")
                            state.input.active_input = .Z
                            state.input.should_clear = true
                        }
                    case 2: // Overworld button
                        if state.input.active_input != .Dimension || state.coordinates.source_dimension != Dimension.Overworld {
                            fmt.println("State change: Clicked Overworld button")
                            handle_dimension_click(&state, .Overworld)
                        }
                    case 3: // Nether button
                        if state.input.active_input != .Dimension || state.coordinates.source_dimension != Dimension.Nether {
                            fmt.println("State change: Clicked Nether button")
                            handle_dimension_click(&state, .Nether)
                        }
                    }
                    handled_click = true
                    break
                }
            }
            
            if !handled_click && state.clipboard.hovered {
                coord_str := fmt.tprintf("%d, %d", state.coordinates.converted.x, state.coordinates.converted.z)
                rl.SetClipboardText(strings.clone_to_cstring(coord_str))
                state.clipboard.last_copied = 0.5 // Start feedback animation
                handled_click = true
            } else if !handled_click && state.input.active_input != .None {
                fmt.println("State change: Clicked outside inputs")
                state.input.active_input = .None
            }
        }

        // Toggle debug view with F3
        if rl.IsKeyPressed(.F3) {
            state.debug_view = !state.debug_view
            fmt.println("Debug view:", state.debug_view ? "enabled" : "disabled")
        }

        if update_input_state(&state.input) {
            update_coordinates_from_input(&state.input, &state.coordinates, &state)
        }

        if state.input.active_input == .X || state.input.active_input == .Z {
            if rl.IsKeyPressed(.ENTER) || rl.IsKeyPressed(.TAB) || rl.IsKeyPressed(.BACKSPACE) || 
               (rl.IsKeyPressed(.ZERO) || rl.IsKeyPressed(.ONE) || rl.IsKeyPressed(.TWO) || 
                rl.IsKeyPressed(.THREE) || rl.IsKeyPressed(.FOUR) || rl.IsKeyPressed(.FIVE) || 
                rl.IsKeyPressed(.SIX) || rl.IsKeyPressed(.SEVEN) || rl.IsKeyPressed(.EIGHT) || 
                rl.IsKeyPressed(.NINE) || rl.IsKeyPressed(.MINUS)) {
                update_coordinates_from_input(&state.input, &state.coordinates, &state)
            }
        }

        if state.input.needs_dimension_toggle {
            state.coordinates.source_dimension = state.coordinates.source_dimension == Dimension.Overworld ? Dimension.Nether : Dimension.Overworld
            state.coordinates.needs_conversion = true
            state.input.needs_dimension_toggle = false
        }

        // Update converted coordinates position based on section scroll
        converted_coords.rect.y = 140 + 3*state.layout.section_spacing + state.layout.spacing - converter_section.scroll_offset
        converted_coords.text_pos.y = 140 + 3*state.layout.section_spacing + state.layout.spacing + state.font_size/2 - converter_section.scroll_offset
        
        // Update element bounds for click detection
        element := converter_section.elements[UIElement_ID(4)]
        element.bounds = converted_coords.rect
        converter_section.elements[UIElement_ID(4)] = element

        if state.clipboard.last_copied > 0 {
            state.clipboard.last_copied -= rl.GetFrameTime()
        }

        if state.coordinates.needs_conversion {
            fmt.println("Attempting conversion")
            get_converted_coordinates(&state.coordinates)
        }

        // Update title hover state
        title_scale: f32 = 1.5
        base_width := f32(state.title.char_width) * title_scale
        base_height := f32(state.title.char_height) * title_scale
        total_width := base_width * 9 // currently 9 sprite chunks
        start_x := f32(state.window_width) / 2 - total_width / 2
        
        // Reset hover state
        state.title.hover_state.index = -1
        
        // Check for hover using the actual drawn letter positions
        for i in 0..<9 {
            char_x := start_x + f32(i32(i)) * base_width
            
            // Use the base dimensions for hover detection to match the visible letters
            hover_rect := rl.Rectangle{
                x = char_x,
                y = 20,
                width = base_width,
                height = base_height,
            }
            
            if rl.CheckCollisionPointRec(mouse_pos, hover_rect) {
                state.title.hover_state.index = i32(i)
                break
            }
        }
        
        // Update animations
        state.title.hover_state.time += rl.GetFrameTime()
        for i in 0..<9 {
            if i32(i) == state.title.hover_state.index {
                // Animate hovered letter
                state.title.hover_state.rotation[i] = math.sin(state.title.hover_state.time * 2) * 5
                state.title.hover_state.scale[i] = 1.0 + math.sin(state.title.hover_state.time * 3) * 0.1
            } else {
                // Reset non-hovered letters
                state.title.hover_state.rotation[i] = 0
                state.title.hover_state.scale[i] = 1.0
            }
        }

        rl.BeginDrawing()
        defer rl.EndDrawing()

        rl.ClearBackground(rl.BLACK)
        
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
        
        // Draw title using the image atlas
        // Reuse the variables from above instead of redeclaring
        // title_scale, base_width, base_height, total_width, and start_x are already defined
        
        if state.debug_view {
            // Draw total width debug rectangle
            total_bounds := rl.Rectangle{
                x = start_x,
                y = 15,
                width = total_width,
                height = base_height + 10,
            }
            rl.DrawRectangleLinesEx(total_bounds, 2, rl.ColorAlpha(rl.PURPLE, 0.3))
            
            // Draw center line for reference
            center_x := f32(state.window_width) / 2
            rl.DrawLine(i32(center_x), 0, i32(center_x), 60, rl.ColorAlpha(rl.RED, 0.5))
            
            // Draw source texture debug info
            debug_text := fmt.tprintf("Texture: %dx%d", state.title.texture.width, state.title.texture.height)
            rl.DrawText(strings.clone_to_cstring(debug_text), 10, 60, 10, rl.ColorAlpha(rl.WHITE, 0.5))
        }
        
        // Update shader time
        title_time := f32(rl.GetTime())
        rl.SetShaderValue(state.title.shaders[0].shader, state.title.shaders[0].time_loc, &title_time, .FLOAT)
        rl.SetShaderValue(state.title.shaders[1].shader, state.title.shaders[1].time_loc, &title_time, .FLOAT)
        rl.SetShaderValue(state.title.shaders[2].shader, state.title.shaders[2].time_loc, &title_time, .FLOAT)
        
        shader := &state.title.shaders[0]  // Digital noise shader
        rl.SetShaderValue(shader.shader, shader.noise_scale_loc, &state.title.digital_noise_params.noise_scale, .FLOAT)
        rl.SetShaderValue(shader.shader, shader.glitch_intensity_loc, &state.title.digital_noise_params.glitch_intensity, .FLOAT)
        rl.SetShaderValue(shader.shader, shader.scan_line_density_loc, &state.title.digital_noise_params.scan_line_density, .FLOAT)
        rl.SetShaderValue(shader.shader, shader.tear_frequency_loc, &state.title.digital_noise_params.tear_frequency, .FLOAT)
        rl.SetShaderValue(shader.shader, shader.rgb_split_amount_loc, &state.title.digital_noise_params.rgb_split_amount, .FLOAT)
        rl.SetShaderValue(shader.shader, shader.static_amount_loc, &state.title.digital_noise_params.static_amount, .FLOAT)
        rl.SetShaderValue(shader.shader, shader.pulse_speed_loc, &state.title.digital_noise_params.pulse_speed, .FLOAT)
        rl.SetShaderValue(shader.shader, shader.pulse_intensity_loc, &state.title.digital_noise_params.pulse_intensity, .FLOAT)
        rl.SetShaderValue(shader.shader, shader.glitch_color_loc, &state.title.digital_noise_params.glitch_color[0], .VEC3)
        
        // Update parameters on keyboard input
        if rl.IsKeyDown(.LEFT_CONTROL) && !rl.IsKeyDown(.LEFT_SHIFT) {
            if rl.IsKeyDown(.Q) {
                state.title.digital_noise_params.noise_scale = max(0.1, state.title.digital_noise_params.noise_scale - 0.5)
                handle_shader_param_update(&state, .NoiseScale, state.title.digital_noise_params.noise_scale)
            }
            if rl.IsKeyDown(.A) {
                state.title.digital_noise_params.noise_scale = min(50.0, state.title.digital_noise_params.noise_scale + 0.5)
                handle_shader_param_update(&state, .NoiseScale, state.title.digital_noise_params.noise_scale)
            }
            if rl.IsKeyDown(.W) {
                state.title.digital_noise_params.glitch_intensity = clamp(state.title.digital_noise_params.glitch_intensity + 0.05, 0.0, 1.0)
                handle_shader_param_update(&state, .GlitchIntensity, state.title.digital_noise_params.glitch_intensity)
            }
            if rl.IsKeyDown(.S) {
                state.title.digital_noise_params.glitch_intensity = clamp(state.title.digital_noise_params.glitch_intensity - 0.05, 0.0, 1.0)
                handle_shader_param_update(&state, .GlitchIntensity, state.title.digital_noise_params.glitch_intensity)
            }
            if rl.IsKeyDown(.E) {
                state.title.digital_noise_params.scan_line_density = clamp(state.title.digital_noise_params.scan_line_density + 0.1, 0.1, 10.0)
                handle_shader_param_update(&state, .ScanLineDensity, state.title.digital_noise_params.scan_line_density)
            }
            if rl.IsKeyDown(.D) {
                state.title.digital_noise_params.scan_line_density = clamp(state.title.digital_noise_params.scan_line_density - 0.1, 0.1, 10.0)
                handle_shader_param_update(&state, .ScanLineDensity, state.title.digital_noise_params.scan_line_density)
            }
            if rl.IsKeyDown(.R) {
                state.title.digital_noise_params.tear_frequency = clamp(state.title.digital_noise_params.tear_frequency + 0.01, 0.0, 0.2)
                handle_shader_param_update(&state, .TearFrequency, state.title.digital_noise_params.tear_frequency)
            }
            if rl.IsKeyDown(.F) {
                state.title.digital_noise_params.tear_frequency = clamp(state.title.digital_noise_params.tear_frequency - 0.01, 0.0, 0.2)
                handle_shader_param_update(&state, .TearFrequency, state.title.digital_noise_params.tear_frequency)
            }
            if rl.IsKeyDown(.T) {
                state.title.digital_noise_params.rgb_split_amount = clamp(state.title.digital_noise_params.rgb_split_amount + 0.001, 0.0, 0.02)
                handle_shader_param_update(&state, .RGBSplitAmount, state.title.digital_noise_params.rgb_split_amount)
            }
            if rl.IsKeyDown(.G) {
                state.title.digital_noise_params.rgb_split_amount = clamp(state.title.digital_noise_params.rgb_split_amount - 0.001, 0.0, 0.02)
                handle_shader_param_update(&state, .RGBSplitAmount, state.title.digital_noise_params.rgb_split_amount)
            }
            if rl.IsKeyDown(.Y) {
                state.title.digital_noise_params.static_amount = clamp(state.title.digital_noise_params.static_amount + 0.02, 0.0, 0.5)
                handle_shader_param_update(&state, .StaticAmount, state.title.digital_noise_params.static_amount)
            }
            if rl.IsKeyDown(.H) {
                state.title.digital_noise_params.static_amount = clamp(state.title.digital_noise_params.static_amount - 0.02, 0.0, 0.5)
                handle_shader_param_update(&state, .StaticAmount, state.title.digital_noise_params.static_amount)
            }
            if rl.IsKeyDown(.U) {
                state.title.digital_noise_params.pulse_speed = clamp(state.title.digital_noise_params.pulse_speed + 0.1, 0.1, 5.0)
                handle_shader_param_update(&state, .PulseSpeed, state.title.digital_noise_params.pulse_speed)
            }
            if rl.IsKeyDown(.J) {
                state.title.digital_noise_params.pulse_speed = clamp(state.title.digital_noise_params.pulse_speed - 0.1, 0.1, 5.0)
                handle_shader_param_update(&state, .PulseSpeed, state.title.digital_noise_params.pulse_speed)
            }
            if rl.IsKeyDown(.I) {
                state.title.digital_noise_params.pulse_intensity = clamp(state.title.digital_noise_params.pulse_intensity + 0.05, 0.0, 1.0)
                handle_shader_param_update(&state, .PulseIntensity, state.title.digital_noise_params.pulse_intensity)
            }
            if rl.IsKeyDown(.K) {
                state.title.digital_noise_params.pulse_intensity = clamp(state.title.digital_noise_params.pulse_intensity - 0.05, 0.0, 1.0)
                handle_shader_param_update(&state, .PulseIntensity, state.title.digital_noise_params.pulse_intensity)
            }
            
            // Clamp values to reasonable ranges
            state.title.digital_noise_params.noise_scale = clamp(state.title.digital_noise_params.noise_scale, 0.1, 50.0)
            state.title.digital_noise_params.glitch_intensity = clamp(state.title.digital_noise_params.glitch_intensity, 0.0, 1.0)
            state.title.digital_noise_params.scan_line_density = clamp(state.title.digital_noise_params.scan_line_density, 0.1, 10.0)
            state.title.digital_noise_params.tear_frequency = clamp(state.title.digital_noise_params.tear_frequency, 0.0, 0.2)
            state.title.digital_noise_params.rgb_split_amount = clamp(state.title.digital_noise_params.rgb_split_amount, 0.0, 0.02)
            state.title.digital_noise_params.static_amount = clamp(state.title.digital_noise_params.static_amount, 0.0, 0.5)
            state.title.digital_noise_params.pulse_speed = clamp(state.title.digital_noise_params.pulse_speed, 0.1, 5.0)
            state.title.digital_noise_params.pulse_intensity = clamp(state.title.digital_noise_params.pulse_intensity, 0.0, 1.0)
            
            // Update shader uniforms
            rl.SetShaderValue(state.title.shaders[0].shader, state.title.shaders[0].noise_scale_loc, &state.title.digital_noise_params.noise_scale, .FLOAT)
            rl.SetShaderValue(state.title.shaders[0].shader, state.title.shaders[0].glitch_intensity_loc, &state.title.digital_noise_params.glitch_intensity, .FLOAT)
            rl.SetShaderValue(state.title.shaders[0].shader, state.title.shaders[0].scan_line_density_loc, &state.title.digital_noise_params.scan_line_density, .FLOAT)
            rl.SetShaderValue(state.title.shaders[0].shader, state.title.shaders[0].tear_frequency_loc, &state.title.digital_noise_params.tear_frequency, .FLOAT)
            rl.SetShaderValue(state.title.shaders[0].shader, state.title.shaders[0].rgb_split_amount_loc, &state.title.digital_noise_params.rgb_split_amount, .FLOAT)
            rl.SetShaderValue(state.title.shaders[0].shader, state.title.shaders[0].static_amount_loc, &state.title.digital_noise_params.static_amount, .FLOAT)
            rl.SetShaderValue(state.title.shaders[0].shader, state.title.shaders[0].pulse_speed_loc, &state.title.digital_noise_params.pulse_speed, .FLOAT)
            rl.SetShaderValue(state.title.shaders[0].shader, state.title.shaders[0].pulse_intensity_loc, &state.title.digital_noise_params.pulse_intensity, .FLOAT)
            rl.SetShaderValue(state.title.shaders[0].shader, state.title.shaders[0].glitch_color_loc, &state.title.digital_noise_params.glitch_color[0], .VEC3)
            
            if state.debug_view {
                debug_text := fmt.tprintf(
                    "Digital Noise: Scale=%.2f Intensity=%.2f Scan Line Density=%.2f Tear Frequency=%.2f\nRGB Split Amount=%.3f Static Amount=%.2f Pulse Speed=%.2f Pulse Intensity=%.2f",
                    state.title.digital_noise_params.noise_scale,
                    state.title.digital_noise_params.glitch_intensity,
                    state.title.digital_noise_params.scan_line_density,
                    state.title.digital_noise_params.tear_frequency,
                    state.title.digital_noise_params.rgb_split_amount,
                    state.title.digital_noise_params.static_amount,
                    state.title.digital_noise_params.pulse_speed,
                    state.title.digital_noise_params.pulse_intensity,
                )
                rl.DrawText(strings.clone_to_cstring(debug_text), 10, 40, 10, rl.ColorAlpha(rl.WHITE, 0.5))
            }
        }
        
        for i in 0..<9 {  // Draw 9 letters
            letter_index := i32(i + 1)  // Skip the first empty sprite
            
            // Source rectangle from sprite sheet - each letter is 32x32
            src_x := f32(letter_index * state.title.char_width)
            src_rect := rl.Rectangle{
                x = src_x,
                y = 0,
                width = f32(state.title.char_width),
                height = f32(state.title.char_height),
            }
            
            // Destination position calculation
            dest_x := start_x + f32(i) * base_width
            scale := state.title.hover_state.scale[i]
            
            // Calculate the center point of where the letter should be
            center_x := dest_x + base_width/2
            center_y := 20 + base_height/2
            
            // Create the destination rectangle centered on the same spot but with scale
            dest_rect := rl.Rectangle{
                x = center_x - (base_width * scale)/2 + f32(state.title.char_width)/2,  // Add half sprite width
                y = center_y - (base_height * scale)/2 + f32(state.title.char_height)/2,  // Add half sprite height
                width = base_width * scale,
                height = base_height * scale,
            }
            
            // Create the hover detection rectangle (unscaled)
            hover_rect := rl.Rectangle{
                x = dest_x,
                y = 20,
                width = base_width,
                height = base_height,
            }
            
            if state.debug_view {
                // Draw debug visualization
                debug_alpha :: 0.3
                
                // Draw grid lines
                rl.DrawLine(i32(dest_x), 15, i32(dest_x), 60, rl.ColorAlpha(rl.BLUE, 0.2))
                
                // Source rectangle visualization (drawn at destination position)
                debug_src_rect := hover_rect  // Use same position as hover rect
                rl.DrawRectangleLinesEx(debug_src_rect, 1, rl.ColorAlpha(rl.RED, debug_alpha))
                
                // Hover detection rectangle in blue
                rl.DrawRectangleLinesEx(hover_rect, 1, rl.ColorAlpha(rl.BLUE, debug_alpha))
                
                // Draw source coordinates
                src_debug := fmt.tprintf("src:%d", letter_index)
                rl.DrawText(strings.clone_to_cstring(src_debug), i32(hover_rect.x), 70, 10, rl.ColorAlpha(rl.RED, 0.5))
                
                // Draw destination coordinates
                dest_debug := fmt.tprintf("dst:%d", i)
                rl.DrawText(strings.clone_to_cstring(dest_debug), i32(hover_rect.x), 80, 10, rl.ColorAlpha(rl.BLUE, 0.5))
            }
            
            // Draw the actual sprite with multiple shaders
            origin := rl.Vector2{
                f32(state.title.char_width)/2,
                f32(state.title.char_height)/2,
            }
            
            // First pass: Digital noise shader
            rl.BeginShaderMode(state.title.shaders[0].shader)
            rl.DrawTexturePro(
                state.title.texture,
                src_rect,
                dest_rect,
                origin,
                state.title.hover_state.rotation[i],
                rl.ColorAlpha(state.title.hover_state.tint_color[i], state.title.shaders[0].blend_factor),
            )
            rl.EndShaderMode()
            
            // Second pass: Hex Truchet shader
            rl.BeginShaderMode(state.title.shaders[1].shader)
            rl.DrawTexturePro(
                state.title.texture,
                src_rect,
                dest_rect,
                origin,
                state.title.hover_state.rotation[i],
                rl.ColorAlpha(state.title.hover_state.tint_color[i], state.title.shaders[1].blend_factor),
            )
            rl.EndShaderMode()
            
            // Third pass: Raymarch shader
            rl.BeginShaderMode(state.title.shaders[2].shader)
            rl.DrawTexturePro(
                state.title.texture,
                src_rect,
                dest_rect,
                origin,
                state.title.hover_state.rotation[i],
                rl.ColorAlpha(state.title.hover_state.tint_color[i], state.title.shaders[2].blend_factor),
            )
            rl.EndShaderMode()
        }
        
        draw_outlined_text(state.font, "INPUT COORDINATES:", rl.Vector2{20, 95}, state.font_size, 1)
        
        // Debug visualization for input section header
        if state.debug_view {
            header_bounds := rl.Rectangle{20, 95, 200, state.font_size + 4}
            rl.DrawRectangleLinesEx(header_bounds, 1, rl.ColorAlpha(rl.YELLOW, 0.3))
        }
        
        draw_outlined_text(state.font, "X:", rl.Vector2{x_input.label_pos.x, x_input.label_pos.y}, state.font_size, 1)
        x_box_color := rl.ColorAlpha(state.input.active_input == .X ? rl.BLUE : rl.DARKGRAY, state.input.active_input == .X ? 0.7 : 0.5)
        rl.DrawRectangleRec(x_input.rect, x_box_color)
        draw_outlined_text(state.font, strings.clone_to_cstring(string(state.input.input_buffers[0][:])), rl.Vector2{x_input.text_pos.x, x_input.text_pos.y}, state.font_size, 1)
        
        // Debug visualization for X input
        if state.debug_view {
            // Label bounds
            label_bounds := rl.Rectangle{x_input.label_pos.x, x_input.label_pos.y, 20, state.font_size}
            rl.DrawRectangleLinesEx(label_bounds, 1, rl.ColorAlpha(rl.GREEN, 0.3))
            
            // Input box bounds
            rl.DrawRectangleLinesEx(x_input.rect, 1, rl.ColorAlpha(rl.RED, 0.3))
            
            // Text position marker
            text_marker_size :: 4
            rl.DrawRectangle(
                i32(x_input.text_pos.x) - text_marker_size/2,
                i32(x_input.text_pos.y) - text_marker_size/2,
                text_marker_size,
                text_marker_size,
                rl.ColorAlpha(rl.BLUE, 0.5),
            )
            
            // Debug info
            debug_info := fmt.tprintf("active:%v buf:%s", state.input.active_input == .X, string(state.input.input_buffers[0][:]))
            rl.DrawText(strings.clone_to_cstring(debug_info), i32(x_input.rect.x), i32(x_input.rect.y - 12), 10, rl.ColorAlpha(rl.WHITE, 0.5))
        }
        
        draw_outlined_text(state.font, "Z:", rl.Vector2{z_input.label_pos.x, z_input.label_pos.y}, state.font_size, 1)
        z_box_color := rl.ColorAlpha(state.input.active_input == .Z ? rl.BLUE : rl.DARKGRAY, state.input.active_input == .Z ? 0.7 : 0.5)
        rl.DrawRectangleRec(z_input.rect, z_box_color)
        draw_outlined_text(state.font, strings.clone_to_cstring(string(state.input.input_buffers[1][:])), rl.Vector2{z_input.text_pos.x, z_input.text_pos.y}, state.font_size, 1)
        
        // Debug visualization for Z input (similar to X input)
        if state.debug_view {
            label_bounds := rl.Rectangle{z_input.label_pos.x, z_input.label_pos.y, 20, state.font_size}
            rl.DrawRectangleLinesEx(label_bounds, 1, rl.ColorAlpha(rl.GREEN, 0.3))
            rl.DrawRectangleLinesEx(z_input.rect, 1, rl.ColorAlpha(rl.RED, 0.3))
            
            text_marker_size :: 4
            rl.DrawRectangle(
                i32(z_input.text_pos.x) - text_marker_size/2,
                i32(z_input.text_pos.y) - text_marker_size/2,
                text_marker_size,
                text_marker_size,
                rl.ColorAlpha(rl.BLUE, 0.5),
            )
            
            debug_info := fmt.tprintf("active:%v buf:%s", state.input.active_input == .Z, string(state.input.input_buffers[1][:]))
            rl.DrawText(strings.clone_to_cstring(debug_info), i32(z_input.rect.x), i32(z_input.rect.y - 12), 10, rl.ColorAlpha(rl.WHITE, 0.5))
        }
        
        draw_outlined_text(state.font, "STARTING DIMENSION:", rl.Vector2{20, overworld_button.rect.y - state.layout.spacing}, state.font_size, 1)
        
        // Debug visualization for dimension section header
        if state.debug_view {
            header_bounds := rl.Rectangle{20, overworld_button.rect.y - state.layout.spacing, 200, state.font_size + 4}
            rl.DrawRectangleLinesEx(header_bounds, 1, rl.ColorAlpha(rl.YELLOW, 0.3))
        }
        
        overworld_color := rl.ColorAlpha(
            state.coordinates.source_dimension == Dimension.Overworld ? rl.SKYBLUE : rl.DARKGRAY,
            0.7,
        )
        if state.input.active_input == .Dimension && state.coordinates.source_dimension == Dimension.Overworld {
            overworld_color = rl.ColorAlpha(rl.BLUE, 0.7)
        }
        rl.DrawRectangleRec(overworld_button.rect, overworld_color)
        draw_outlined_text(state.font, "OVERWORLD", rl.Vector2{overworld_button.text_pos.x, overworld_button.text_pos.y}, state.font_size, 1)
        
        // Debug visualization for Overworld button
        if state.debug_view {
            rl.DrawRectangleLinesEx(overworld_button.rect, 1, rl.ColorAlpha(rl.RED, 0.3))
            text_bounds := rl.Rectangle{
                overworld_button.text_pos.x,
                overworld_button.text_pos.y,
                100,  // Approximate text width
                state.font_size,
            }
            rl.DrawRectangleLinesEx(text_bounds, 1, rl.ColorAlpha(rl.GREEN, 0.3))
            
            debug_info := fmt.tprintf("active:%v sel:%v", 
                state.input.active_input == .Dimension,
                state.coordinates.source_dimension == .Overworld,
            )
            rl.DrawText(
                strings.clone_to_cstring(debug_info),
                i32(overworld_button.rect.x),
                i32(overworld_button.rect.y - 12),
                10,
                rl.ColorAlpha(rl.WHITE, 0.5),
            )
        }
        
        nether_color := rl.ColorAlpha(
            state.coordinates.source_dimension == Dimension.Nether ? rl.SKYBLUE : rl.DARKGRAY,
            0.7,
        )
        if state.input.active_input == .Dimension && state.coordinates.source_dimension == Dimension.Nether {
            nether_color = rl.ColorAlpha(rl.BLUE, 0.7)
        }
        rl.DrawRectangleRec(nether_button.rect, nether_color)
        draw_outlined_text(state.font, "NETHER", rl.Vector2{nether_button.text_pos.x, nether_button.text_pos.y}, state.font_size, 1)
        
        // Debug visualization for Nether button
        if state.debug_view {
            rl.DrawRectangleLinesEx(nether_button.rect, 1, rl.ColorAlpha(rl.RED, 0.3))
            text_bounds := rl.Rectangle{
                nether_button.text_pos.x,
                nether_button.text_pos.y,
                80,  // Approximate text width
                state.font_size,
            }
            rl.DrawRectangleLinesEx(text_bounds, 1, rl.ColorAlpha(rl.GREEN, 0.3))
            
            debug_info := fmt.tprintf("active:%v sel:%v", 
                state.input.active_input == .Dimension,
                state.coordinates.source_dimension == .Nether,
            )
            rl.DrawText(
                strings.clone_to_cstring(debug_info),
                i32(nether_button.rect.x),
                i32(nether_button.rect.y - 12),
                10,
                rl.ColorAlpha(rl.WHITE, 0.5),
            )
        }
        
        // Create reusable buffers for text
        coord_buffer: [32]u8
        feedback_buffer: [32]u8
        
        // Convert coordinates to string
        coord_text := fmt.bprintf(coord_buffer[:], "X: %d, Z: %d", 
            state.coordinates.converted.x, state.coordinates.converted.z)
        
        draw_outlined_text(
            state.font,
            strings.clone_to_cstring(coord_text),
            rl.Vector2{converted_coords.text_pos.x, converted_coords.text_pos.y},
            state.font_size * 1.2,
            1,
        )

        if state.clipboard.last_copied > 0 {
            feedback_text := fmt.bprintf(feedback_buffer[:], "Copied!")
            feedback_pos := rl.Vector2{converted_coords.text_pos.x + 200, converted_coords.text_pos.y}
            rl.DrawTextEx(
                state.font,
                strings.clone_to_cstring(feedback_text),
                feedback_pos,
                state.font_size,
                1,
                rl.GREEN,
            )
        }

        if state.debug_view {
            // Draw wave parameters debug info along right margin
            margin := f32(20)  // Distance from right edge
            line_height := f32(20)  // Height between lines
            start_y := f32(100)     // Starting Y position
            text_size := i32(16)    // Text size
            
            params := []struct{name: string, value: f32}{
                {"Noise Scale", state.title.digital_noise_params.noise_scale},
                {"Glitch Intensity", state.title.digital_noise_params.glitch_intensity},
                {"Scan Line Density", state.title.digital_noise_params.scan_line_density},
                {"Tear Frequency", state.title.digital_noise_params.tear_frequency},
                {"RGB Split Amount", state.title.digital_noise_params.rgb_split_amount},
                {"Static Amount", state.title.digital_noise_params.static_amount},
                {"Pulse Speed", state.title.digital_noise_params.pulse_speed},
                {"Pulse Intensity", state.title.digital_noise_params.pulse_intensity},
            }
            
            // Draw background panel
            panel_padding := f32(10)
            max_text_width := f32(200)  // Adjust based on your needs
            panel_rect := rl.Rectangle{
                f32(state.window_width) - max_text_width - margin - panel_padding,
                start_y - panel_padding,
                max_text_width + panel_padding * 2,
                f32(len(params)) * line_height + panel_padding * 2,
            }
            rl.DrawRectangleRec(panel_rect, rl.ColorAlpha(rl.BLACK, 0.7))
            rl.DrawRectangleLinesEx(panel_rect, 1, rl.ColorAlpha(rl.WHITE, 0.3))
            
            // Draw title
            title_text := "Shader Parameters"
            title_pos_x := f32(state.window_width) - max_text_width - margin + panel_padding
            rl.DrawText(strings.clone_to_cstring(title_text), i32(title_pos_x), i32(start_y), text_size, rl.ColorAlpha(rl.WHITE, 0.8))
            
            // Draw parameters
            for param, idx in params {
                y_pos := start_y + f32(idx + 1) * line_height
                text := fmt.tprintf("%s: %.3f", param.name, param.value)
                text_pos_x := f32(state.window_width) - max_text_width - margin + panel_padding
                rl.DrawText(
                    strings.clone_to_cstring(text),
                    i32(text_pos_x),
                    i32(y_pos),
                    text_size,
                    rl.ColorAlpha(rl.WHITE, 0.8),
                )
                
                // Draw key hints
                key_hint := ""
                if param.name == "Noise Scale" {
                    key_hint = "Ctrl + Q/A"
                } else if param.name == "Glitch Intensity" {
                    key_hint = "Ctrl + W/S"
                } else if param.name == "Scan Line Density" {
                    key_hint = "Ctrl + E/D"
                } else if param.name == "Tear Frequency" {
                    key_hint = "Ctrl + R/F"
                } else if param.name == "RGB Split Amount" {
                    key_hint = "Ctrl + T/G"
                } else if param.name == "Static Amount" {
                    key_hint = "Ctrl + Y/H"
                } else if param.name == "Pulse Speed" {
                    key_hint = "Ctrl + U/J"
                } else if param.name == "Pulse Intensity" {
                    key_hint = "Ctrl + I/K"
                }
                hint_pos_x := f32(state.window_width) - f32(rl.MeasureText(strings.clone_to_cstring(key_hint), text_size)) - margin
                rl.DrawText(
                    strings.clone_to_cstring(key_hint),
                    i32(hint_pos_x),
                    i32(y_pos),
                    text_size,
                    rl.ColorAlpha(rl.GRAY, 0.6),
                )
            }
        }

        // Handle save/load operations
        if rl.IsKeyDown(.LEFT_CONTROL) && rl.IsKeyDown(.LEFT_SHIFT) {
            // Manual save with Ctrl+Shift+S
            if rl.IsKeyPressed(.S) {
                if cleanup_temp_files() {
                    if save_state_temp(&state) {
                        if save_state_final(&state) {
                            fmt.println("* State saved successfully")
                            state.state_tracking.has_unsaved_changes = false
                            state.state_tracking.last_auto_save = rl.GetTime()
                        } else {
                            fmt.eprintln("! Failed to finalize state save")
                        }
                    } else {
                        fmt.eprintln("! Failed to save state to temporary file")
                    }
                } else {
                    fmt.eprintln("! Failed to clean up temporary files")
                }
            }

            // Manual load with Ctrl+Shift+L
            if rl.IsKeyPressed(.L) {
                if load_state(&state) {
                    fmt.println("* State loaded successfully")
                    state.state_tracking.has_unsaved_changes = false
                    state.state_tracking.last_auto_save = rl.GetTime()
                } else {
                    fmt.eprintln("! Failed to load state")
                }
            }
        }

        // Check for state changes that need auto-saving
        if state.state_tracking.has_unsaved_changes && 
           state.settings.auto_save && 
           rl.GetTime() - state.state_tracking.last_auto_save >= state.state_tracking.auto_save_interval {
            if cleanup_temp_files() {
                if save_state_temp(&state) {
                    if save_state_final(&state) {
                        fmt.println("* Auto-saved state")
                        state.state_tracking.has_unsaved_changes = false
                        state.state_tracking.last_auto_save = rl.GetTime()
                    }
                }
            }
        }

        // Debug visualization
        if state.debug_view {
            // Create a single reusable buffer for all debug text
            debug_text: [256]u8
            
            // Title debug info
            title_text := fmt.bprintf(debug_text[:], "Title Texture: %dx%d", 
                state.title.texture.width, state.title.texture.height)
            rl.DrawText(strings.clone_to_cstring(title_text), 10, 10, 20, rl.RED)
            
            // Input section debug info
            input_text := fmt.bprintf(debug_text[:], "Input: %s", 
                state.input.active_input == .X ? "X" : state.input.active_input == .Z ? "Z" : "None")
            rl.DrawText(strings.clone_to_cstring(input_text), 10, 40, 20, rl.RED)
            
            // Wave parameters debug info
            wave_text := fmt.bprintf(debug_text[:], "Wave: Scale=%.2f Intensity=%.2f Scan Line Density=%.2f Tear Frequency=%.2f", 
                state.title.digital_noise_params.noise_scale,
                state.title.digital_noise_params.glitch_intensity,
                state.title.digital_noise_params.scan_line_density,
                state.title.digital_noise_params.tear_frequency)
            rl.DrawText(strings.clone_to_cstring(wave_text), 10, 70, 20, rl.RED)
        }

        // Update clipboard hover state
        state.clipboard.hovered = rl.CheckCollisionPointRec(mouse_pos, converted_coords.rect)
    }

    // Cleanup and final save on exit
    defer {
        // Always try to save on exit, regardless of auto-save setting
        if cleanup_temp_files() {
            if save_state_temp(&state) {
                if save_state_final(&state) {
                    fmt.println("* Final state save successful")
                } else {
                    fmt.eprintln("! Failed to finalize final state save")
                }
            } else {
                fmt.eprintln("! Failed to create temporary file for final save")
            }
        } else {
            fmt.eprintln("! Failed to clean up temporary files during exit")
        }
    }
}
