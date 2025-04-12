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
    ui_state: UIState,
    debug_view: bool,  // Toggle for debug visualization
}

TitleImage :: struct {
    texture: rl.Texture2D,
    char_width: i32,
    char_height: i32,
    chars: [10]rl.Rectangle, // 9 letters + 1 empty
    padding: f32,
    hover_state: struct {
        index: i32,
        time: f32,
        rotation: [9]f32,
        scale: [9]f32,
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
        debug_view = false,  // Debug visualization off by default
    }
    
    init_input_state(&state.input)
    
    bg, ok := load_background_image("assets/tree-house.png", state.window_width, state.window_height)
    if ok {
        state.background = bg
    } else {
        fmt.eprintln("Failed to load background image")
    }

    // Load title image
    title_img := rl.LoadImage(strings.clone_to_cstring("assets/title.png"))
    if title_img.data == nil {
        fmt.eprintln("Failed to load title image")
    } else {
        state.title.texture = rl.LoadTextureFromImage(title_img)
        state.title.char_width = 32
        state.title.char_height = 32
        state.title.padding = 0
        
        // Initialize character rectangles - each sprite is 32x32
        for i in 0..<10 {
            state.title.chars[i] = rl.Rectangle{
                x = f32(i32(i) * state.title.char_width),
                y = 0,
                width = f32(state.title.char_width),
                height = f32(state.title.char_height),
            }
        }
        
        // Print texture dimensions for debugging
        fmt.println("Title texture dimensions:", title_img.width, "x", title_img.height)
        
        // Initialize hover state
        state.title.hover_state.index = -1
        state.title.hover_state.time = 0
        for i in 0..<9 {
            state.title.hover_state.rotation[i] = 0
            state.title.hover_state.scale[i] = 1.0
        }
        
        rl.UnloadImage(title_img)
    }
    
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

main :: proc() {
    rl.InitWindow(WINDOW_DEFAULT_FLAGS.width, WINDOW_DEFAULT_FLAGS.height, strings.clone_to_cstring(WINDOW_DEFAULT_FLAGS.title))
    defer rl.CloseWindow()

    rl.SetTargetFPS(60)

    state := init_app()
    defer {
        rl.UnloadFont(state.font)
        rl.UnloadTexture(state.title.texture)
        delete(state.input.key_states)
    }
    
    layout := DEFAULT_LAYOUT
    
    x_input := make_input_box(layout, Position{20, 140}, "X:", state.font, state.font_size, 1)
    z_input := make_input_box(layout, Position{20, 140 + layout.section_spacing}, "Z:", state.font, state.font_size, 1)
    overworld_button, nether_button := make_dimension_buttons(layout, Position{20, 140 + 2*layout.section_spacing + layout.spacing})

    for !rl.WindowShouldClose() {
        if rl.IsMouseButtonPressed(.LEFT) {
        mouse_pos := rl.GetMousePosition()
            handled_click := false
            
            if rl.CheckCollisionPointRec(mouse_pos, overworld_button.rect) {
                if state.input.active_input != .Dimension || state.coordinates.source_dimension != Dimension.Overworld {
                    fmt.println("State change: Clicked Overworld button")
                    state.input.active_input = .Dimension
                    state.coordinates.source_dimension = Dimension.Overworld
                    state.coordinates.needs_conversion = true
                }
                handled_click = true
            } else if rl.CheckCollisionPointRec(mouse_pos, nether_button.rect) {
                if state.input.active_input != .Dimension || state.coordinates.source_dimension != Dimension.Nether {
                    fmt.println("State change: Clicked Nether button")
                    state.input.active_input = .Dimension
                    state.coordinates.source_dimension = Dimension.Nether
                    state.coordinates.needs_conversion = true
                }
                handled_click = true
            }
            
            if !handled_click && rl.CheckCollisionPointRec(mouse_pos, x_input.rect) {
                if state.input.active_input != .X {
                    fmt.println("State change: Clicked X input")
                    state.input.active_input = .X
                    state.input.should_clear = true
                }
                handled_click = true
            } else if !handled_click && rl.CheckCollisionPointRec(mouse_pos, z_input.rect) {
                if state.input.active_input != .Z {
                    fmt.println("State change: Clicked Z input")
                    state.input.active_input = .Z
                    state.input.should_clear = true
                }
                handled_click = true
            } else if !handled_click && state.clipboard.hovered {
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
            update_coordinates_from_input(&state.input, &state.coordinates)
        }

        if state.input.active_input == .X || state.input.active_input == .Z {
            if rl.IsKeyPressed(.ENTER) || rl.IsKeyPressed(.TAB) || rl.IsKeyPressed(.BACKSPACE) || 
               (rl.IsKeyPressed(.ZERO) || rl.IsKeyPressed(.ONE) || rl.IsKeyPressed(.TWO) || 
                rl.IsKeyPressed(.THREE) || rl.IsKeyPressed(.FOUR) || rl.IsKeyPressed(.FIVE) || 
                rl.IsKeyPressed(.SIX) || rl.IsKeyPressed(.SEVEN) || rl.IsKeyPressed(.EIGHT) || 
                rl.IsKeyPressed(.NINE) || rl.IsKeyPressed(.MINUS)) {
                update_coordinates_from_input(&state.input, &state.coordinates)
            }
        }

        if state.input.needs_dimension_toggle {
            state.coordinates.source_dimension = state.coordinates.source_dimension == Dimension.Overworld ? Dimension.Nether : Dimension.Overworld
            state.coordinates.needs_conversion = true
            state.input.needs_dimension_toggle = false
        }

        converted_pos := rl.Vector2{DEFAULT_LAYOUT.margin, f32(state.window_height/2) + 50}
        converted_rect := rl.Rectangle{converted_pos.x, converted_pos.y, 200, state.font_size * 2}

        mouse_pos := rl.GetMousePosition()
        state.clipboard.hovered = rl.CheckCollisionPointRec(mouse_pos, converted_rect)

        if state.clipboard.last_copied > 0 {
            state.clipboard.last_copied -= rl.GetFrameTime()
        }

        if state.coordinates.needs_conversion {
            fmt.println("Attempting conversion")
            get_converted_coordinates(&state.coordinates)
        }

        // Update title hover state
        title_scale: f32 = 1.2
        base_width := f32(state.title.char_width) * title_scale
        base_height := f32(state.title.char_height) * title_scale
        total_width := base_width * 9  // 9 letters
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
            
            // Draw the actual sprite
            origin := rl.Vector2{
                f32(state.title.char_width)/2,  // 16 pixels (half of 32)
                f32(state.title.char_height)/2,  // 16 pixels (half of 32)
            }
            rl.DrawTexturePro(
                state.title.texture,
                src_rect,
                dest_rect,
                origin,
                state.title.hover_state.rotation[i],
                rl.ColorAlpha(rl.WHITE, 1.0),
            )
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
        
        draw_outlined_text(state.font, "STARTING DIMENSION:", rl.Vector2{20, overworld_button.rect.y - layout.spacing}, state.font_size, 1)
        
        // Debug visualization for dimension section header
        if state.debug_view {
            header_bounds := rl.Rectangle{20, overworld_button.rect.y - layout.spacing, 200, state.font_size + 4}
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
        
        coord_text := fmt.tprintf("X: %d, Z: %d", state.coordinates.converted.x, state.coordinates.converted.z)
        
        draw_outlined_text(
            state.font,
            strings.clone_to_cstring(coord_text),
            converted_pos,
            state.font_size * 1.2,  // 20% larger font
            1,
            1,  // Outline thickness
        )
        
        // Debug visualization for converted coordinates
        if state.debug_view {
            rl.DrawRectangleLinesEx(converted_rect, 1, rl.ColorAlpha(rl.RED, 0.3))
            debug_info := fmt.tprintf("hover:%v copy_time:%.1f", state.clipboard.hovered, state.clipboard.last_copied)
            rl.DrawText(
                strings.clone_to_cstring(debug_info),
                i32(converted_rect.x),
                i32(converted_rect.y - 12),
                10,
                rl.ColorAlpha(rl.WHITE, 0.5),
            )
        }

        if state.clipboard.last_copied > 0 {
            feedback_text := "Copied!"
            feedback_pos := rl.Vector2{converted_pos.x + 200, converted_pos.y}
            rl.DrawTextEx(
                state.font,
                strings.clone_to_cstring(feedback_text),
                feedback_pos,
                state.font_size,
                1,
                rl.GREEN,
            )
            
            // Debug visualization for copy feedback
            if state.debug_view {
                feedback_bounds := rl.Rectangle{
                    feedback_pos.x,
                    feedback_pos.y,
                    70,  // Approximate text width
                    state.font_size,
                }
                rl.DrawRectangleLinesEx(feedback_bounds, 1, rl.ColorAlpha(rl.GREEN, 0.3))
            }
        }
    }
}
