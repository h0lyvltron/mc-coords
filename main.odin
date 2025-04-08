package main

import "core:fmt"
import "core:mem"
import "core:strings"
import "core:strconv"
import "core:os"
import "conversion"
import rl "vendor:raylib"

AppState :: struct {
    input_x: [32]u8,
    input_y: [32]u8,
    input_x_len: int,
    input_y_len: int,
    current_dimension: conversion.Dimension,
    converted_x: i32,
    converted_y: i32,
    active_input: int, // 0 = none, 1 = x, 2 = y, 3 = dimension
    backspace_held_time: f32,
    delete_held_time: f32,
    field_just_focused: bool,
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
    title = "Minecraft Coordinate Manager",
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

main :: proc() {
    // Initialize window
    rl.InitWindow(DEFAULT_WINDOW_FLAGS.width, DEFAULT_WINDOW_FLAGS.height, strings.clone_to_cstring(DEFAULT_WINDOW_FLAGS.title))
    defer rl.CloseWindow()

    // Set target FPS
    rl.SetTargetFPS(60)

    // Initialize font settings with improved font loading
    font_settings := DEFAULT_FONT_SETTINGS
    font_settings.font = load_font_with_fallback()
    defer rl.UnloadFont(font_settings.font)

    // Initialize layout
    layout := DEFAULT_LAYOUT

    // Initialize UI elements
    x_input := make_input_box(layout, Position{20, 140}, "X:", font_settings.font, font_settings.size, font_settings.spacing)
    y_input := make_input_box(layout, Position{20, 140 + layout.section_spacing}, "Y:", font_settings.font, font_settings.size, font_settings.spacing)
    overworld_button, nether_button := make_dimension_buttons(layout, Position{20, 140 + 2*layout.section_spacing + layout.spacing})

    // Initialize app state
    state := AppState {
        current_dimension = conversion.Dimension.Overworld,
        input_x = {0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0},
        input_y = {0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0},
        input_x_len = 0,
        input_y_len = 0,
        active_input = 0,
    }
    copy(state.input_x[:], "0")
    copy(state.input_y[:], "0")
    state.input_x_len = len("0")
    state.input_y_len = len("0")

    // Main loop
    for !rl.WindowShouldClose() {
        // Update
        mouse_pos := rl.GetMousePosition()
        
        // Handle mouse input for text boxes
        if rl.IsMouseButtonPressed(rl.MouseButton.LEFT) {
            if rl.CheckCollisionPointRec(mouse_pos, x_input.rect) {
                state.active_input = 1
                state.field_just_focused = true
            } else if rl.CheckCollisionPointRec(mouse_pos, y_input.rect) {
                state.active_input = 2
                state.field_just_focused = true
            } else if rl.CheckCollisionPointRec(mouse_pos, overworld_button.rect) {
                state.current_dimension = conversion.Dimension.Overworld
                state.active_input = 0
            } else if rl.CheckCollisionPointRec(mouse_pos, nether_button.rect) {
                state.current_dimension = conversion.Dimension.Nether
                state.active_input = 0
            } else {
                state.active_input = 0
            }
        }

        // Handle keyboard input
        if state.active_input > 0 {
            key := rl.GetCharPressed()
            for key > 0 {
                if state.active_input == 1 {
                    if state.field_just_focused {
                        state.input_x_len = 0
                        state.field_just_focused = false
                    }
                    if (key >= '0' && key <= '9') || (key == '-' && state.input_x_len == 0) {
                        if state.input_x_len < 31 {
                            state.input_x[state.input_x_len] = cast(u8)key
                            state.input_x_len += 1
                        }
                    }
                } else if state.active_input == 2 {
                    if state.field_just_focused {
                        state.input_y_len = 0
                        state.field_just_focused = false
                    }
                    if (key >= '0' && key <= '9') || (key == '-' && state.input_y_len == 0) {
                        if state.input_y_len < 31 {
                            state.input_y[state.input_y_len] = cast(u8)key
                            state.input_y_len += 1
                        }
                    }
                }
                key = rl.GetCharPressed()
            }

            frame_time := rl.GetFrameTime()
            
            if rl.IsKeyDown(rl.KeyboardKey.BACKSPACE) {
                state.backspace_held_time += frame_time
                if rl.IsKeyPressed(rl.KeyboardKey.BACKSPACE) || state.backspace_held_time >= 0.5 {
                    repeat_intervals := cast(i32)((state.backspace_held_time - 0.5) / 0.05)
                    if repeat_intervals > 0 || rl.IsKeyPressed(rl.KeyboardKey.BACKSPACE) {
                        if state.active_input == 1 && state.input_x_len > 0 {
                            state.input_x_len -= 1
                        } else if state.active_input == 2 && state.input_y_len > 0 {
                            state.input_y_len -= 1
                        }
                        state.backspace_held_time = 0.5 + f32(repeat_intervals) * 0.05
                    }
                }
            } else {
                state.backspace_held_time = 0
            }

            if rl.IsKeyDown(rl.KeyboardKey.DELETE) {
                state.delete_held_time += frame_time
                if rl.IsKeyPressed(rl.KeyboardKey.DELETE) || state.delete_held_time >= 0.5 {
                    repeat_intervals := cast(i32)((state.delete_held_time - 0.5) / 0.05)
                    if repeat_intervals > 0 || rl.IsKeyPressed(rl.KeyboardKey.DELETE) {
                        if state.active_input == 1 && state.input_x_len > 0 {
                            for i in 0..<state.input_x_len-1 {
                                state.input_x[i] = state.input_x[i+1]
                            }
                            state.input_x_len -= 1
                        } else if state.active_input == 2 && state.input_y_len > 0 {
                            for i in 0..<state.input_y_len-1 {
                                state.input_y[i] = state.input_y[i+1]
                            }
                            state.input_y_len -= 1
                        }
                        state.delete_held_time = 0.5 + f32(repeat_intervals) * 0.05
                    }
                }
            } else {
                state.delete_held_time = 0
            }
        }

        if rl.IsKeyPressed(rl.KeyboardKey.TAB) {
            if state.active_input == 0 {
                state.active_input = 1
                state.field_just_focused = true
            } else if rl.IsKeyDown(rl.KeyboardKey.LEFT_SHIFT) || rl.IsKeyDown(rl.KeyboardKey.RIGHT_SHIFT) {
                state.active_input = state.active_input == 1 ? 3 : state.active_input - 1
                state.field_just_focused = true
            } else {
                state.active_input = state.active_input == 3 ? 1 : state.active_input + 1
                state.field_just_focused = true
            }
        }

        if state.active_input == 3 {
            if rl.IsKeyPressed(rl.KeyboardKey.SPACE) {
                state.current_dimension = state.current_dimension == conversion.Dimension.Overworld ? conversion.Dimension.Nether : conversion.Dimension.Overworld
            } else if rl.IsKeyPressed(rl.KeyboardKey.RIGHT) && state.current_dimension == conversion.Dimension.Overworld {
                state.current_dimension = conversion.Dimension.Nether
            } else if rl.IsKeyPressed(rl.KeyboardKey.LEFT) && state.current_dimension == conversion.Dimension.Nether {
                state.current_dimension = conversion.Dimension.Overworld
            }
        }

        if rl.IsKeyPressed(rl.KeyboardKey.ENTER) {
            target_dimension := state.current_dimension == conversion.Dimension.Overworld ? conversion.Dimension.Nether : conversion.Dimension.Overworld
            input_x_str := string(state.input_x[:state.input_x_len])
            input_y_str := string(state.input_y[:state.input_y_len])
            input_x, ok_x := strconv.parse_int(input_x_str)
            input_y, ok_y := strconv.parse_int(input_y_str)
            
            if ok_x && ok_y {
                state.converted_x = cast(i32)conversion.convert_between_dimensions(
                    input_x,
                    state.current_dimension,
                    target_dimension,
                )
                state.converted_y = cast(i32)conversion.convert_between_dimensions(
                    input_y,
                    state.current_dimension,
                    target_dimension,
                )
            }
        }

        // Draw
        rl.BeginDrawing()
        defer rl.EndDrawing()

        rl.ClearBackground(rl.RAYWHITE)

        // Title - centered horizontally
        title_width := rl.MeasureTextEx(font_settings.font, strings.clone_to_cstring(DEFAULT_WINDOW_FLAGS.title), font_settings.title_size, font_settings.spacing).x
        title_x := f32(DEFAULT_WINDOW_FLAGS.width/2) - title_width/2
        rl.DrawTextEx(font_settings.font, strings.clone_to_cstring(DEFAULT_WINDOW_FLAGS.title), rl.Vector2{title_x, 30}, font_settings.title_size, font_settings.spacing, rl.BLACK)

        // Input coordinates section
        rl.DrawTextEx(font_settings.font, strings.clone_to_cstring("INPUT COORDINATES:"), rl.Vector2{20, 95}, font_settings.size, font_settings.spacing, rl.BLACK)

        // X input
        rl.DrawTextEx(font_settings.font, strings.clone_to_cstring("X:"), rl.Vector2{x_input.label_pos.x, x_input.label_pos.y}, font_settings.size, font_settings.spacing, rl.BLACK)
        x_box_color := state.active_input == 1 ? rl.BLUE : rl.LIGHTGRAY
        rl.DrawRectangleRec(x_input.rect, x_box_color)
        rl.DrawTextEx(font_settings.font, strings.clone_to_cstring(string(state.input_x[:state.input_x_len])), rl.Vector2{x_input.text_pos.x, x_input.text_pos.y}, font_settings.size, font_settings.spacing, rl.BLACK)

        // Y input
        rl.DrawTextEx(font_settings.font, strings.clone_to_cstring("Y:"), rl.Vector2{y_input.label_pos.x, y_input.label_pos.y}, font_settings.size, font_settings.spacing, rl.BLACK)
        y_box_color := state.active_input == 2 ? rl.BLUE : rl.LIGHTGRAY
        rl.DrawRectangleRec(y_input.rect, y_box_color)
        rl.DrawTextEx(font_settings.font, strings.clone_to_cstring(string(state.input_y[:state.input_y_len])), rl.Vector2{y_input.text_pos.x, y_input.text_pos.y}, font_settings.size, font_settings.spacing, rl.BLACK)

        // Dimension selection
        rl.DrawTextEx(font_settings.font, strings.clone_to_cstring("STARTING DIMENSION:"), rl.Vector2{20, overworld_button.rect.y - layout.spacing}, font_settings.size, font_settings.spacing, rl.BLACK)

        // Overworld button
        overworld_color := state.current_dimension == conversion.Dimension.Overworld ? rl.BLUE : rl.GRAY
        if state.active_input == 3 {
            overworld_color = state.current_dimension == conversion.Dimension.Overworld ? rl.BLUE : rl.LIGHTGRAY
        }
        rl.DrawRectangleRec(overworld_button.rect, overworld_color)
        rl.DrawTextEx(font_settings.font, strings.clone_to_cstring("OVERWORLD"), rl.Vector2{overworld_button.text_pos.x, overworld_button.text_pos.y}, font_settings.size, font_settings.spacing, rl.WHITE)

        // Nether button
        nether_color := state.current_dimension == conversion.Dimension.Nether ? rl.BLUE : rl.GRAY
        if state.active_input == 3 {
            nether_color = state.current_dimension == conversion.Dimension.Nether ? rl.BLUE : rl.LIGHTGRAY
        }
        rl.DrawRectangleRec(nether_button.rect, nether_color)
        rl.DrawTextEx(font_settings.font, strings.clone_to_cstring("NETHER"), rl.Vector2{nether_button.text_pos.x, nether_button.text_pos.y}, font_settings.size, font_settings.spacing, rl.WHITE)

        // Converted coordinates section
        converted_y := overworld_button.rect.y + layout.dimension_button.height + layout.section_spacing
        rl.DrawTextEx(font_settings.font, strings.clone_to_cstring("CONVERTED COORDINATES:"), rl.Vector2{20, converted_y}, font_settings.size, font_settings.spacing, rl.BLACK)
        converted_y += layout.spacing

        target_dimension := state.current_dimension == conversion.Dimension.Overworld ? conversion.Dimension.Nether : conversion.Dimension.Overworld
        rl.DrawTextEx(font_settings.font, strings.clone_to_cstring(fmt.tprintf("X: %d", state.converted_x)), rl.Vector2{20, converted_y}, font_settings.size, font_settings.spacing, rl.BLACK)
        converted_y += layout.spacing
        rl.DrawTextEx(font_settings.font, strings.clone_to_cstring(fmt.tprintf("Y: %d", state.converted_y)), rl.Vector2{20, converted_y}, font_settings.size, font_settings.spacing, rl.BLACK)
        converted_y += layout.spacing
        rl.DrawTextEx(font_settings.font, strings.clone_to_cstring(fmt.tprintf("TARGET DIMENSION: %v", target_dimension)), rl.Vector2{20, converted_y}, font_settings.size, font_settings.spacing, rl.BLACK)
    }
}
