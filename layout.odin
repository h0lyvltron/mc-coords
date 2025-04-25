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

LayoutSection :: struct {
    id: string,
    rect: rl.Rectangle,
    content_height: f32,
    is_visible: bool,
    scroll_offset: f32,
    max_scroll: f32,
    elements: map[UIElement_ID]UIElementState,
    active_element: UIElement_ID,
    previous_element: UIElement_ID,
}

Layout :: struct {
    sections: [dynamic]LayoutSection,
    current_section: int,
    viewport: rl.Rectangle,
    scroll_speed: f32,
    is_scrolling: bool,
    last_mouse_y: f32,
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
    sections = make([dynamic]LayoutSection),
    current_section = 0,
    viewport = rl.Rectangle{},
    scroll_speed = 10.0,
    is_scrolling = false,
    last_mouse_y = 0,
    margin = 25,
    spacing = 40,
    section_spacing = 55,
    input_box = {
        width = 200,
        height = 32,
        text_padding = 10,
    },
    dimension_button = {
        width = 160,
        height = 40,
        text_padding = 10,
        gap = 15,
    },
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
        path_buf: [512]u8
        user_font_path := fmt.bprintf(path_buf[:], "%s/Microsoft/Windows/Fonts/MinecraftTen-VGORe.ttf", local_app_data)
        if os.exists(user_font_path) {
            path_c_buf: [512]u8
            cstr := get_cstring(user_font_path, path_c_buf[:])
            font := rl.LoadFont(cstr)
            if font.texture.id != 0 && rl.GetGlyphIndex(font, 'A') != 0 {
                fmt.println("Loaded Minecraft font from:", user_font_path)
                return font
            }
            rl.UnloadFont(font)
        }
    }

    for path in font_paths {
        if os.exists(path) {
            path_c_buf: [512]u8
            cstr := get_cstring(path, path_c_buf[:])
            font := rl.LoadFont(cstr)
            if font.texture.id != 0 && rl.GetGlyphIndex(font, 'A') != 0 {
                fmt.println("Loaded Minecraft font from:", path)
                return font
            }
            rl.UnloadFont(font)
        }
    }

    consolas_buf: [512]u8
    consolas := rl.LoadFont(get_cstring("C:/Windows/Fonts/consola.ttf", consolas_buf[:]))
    if consolas.texture.id != 0 && rl.GetGlyphIndex(consolas, 'A') != 0 {
        fmt.println("Using Consolas as fallback font")
        return consolas
    }

    fmt.println("Using default raylib font")
    return rl.GetFontDefault()
}

Position :: struct {
    x, y: f32,
}

UIElement :: struct {
    rect: rl.Rectangle,
    text_pos: Position,
    label_pos: Position,
}

init_layout :: proc(window_width, window_height: i32) -> Layout {
    layout := DEFAULT_LAYOUT
    layout.viewport = rl.Rectangle{
        x = 0,
        y = 0,
        width = f32(window_width),
        height = f32(window_height),
    }
    return layout
}

add_section :: proc(layout: ^Layout, id: string, height: f32) -> ^LayoutSection {
    section := LayoutSection{
        id = id,
        rect = rl.Rectangle{},
        content_height = height,
        is_visible = true,
        scroll_offset = 0,
        max_scroll = 0,
        elements = make(map[UIElement_ID]UIElementState),
        active_element = -1,
        previous_element = -1,
    }
    append(&layout.sections, section)
    return &layout.sections[len(layout.sections) - 1]
}

update_layout :: proc(layout: ^Layout, window_width, window_height: i32) {
    // Update viewport
    layout.viewport.width = f32(window_width)
    layout.viewport.height = f32(window_height)
    
    // Calculate section positions
    current_y: f32 = 0
    for i in 0..<len(layout.sections) {
        section := &layout.sections[i]
        if section.is_visible {
            // Update section rectangle
            section.rect = rl.Rectangle{
                x = 0,
                y = current_y - section.scroll_offset,
                width = f32(window_width),
                height = section.content_height,
            }
            
            // Update max scroll
            section.max_scroll = max(0, section.content_height - f32(window_height))
            
            // Move to next section
            current_y += section.content_height
        }
    }
}

handle_scroll :: proc(layout: ^Layout, mouse_pos: rl.Vector2) {
    // Check if mouse is over any section
    for i in 0..<len(layout.sections) {
        section := &layout.sections[i]
        if section.is_visible && rl.CheckCollisionPointRec(mouse_pos, section.rect) {
            // Handle mouse wheel scrolling
            wheel_move := rl.GetMouseWheelMove()
            if wheel_move != 0 {
                section.scroll_offset = clamp(
                    section.scroll_offset - wheel_move * layout.scroll_speed,
                    0,
                    section.max_scroll,
                )
            }
            
            // Handle drag scrolling
            if rl.IsMouseButtonDown(.LEFT) {
                if !layout.is_scrolling {
                    layout.is_scrolling = true
                    layout.last_mouse_y = mouse_pos.y
                } else {
                    delta := layout.last_mouse_y - mouse_pos.y
                    section.scroll_offset = clamp(
                        section.scroll_offset + delta,
                        0,
                        section.max_scroll,
                    )
                    layout.last_mouse_y = mouse_pos.y
                }
            } else {
                layout.is_scrolling = false
            }
            
            break
        }
    }
}

draw_scrollbar :: proc(layout: ^Layout, section: ^LayoutSection) {
    if section.max_scroll <= 0 do return
    
    // Calculate scrollbar dimensions
    scrollbar_width: f32 = 8
    scrollbar_height := (section.rect.height / section.content_height) * section.rect.height
    scrollbar_x := section.rect.x + section.rect.width - scrollbar_width
    scrollbar_y := section.rect.y + (section.scroll_offset / section.max_scroll) * (section.rect.height - scrollbar_height)
    
    // Draw scrollbar track
    track_rect := rl.Rectangle{
        x = scrollbar_x,
        y = section.rect.y,
        width = scrollbar_width,
        height = section.rect.height,
    }
    rl.DrawRectangleRec(track_rect, rl.ColorAlpha(rl.DARKGRAY, 0.3))
    
    // Draw scrollbar thumb
    thumb_rect := rl.Rectangle{
        x = scrollbar_x,
        y = scrollbar_y,
        width = scrollbar_width,
        height = scrollbar_height,
    }
    rl.DrawRectangleRec(thumb_rect, rl.ColorAlpha(rl.GRAY, 0.7))
}

is_point_in_section :: proc(section: ^LayoutSection, point: rl.Vector2) -> bool {
    return rl.CheckCollisionPointRec(point, section.rect)
}

get_section_at_point :: proc(layout: ^Layout, point: rl.Vector2) -> ^LayoutSection {
    for i in 0..<len(layout.sections) {
        section := &layout.sections[i]
        if section.is_visible && is_point_in_section(section, point) {
            return section
        }
    }
    return nil
}

make_input_box :: proc(layout: ^Layout, section: ^LayoutSection, pos: Position, label: string, font: rl.Font, font_size: f32, font_spacing: f32) -> UIElement {
    label_c_buf: [256]u8
    label_width := rl.MeasureTextEx(font, get_cstring(label, label_c_buf[:]), font_size, font_spacing).x
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

make_dimension_buttons :: proc(layout: ^Layout, section: ^LayoutSection, pos: Position) -> (overworld: UIElement, nether: UIElement) {
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

draw_outlined_text :: proc(font: rl.Font, text: cstring, position: rl.Vector2, font_size: f32, spacing: f32, text_color: rl.Color = rl.WHITE, thickness: f32 = 1) {
    // Draw white outline
    outline_color := rl.WHITE
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
        rl.DrawTextEx(font, text, pos, font_size, spacing, outline_color)
    }
    
    // Draw the text with the specified color (black if white was passed to maintain original behavior)
    inner_color := text_color == rl.WHITE ? rl.BLACK : text_color
    rl.DrawTextEx(font, text, position, font_size, spacing, inner_color)
} 