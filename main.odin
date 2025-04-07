package main

import "core:fmt"
import "core:mem"
import "core:strings"
import "core:strconv"
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

DEFAULT_WINDOW_FLAGS := WindowDefaultFlags {
    title = "Minecraft Coordinate Converter",
    width = 360,
    height = 360,
    pos_x = 100,
    pos_y = 100,
}

DEFAULT_FONT_SETTINGS := FontSettings {
    font = rl.GetFontDefault(),
    size = 16.0,
    spacing = 0.0,
    title_size = 20.0,
}

main :: proc() {

    rl.InitWindow(DEFAULT_WINDOW_FLAGS.width, DEFAULT_WINDOW_FLAGS.height, strings.clone_to_cstring(DEFAULT_WINDOW_FLAGS.title))
    defer rl.CloseWindow()

    rl.SetTargetFPS(60)

    font_settings := DEFAULT_FONT_SETTINGS
    font_settings.font = rl.LoadFont(strings.clone_to_cstring("C:\\Windows\\Fonts\\consola.ttf"))
    defer rl.UnloadFont(font_settings.font)

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

        mouse_pos := rl.GetMousePosition()
        
        if rl.IsMouseButtonPressed(rl.MouseButton.LEFT) {

            if rl.CheckCollisionPointRec(mouse_pos, rl.Rectangle{30, f32(60), 140, 20}) {
                state.active_input = 1
                state.field_just_focused = true
            } else if rl.CheckCollisionPointRec(mouse_pos, rl.Rectangle{30, f32(90), 140, 20}) {

                state.active_input = 2
                state.field_just_focused = true
            } else if rl.CheckCollisionPointRec(mouse_pos, rl.Rectangle{10, f32(140), 80, 25}) {

                state.current_dimension = conversion.Dimension.Overworld
                state.active_input = 0
            } else if rl.CheckCollisionPointRec(mouse_pos, rl.Rectangle{90, f32(140), 80, 25}) {

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

        y_offset: i32 = 10
        spacing: i32 = 30

        rl.DrawTextEx(font_settings.font, strings.clone_to_cstring(DEFAULT_WINDOW_FLAGS.title), rl.Vector2{10, f32(y_offset)}, font_settings.title_size, font_settings.spacing, rl.BLACK)
        y_offset += spacing

        rl.DrawTextEx(font_settings.font, strings.clone_to_cstring("Input Coordinates:"), rl.Vector2{10, f32(y_offset)}, font_settings.size, font_settings.spacing, rl.BLACK)
        y_offset += 20

        rl.DrawTextEx(font_settings.font, strings.clone_to_cstring("X:"), rl.Vector2{10, f32(y_offset)}, font_settings.size, font_settings.spacing, rl.BLACK)
        x_box_color := state.active_input == 1 ? rl.BLUE : rl.LIGHTGRAY
        rl.DrawRectangle(30, y_offset, 140, 20, x_box_color)
        rl.DrawTextEx(font_settings.font, strings.clone_to_cstring(string(state.input_x[:state.input_x_len])), rl.Vector2{35, f32(y_offset)}, font_settings.size, font_settings.spacing, rl.BLACK)
        y_offset += spacing

        rl.DrawTextEx(font_settings.font, strings.clone_to_cstring("Y:"), rl.Vector2{10, f32(y_offset)}, font_settings.size, font_settings.spacing, rl.BLACK)
        y_box_color := state.active_input == 2 ? rl.BLUE : rl.LIGHTGRAY
        rl.DrawRectangle(30, y_offset, 140, 20, y_box_color)
        rl.DrawTextEx(font_settings.font, strings.clone_to_cstring(string(state.input_y[:state.input_y_len])), rl.Vector2{35, f32(y_offset)}, font_settings.size, font_settings.spacing, rl.BLACK)
        y_offset += spacing

        rl.DrawTextEx(font_settings.font, strings.clone_to_cstring("Dimension:"), rl.Vector2{10, f32(y_offset)}, font_settings.size, font_settings.spacing, rl.BLACK)
        y_offset += 20

        overworld_rect := rl.Rectangle{10, f32(y_offset), 80, 25}
        overworld_color := state.current_dimension == conversion.Dimension.Overworld ? rl.BLUE : rl.GRAY
        if state.active_input == 3 {
            overworld_color = state.current_dimension == conversion.Dimension.Overworld ? rl.BLUE : rl.LIGHTGRAY
        }
        rl.DrawRectangleRec(overworld_rect, overworld_color)
        rl.DrawTextEx(font_settings.font, strings.clone_to_cstring("Overworld"), rl.Vector2{15, f32(y_offset + 5)}, font_settings.size, font_settings.spacing, rl.WHITE)

        nether_rect := rl.Rectangle{90, f32(y_offset), 80, 25}
        nether_color := state.current_dimension == conversion.Dimension.Nether ? rl.BLUE : rl.GRAY
        if state.active_input == 3 {
            nether_color = state.current_dimension == conversion.Dimension.Nether ? rl.BLUE : rl.LIGHTGRAY
        }
        rl.DrawRectangleRec(nether_rect, nether_color)
        rl.DrawTextEx(font_settings.font, strings.clone_to_cstring("Nether"), rl.Vector2{95, f32(y_offset + 5)}, font_settings.size, font_settings.spacing, rl.WHITE)
        y_offset += spacing

        rl.DrawTextEx(font_settings.font, strings.clone_to_cstring("Converted Coordinates:"), rl.Vector2{10, f32(y_offset)}, font_settings.size, font_settings.spacing, rl.BLACK)
        y_offset += 20

        target_dimension := state.current_dimension == conversion.Dimension.Overworld ? conversion.Dimension.Nether : conversion.Dimension.Overworld
        rl.DrawTextEx(font_settings.font, strings.clone_to_cstring(fmt.tprintf("X: %d", state.converted_x)), rl.Vector2{10, f32(y_offset)}, font_settings.size, font_settings.spacing, rl.BLACK)
        y_offset += 20
        rl.DrawTextEx(font_settings.font, strings.clone_to_cstring(fmt.tprintf("Y: %d", state.converted_y)), rl.Vector2{10, f32(y_offset)}, font_settings.size, font_settings.spacing, rl.BLACK)
        y_offset += 20
        rl.DrawTextEx(font_settings.font, strings.clone_to_cstring(fmt.tprintf("Dimension: %v", target_dimension)), rl.Vector2{10, f32(y_offset)}, font_settings.size, font_settings.spacing, rl.BLACK)
    }
}
