package main

import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:strings"
import "core:strconv"
import "core:math"
import rl "vendor:raylib"

// SerializationError represents possible errors during save/load operations
SerializationError :: enum {
    None,
    FileError,
    WriteError,
    ReadError,
    ParseError,
    ValidationError,
}

// SerializedLocation represents a location for serialization
SerializedLocation :: struct {
    name: string,
    world: string,
    x: i32,
    z: i32,
    dimension: Dimension,
    description: string,
}

// SerializedState represents the data we want to save/load
SerializedState :: struct {
    coordinates: struct {
        input_x: i32,  // Changed from int to i32
        input_z: i32,  // Changed from int to i32
        dimension: Dimension,
    },
    locations: []SerializedLocation,
    shader_params: struct {
        // Digital noise parameters
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
    window: struct {
        width: i32,
        height: i32,
        pos_x: i32,
        pos_y: i32,
    },
}

// Helper to clean up temporary files
cleanup_temp_files :: proc() -> bool {
    if os.exists("state.json.tmp") {
        if os.remove("state.json.tmp") != 0 {
            fmt.eprintln("! Failed to remove temporary file")
            return false
        }
    }
    return true
}

// Load state from JSON file
load_state :: proc(state: ^AppState) -> bool {
    // Try to read state file
    data, ok := os.read_entire_file("state.json")
    if !ok {
        fmt.println("No existing state file found")
        return false
    }
    defer delete(data)

    // Parse JSON data
    serial_state: SerializedState
    err := json.unmarshal(data, &serial_state)
    if err != nil {
        fmt.eprintln("Failed to parse state file:", err)
        return false
    }
    defer {
        for loc in serial_state.locations {
            delete(loc.name)
            delete(loc.world)
            delete(loc.description)
        }
        delete(serial_state.locations)
    }

    // Store texture and shader data
    old_background := state.background
    old_title := state.title
    old_font := state.font
    old_font_size := state.font_size
    old_layout := state.layout
    old_input := state.input
    
    // Need to store locations before clearing state
    old_locations := state.locations
    
    // Clear state but preserve graphics resources and UI state
    state^ = AppState{
        background = old_background,
        title = old_title,
        font = old_font,
        font_size = old_font_size,
        layout = old_layout,
        input = old_input,
        locations = old_locations, // Keep the reference but we'll clean the contents
    }
    
    // Clean up existing locations
    for location in state.locations.locations {
        delete(location.name)
        delete(location.world) 
        delete(location.description)
    }
    clear(&state.locations.locations)
    
    // Debug info
    fmt.println("* Loading", len(serial_state.locations), "locations from saved state")

    // Copy locations
    for location in serial_state.locations {
        name_clone := strings.clone(location.name)
        track_allocation(.Strings, len(name_clone))
        
        world_clone := strings.clone(location.world)
        track_allocation(.Strings, len(world_clone))
        
        desc_clone := strings.clone(location.description)
        track_allocation(.Strings, len(desc_clone))
        
        add_location := Location{
            name = name_clone,
            world = world_clone,
            description = desc_clone,
            x = location.x,
            z = location.z,
            dimension = location.dimension,
        }
        append(&state.locations.locations, add_location)
    }

    // Debug information about loaded locations
    if len(state.locations.locations) > 0 {
        fmt.println("* Successfully loaded", len(state.locations.locations), "locations:")
        for i in 0..<min(len(state.locations.locations), 5) { // Show up to 5 locations for brevity
            fmt.println("  -", state.locations.locations[i].name, "at", 
                       state.locations.locations[i].x, ",", 
                       state.locations.locations[i].z, 
                       "(", state.locations.locations[i].dimension, ")")
        }
        if len(state.locations.locations) > 5 {
            fmt.println("  ... and", len(state.locations.locations) - 5, "more")
        }
    } else {
        fmt.println("* No locations were loaded from the state file")
    }

    // Copy window state and update Raylib window
    state.window_width = serial_state.window.width
    state.window_height = serial_state.window.height
    
    // Ensure window size is at least the minimum
    if state.window_width < 400 do state.window_width = 400
    if state.window_height < 300 do state.window_height = 300
    
    // Update Raylib window size
    rl.SetWindowSize(state.window_width, state.window_height)
    
    // Restore window position from saved state
    if serial_state.window.pos_x != 0 && serial_state.window.pos_y != 0 {
        rl.SetWindowPosition(serial_state.window.pos_x, serial_state.window.pos_y)
        fmt.println("* Restored window position:", serial_state.window.pos_x, serial_state.window.pos_y)
    }
    
    // Update layout with new window dimensions
    update_layout(&state.layout, state.window_width, state.window_height)
    
    // No need to update the background color, as it's just a simple color value

    // Clear existing buffers by setting to zero
    for i in 0..<len(state.input.coord_buffers[0]) {
        state.input.coord_buffers[0][i] = 0
        state.input.coord_buffers[1][i] = 0
    }
    
    // Convert integers back to strings using reusable buffers instead of fmt.tprintf
    x_buf: [32]u8
    z_buf: [32]u8
    x_str := fmt.bprintf(x_buf[:], "%d", serial_state.coordinates.input_x)
    z_str := fmt.bprintf(z_buf[:], "%d", serial_state.coordinates.input_z)
    
    fmt.println("* Debug: Loading coordinates:", x_str, z_str)
    
    // Copy input values into buffers
    for i in 0..<min(len(x_str), len(state.input.coord_buffers[0])) {
        state.input.coord_buffers[0][i] = x_str[i]
    }
    for i in 0..<min(len(z_str), len(state.input.coord_buffers[1])) {
        state.input.coord_buffers[1][i] = z_str[i]
    }
    
    // Update source coordinates and dimension
    state.coordinates.source.x = i32(serial_state.coordinates.input_x)
    state.coordinates.source.z = i32(serial_state.coordinates.input_z)
    state.coordinates.source_dimension = serial_state.coordinates.dimension
    
    // Trigger conversion
    state.coordinates.needs_conversion = true

    // Load digital noise parameters
    state.title.digital_noise_params.noise_scale = serial_state.shader_params.noise_scale
    state.title.digital_noise_params.glitch_intensity = serial_state.shader_params.glitch_intensity
    state.title.digital_noise_params.scan_line_density = serial_state.shader_params.scan_line_density
    state.title.digital_noise_params.tear_frequency = serial_state.shader_params.tear_frequency
    state.title.digital_noise_params.rgb_split_amount = serial_state.shader_params.rgb_split_amount
    state.title.digital_noise_params.static_amount = serial_state.shader_params.static_amount
    state.title.digital_noise_params.pulse_speed = serial_state.shader_params.pulse_speed
    state.title.digital_noise_params.pulse_intensity = serial_state.shader_params.pulse_intensity
    state.title.digital_noise_params.glitch_color = serial_state.shader_params.glitch_color

    // Apply digital noise parameters to shader
    if state.title.shaders[0].shader.id != 0 {
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
    }

    // Make sure Input state has the proper reference to locations
    state.input.locations = &state.locations

    fmt.println("* State loaded successfully")
    return true
}

// Save state to temporary file
save_state_temp :: proc(state: ^AppState) -> bool {
    // Use temp allocator for JSON serialization
    {
        context.allocator = context.temp_allocator
        defer free_all(context.temp_allocator)
        
        // Parse input buffers to integers
        x_str := strings.trim_right(string(state.input.coord_buffers[0][:]), "\x00")
        z_str := strings.trim_right(string(state.input.coord_buffers[1][:]), "\x00")
        
        // Get current window state
        window_pos := rl.GetWindowPosition()
        window_width := rl.GetScreenWidth()
        window_height := rl.GetScreenHeight()
        
        // Create serialized locations
        serialized_locations := make([]SerializedLocation, len(state.locations.locations))
        
        for location, i in state.locations.locations {
            serialized_locations[i] = SerializedLocation{
                name = strings.clone(location.name, context.temp_allocator),
                world = strings.clone(location.world, context.temp_allocator),
                x = location.x,
                z = location.z,
                dimension = location.dimension,
                description = strings.clone(location.description, context.temp_allocator),
            }
        }
        
        // Parse coordinates, using converted coordinates as fallback
        x_val, z_val: i32
        if len(x_str) > 0 && len(z_str) > 0 {
            x_val_int, x_ok := strconv.parse_int(x_str)
            z_val_int, z_ok := strconv.parse_int(z_str)
            
            if !x_ok || !z_ok {
                fmt.eprintln("Failed to parse input coordinates")
                return false
            }
            
            x_val = i32(x_val_int)
            z_val = i32(z_val_int)
        } else {
            // Use converted coordinates if input is empty
            x_val = i32(math.round_f32(f32(state.coordinates.converted.x)))
            z_val = i32(math.round_f32(f32(state.coordinates.converted.z)))
        }
        
        // Create serialized state from app state
        serial_state := SerializedState{
            coordinates = {
                input_x = x_val,
                input_z = z_val,
                dimension = state.coordinates.source_dimension,
            },
            locations = serialized_locations,
            shader_params = {
                noise_scale = state.title.digital_noise_params.noise_scale,
                glitch_intensity = state.title.digital_noise_params.glitch_intensity,
                scan_line_density = state.title.digital_noise_params.scan_line_density,
                tear_frequency = state.title.digital_noise_params.tear_frequency,
                rgb_split_amount = state.title.digital_noise_params.rgb_split_amount,
                static_amount = state.title.digital_noise_params.static_amount,
                pulse_speed = state.title.digital_noise_params.pulse_speed,
                pulse_intensity = state.title.digital_noise_params.pulse_intensity,
                glitch_color = state.title.digital_noise_params.glitch_color,
            },
            window = {
                width = window_width,
                height = window_height,
                pos_x = i32(math.round_f32(f32(window_pos.x))),
                pos_y = i32(math.round_f32(f32(window_pos.y))),
            },
        }

        // Convert to JSON
        data, err := json.marshal(serial_state)
        if err != nil {
            fmt.eprintln("Failed to marshal state to JSON:", err)
            return false
        }
        
        // Write to temporary file first
        ok := os.write_entire_file("state.json.tmp", data)
        if !ok {
            fmt.eprintln("Failed to write temporary state file")
            return false
        }
        
        fmt.println("State saved to temporary file")
        return true
    }
}

// Save state to final file
save_state_final :: proc(state: ^AppState) -> bool {
    // Check if temporary file exists
    if !os.exists("state.json.tmp") {
        fmt.eprintln("! No temporary file found to finalize")
        return false
    }

    // Try to remove existing state file if it exists
    if os.exists("state.json") {
        err := os.remove("state.json")
        if err != 0 {
            fmt.eprintln("! Failed to remove existing state file")
            // Don't return false here - try the rename anyway
        }
    }
    
    // Rename temporary file to final file
    err := os.rename("state.json.tmp", "state.json")
    if err != 0 {
        fmt.eprintln("! Failed to rename temporary file to final file")
        fmt.eprintln("  Error code:", err)
        // Don't remove the temp file on failure - we might want to retry
        return false
    }
    
    fmt.println("* Final state file saved successfully")
    return true
}