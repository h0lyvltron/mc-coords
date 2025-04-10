package main

import "core:fmt"
import "core:strings"
import "core:os"
import rl "vendor:raylib"

UIElement_ID :: distinct int

UIElementState :: struct {
    bounds: rl.Rectangle,
    is_active: bool,
    is_visible: bool,
    is_hovered: bool,
}

UIState :: struct {
    elements: map[UIElement_ID]UIElementState,
    active_element: UIElement_ID,
    previous_element: UIElement_ID,
    modal_state: Modal_State,
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

FontSettings :: struct {
    font: rl.Font,
    size: f32,
    spacing: f32,
    title_size: f32,
}

DEFAULT_FONT_SETTINGS := FontSettings {
    font = rl.GetFontDefault(),
    size = 20.0,
    spacing = 0.5,
    title_size = 24.0,
}

load_font_with_fallback :: proc() -> rl.Font {
    font_paths := []string{
        "assets/fonts/MinecraftTen-VGORe.ttf",
        "./assets/fonts/MinecraftTen-VGORe.ttf",
        "C:/Windows/Fonts/MinecraftTen-VGORe.ttf",
    }

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

    for path in font_paths {
        if os.exists(path) {
            font := rl.LoadFont(strings.clone_to_cstring(path))
            if font.texture.id != 0 && rl.GetGlyphIndex(font, 'A') != 0 {
                fmt.println("Loaded Minecraft font from:", path)
                return font
            }
            rl.UnloadFont(font)
        }
    }

    consolas := rl.LoadFont(strings.clone_to_cstring("C:/Windows/Fonts/consola.ttf"))
    if consolas.texture.id != 0 && rl.GetGlyphIndex(consolas, 'A') != 0 {
        fmt.println("Using Consolas as fallback font")
        return consolas
    }

    fmt.println("Using default raylib font")
    return rl.GetFontDefault()
}

draw_outlined_text :: proc(font: rl.Font, text: cstring, position: rl.Vector2, font_size: f32, spacing: f32, thickness: f32 = 1) {
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
    
    rl.DrawTextEx(font, text, position, font_size, spacing, rl.BLACK)
}
