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
    clipboard: struct {
        hovered: bool,
        last_copied: f32,
    },
    // Future enhancements
    locations: LocationDatabase,
    settings: Settings,
    ui_state: UIState,
}

init_app :: proc() -> AppState {
    state := AppState {
        window_width = WINDOW_DEFAULT_FLAGS.width,
        window_height = WINDOW_DEFAULT_FLAGS.height,
        font = load_font_with_fallback(),
        font_size = DEFAULT_FONT_SETTINGS.size,
        coordinates = init_coordinate_state(),
        help_visible = false,
    }
    
    init_input_state(&state.input)
    
    bg, ok := load_background_image("assets/tree-house.png", state.window_width, state.window_height)
    if ok {
        state.background = bg
    } else {
        fmt.eprintln("Failed to load background image")
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
        
        title_width := rl.MeasureTextEx(state.font, strings.clone_to_cstring(WINDOW_DEFAULT_FLAGS.title), state.font_size * 1.5, 1).x
        title_x := f32(state.window_width/2) - title_width/2
        draw_outlined_text(state.font, strings.clone_to_cstring(WINDOW_DEFAULT_FLAGS.title), rl.Vector2{title_x, 30}, state.font_size * 1.5, 1)
        
        draw_outlined_text(state.font, "INPUT COORDINATES:", rl.Vector2{20, 95}, state.font_size, 1)
        
        draw_outlined_text(state.font, "X:", rl.Vector2{x_input.label_pos.x, x_input.label_pos.y}, state.font_size, 1)
        x_box_color := rl.ColorAlpha(state.input.active_input == .X ? rl.BLUE : rl.DARKGRAY, state.input.active_input == .X ? 0.7 : 0.5)
        rl.DrawRectangleRec(x_input.rect, x_box_color)
        draw_outlined_text(state.font, strings.clone_to_cstring(string(state.input.input_buffers[0][:])), rl.Vector2{x_input.text_pos.x, x_input.text_pos.y}, state.font_size, 1)
        
        draw_outlined_text(state.font, "Z:", rl.Vector2{z_input.label_pos.x, z_input.label_pos.y}, state.font_size, 1)
        z_box_color := rl.ColorAlpha(state.input.active_input == .Z ? rl.BLUE : rl.DARKGRAY, state.input.active_input == .Z ? 0.7 : 0.5)
        rl.DrawRectangleRec(z_input.rect, z_box_color)
        draw_outlined_text(state.font, strings.clone_to_cstring(string(state.input.input_buffers[1][:])), rl.Vector2{z_input.text_pos.x, z_input.text_pos.y}, state.font_size, 1)
        
        draw_outlined_text(state.font, "STARTING DIMENSION:", rl.Vector2{20, overworld_button.rect.y - layout.spacing}, state.font_size, 1)
        
        overworld_color := rl.ColorAlpha(
            state.coordinates.source_dimension == Dimension.Overworld ? rl.SKYBLUE : rl.DARKGRAY,
            0.7,
        )
        if state.input.active_input == .Dimension && state.coordinates.source_dimension == Dimension.Overworld {
            overworld_color = rl.ColorAlpha(rl.BLUE, 0.7)
        }
        rl.DrawRectangleRec(overworld_button.rect, overworld_color)
        draw_outlined_text(state.font, "OVERWORLD", rl.Vector2{overworld_button.text_pos.x, overworld_button.text_pos.y}, state.font_size, 1)
        
        nether_color := rl.ColorAlpha(
            state.coordinates.source_dimension == Dimension.Nether ? rl.SKYBLUE : rl.DARKGRAY,
            0.7,
        )
        if state.input.active_input == .Dimension && state.coordinates.source_dimension == Dimension.Nether {
            nether_color = rl.ColorAlpha(rl.BLUE, 0.7)
        }
        rl.DrawRectangleRec(nether_button.rect, nether_color)
        draw_outlined_text(state.font, "NETHER", rl.Vector2{nether_button.text_pos.x, nether_button.text_pos.y}, state.font_size, 1)
        coord_text := fmt.tprintf("X: %d, Z: %d", state.coordinates.converted.x, state.coordinates.converted.z)
        
        draw_outlined_text(
            state.font,
            strings.clone_to_cstring(coord_text),
            converted_pos,
            state.font_size * 1.2,  // 20% larger font
            1,
            1,  // Outline thickness
        )

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
        }
    }
}
