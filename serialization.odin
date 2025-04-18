package main

import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:strings"
import "core:strconv"
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

// SerializedState represents the data we want to save/load
SerializedState :: struct {
    coordinates: struct {
        input_x: int,  // Store as numbers instead of strings
        input_z: int,
        dimension: Dimension,
    },
    locations: []Location,
    shader_params: struct {
        wave_speed: f32,
        wave_amplitude: f32,
        wave_frequency: f32,
        wave_smoothness: f32,
        color_speed: f32,
        color_phase: f32,
        color_spread: f32,
        color_intensity: f32,
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
load_state :: proc(state: ^AppState) -> (ok: bool) {
    context.allocator = context.temp_allocator
    
    // Try to read the state file
    data, read_ok := os.read_entire_file("state.json")
    if !read_ok {
        fmt.eprintln("! No saved state file found")
        return false
    }
    defer delete(data)

    fmt.println("* Debug: Loading JSON data:", string(data))

    // Parse JSON
    serial_state: SerializedState
    unmarshal_err := json.unmarshal(data, &serial_state)
    if unmarshal_err != nil {
        fmt.eprintln("! Failed to parse state file:", unmarshal_err)
        return false
    }

    // Clear existing buffers by setting to zero
    for i in 0..<len(state.input.input_buffers[0]) {
        state.input.input_buffers[0][i] = 0
        state.input.input_buffers[1][i] = 0
    }
    
    // Convert integers back to strings
    x_str := fmt.tprintf("%d", serial_state.coordinates.input_x)
    z_str := fmt.tprintf("%d", serial_state.coordinates.input_z)
    
    fmt.println("* Debug: Loading coordinates:", x_str, z_str)
    
    // Copy input values into buffers
    for i in 0..<min(len(x_str), len(state.input.input_buffers[0])) {
        state.input.input_buffers[0][i] = x_str[i]
    }
    for i in 0..<min(len(z_str), len(state.input.input_buffers[1])) {
        state.input.input_buffers[1][i] = z_str[i]
    }
    
    // Update source coordinates and dimension
    state.coordinates.source.x = serial_state.coordinates.input_x
    state.coordinates.source.z = serial_state.coordinates.input_z
    state.coordinates.source_dimension = serial_state.coordinates.dimension
    
    // Trigger conversion
    state.coordinates.needs_conversion = true
    
    // Load locations
    if len(serial_state.locations) > 0 {
        state.locations.locations = make([dynamic]Location, len(serial_state.locations))
        for location, i in serial_state.locations {
            state.locations.locations[i] = location
        }
    }

    // Update shader parameters
    state.title.wave_params.speed = serial_state.shader_params.wave_speed
    state.title.wave_params.amplitude = serial_state.shader_params.wave_amplitude
    state.title.wave_params.frequency = serial_state.shader_params.wave_frequency
    state.title.wave_params.smoothness = serial_state.shader_params.wave_smoothness
    state.title.wave_params.color_speed = serial_state.shader_params.color_speed
    state.title.wave_params.color_phase = serial_state.shader_params.color_phase
    state.title.wave_params.color_spread = serial_state.shader_params.color_spread
    state.title.wave_params.color_intensity = serial_state.shader_params.color_intensity

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

    // Only update shader uniforms if shaders are initialized
    if state.title.shaders[3].shader.id != 0 {
        shader := &state.title.shaders[3]  // Sine wave shader
        rl.SetShaderValue(shader.shader, shader.wave_speed_loc, &state.title.wave_params.speed, .FLOAT)
        rl.SetShaderValue(shader.shader, shader.wave_amplitude_loc, &state.title.wave_params.amplitude, .FLOAT)
        rl.SetShaderValue(shader.shader, shader.wave_frequency_loc, &state.title.wave_params.frequency, .FLOAT)
        rl.SetShaderValue(shader.shader, shader.wave_smoothness_loc, &state.title.wave_params.smoothness, .FLOAT)
        rl.SetShaderValue(shader.shader, shader.color_speed_loc, &state.title.wave_params.color_speed, .FLOAT)
        rl.SetShaderValue(shader.shader, shader.color_phase_loc, &state.title.wave_params.color_phase, .FLOAT)
        rl.SetShaderValue(shader.shader, shader.color_spread_loc, &state.title.wave_params.color_spread, .FLOAT)
        rl.SetShaderValue(shader.shader, shader.color_intensity_loc, &state.title.wave_params.color_intensity, .FLOAT)
    } else {
        fmt.println("* Shaders not initialized yet - parameters will be applied when shaders are loaded")
    }

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

    fmt.println("* State loaded successfully")
    return true
}

// Save state to temporary file
save_state_temp :: proc(state: ^AppState) -> bool {
    context.allocator = context.temp_allocator
    
    // Parse input buffers to integers
    x_str := strings.trim_right(string(state.input.input_buffers[0][:]), "\x00")
    z_str := strings.trim_right(string(state.input.input_buffers[1][:]), "\x00")
    
    fmt.println("* Debug: Raw input buffers:")
    fmt.println("  X buffer:", x_str, "length:", len(x_str))
    fmt.println("  Z buffer:", z_str, "length:", len(z_str))
    
    // Handle empty inputs
    if len(x_str) == 0 || len(z_str) == 0 {
        // Use the converted coordinates if input is empty
        x_val := state.coordinates.converted.x
        z_val := state.coordinates.converted.z
        fmt.println("* Debug: Using converted coordinates:", x_val, z_val)
        
        // Create serialized state from app state
        serial_state := SerializedState{
            coordinates = {
                input_x = x_val,
                input_z = z_val,
                dimension = state.coordinates.source_dimension,
            },
            locations = state.locations.locations[:],
            shader_params = {
                wave_speed = state.title.wave_params.speed,
                wave_amplitude = state.title.wave_params.amplitude,
                wave_frequency = state.title.wave_params.frequency,
                wave_smoothness = state.title.wave_params.smoothness,
                color_speed = state.title.wave_params.color_speed,
                color_phase = state.title.wave_params.color_phase,
                color_spread = state.title.wave_params.color_spread,
                color_intensity = state.title.wave_params.color_intensity,
                // Digital noise parameters
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
        }
        
        // Save digital noise parameters
        serial_state.shader_params.noise_scale = state.title.digital_noise_params.noise_scale
        serial_state.shader_params.glitch_intensity = state.title.digital_noise_params.glitch_intensity
        serial_state.shader_params.scan_line_density = state.title.digital_noise_params.scan_line_density
        serial_state.shader_params.tear_frequency = state.title.digital_noise_params.tear_frequency
        serial_state.shader_params.rgb_split_amount = state.title.digital_noise_params.rgb_split_amount
        serial_state.shader_params.static_amount = state.title.digital_noise_params.static_amount
        serial_state.shader_params.pulse_speed = state.title.digital_noise_params.pulse_speed
        serial_state.shader_params.pulse_intensity = state.title.digital_noise_params.pulse_intensity
        serial_state.shader_params.glitch_color = state.title.digital_noise_params.glitch_color
        
        // Convert to JSON
        data, marshal_err := json.marshal(serial_state)
        if marshal_err != nil {
            fmt.eprintln("! Failed to marshal state to JSON:", marshal_err)
            return false
        }
        defer delete(data)
        
        // Print debug info
        fmt.println("* Debug: JSON data:", string(data))
        
        // Write to temporary file first
        if !os.write_entire_file("state.json.tmp", data) {
            fmt.eprintln("! Failed to write temporary state file")
            return false
        }
        
        fmt.println("* Temporary state file written successfully")
        return true
    }
    
    // Try to parse non-empty input buffers
    x_val, x_ok := strconv.parse_int(x_str)
    z_val, z_ok := strconv.parse_int(z_str)
    
    if !x_ok || !z_ok {
        fmt.eprintln("! Failed to parse input coordinates")
        fmt.eprintln("  X parse result:", x_ok)
        fmt.eprintln("  Z parse result:", z_ok)
        return false
    }
    
    fmt.println("* Debug: Successfully parsed coordinates:", x_val, z_val)
    
    // Create serialized state from app state
    serial_state := SerializedState{
        coordinates = {
            input_x = x_val,
            input_z = z_val,
            dimension = state.coordinates.source_dimension,
        },
        locations = state.locations.locations[:],
        shader_params = {
            wave_speed = state.title.wave_params.speed,
            wave_amplitude = state.title.wave_params.amplitude,
            wave_frequency = state.title.wave_params.frequency,
            wave_smoothness = state.title.wave_params.smoothness,
            color_speed = state.title.wave_params.color_speed,
            color_phase = state.title.wave_params.color_phase,
            color_spread = state.title.wave_params.color_spread,
            color_intensity = state.title.wave_params.color_intensity,
            // Digital noise parameters
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
    }

    // Save digital noise parameters
    serial_state.shader_params.noise_scale = state.title.digital_noise_params.noise_scale
    serial_state.shader_params.glitch_intensity = state.title.digital_noise_params.glitch_intensity
    serial_state.shader_params.scan_line_density = state.title.digital_noise_params.scan_line_density
    serial_state.shader_params.tear_frequency = state.title.digital_noise_params.tear_frequency
    serial_state.shader_params.rgb_split_amount = state.title.digital_noise_params.rgb_split_amount
    serial_state.shader_params.static_amount = state.title.digital_noise_params.static_amount
    serial_state.shader_params.pulse_speed = state.title.digital_noise_params.pulse_speed
    serial_state.shader_params.pulse_intensity = state.title.digital_noise_params.pulse_intensity
    serial_state.shader_params.glitch_color = state.title.digital_noise_params.glitch_color

    // Convert to JSON
    data, marshal_err := json.marshal(serial_state)
    if marshal_err != nil {
        fmt.eprintln("! Failed to marshal state to JSON:", marshal_err)
        return false
    }
    defer delete(data)

    // Print debug info
    fmt.println("* Debug: JSON data:", string(data))

    // Write to temporary file first
    if !os.write_entire_file("state.json.tmp", data) {
        fmt.eprintln("! Failed to write temporary state file")
        return false
    }

    fmt.println("* Temporary state file written successfully")
    return true
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