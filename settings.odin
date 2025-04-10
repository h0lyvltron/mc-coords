package main

import "core:fmt"
import "core:strings"
import rl "vendor:raylib"

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
