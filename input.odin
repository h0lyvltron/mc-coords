package main

import "core:fmt"
import "core:strings"
import "core:strconv"
import rl "vendor:raylib"

InputBox :: enum {
    X,
    Z,
    Dimension,
    None,
}

InputAction :: enum {
    None,
    // Future Inputs
    Move_Up,          // W
    Move_Down,        // S
    Move_Left,        // A
    Move_Right,       // D
    Jump,             // Space
    Roll,             // Shift
    Interact,         // E
    Attack_Primary,   // Left Click
    Attack_Secondary, // Right Click
    Toggle_Menu,      // Escape
    // Navigation
    FocusNext,        // Tab
    FocusPrevious,    // Shift+Tab
    ClearFocus,
    // Dimension Control
    ToggleDimension,
    NextDimension,    // Right Arrow
    PreviousDimension,// Left Arrow
    // Input Control
    Backspace,        // Backspace
    Enter,            // Enter
    NumericInput,     // 0-9, -
    // UI Actions
    ToggleHelp,       // F1
    OpenSettings,     // Ctrl+S
    CopyDestination,  // Ctrl+C
}

KeyBinding :: struct {
    key: rl.KeyboardKey,
    action: InputAction,
}

InputState :: struct {
    active_input: InputBox,
    should_clear: bool,
    input_buffers: [2][32]u8,
    key_states: map[rl.KeyboardKey]KeyState,
    mouse: rl.Vector2,
    key_bindings: [dynamic]KeyBinding,
    needs_dimension_toggle: bool,
}

KeyConfig :: struct {
    initial_delay: f32,  // Time before first repeat
    repeat_rate: f32,    // Time between repeats
}

KeyState :: struct {
    is_held: bool,
    held_time: f32,
    last_repeat_time: f32,
    config: KeyConfig,
}

DEFAULT_KEY_CONFIG := KeyConfig{
    initial_delay = 0.5,  // 500ms initial delay
    repeat_rate = 0.05,   // 50ms between repeats
}

init_input_state :: proc(state: ^InputState) {
    state.key_bindings = make([dynamic]KeyBinding)
    state.key_states = make(map[rl.KeyboardKey]KeyState)
    state.active_input = .None
    state.should_clear = false
    state.needs_dimension_toggle = false
    
    state.key_states[.BACKSPACE] = KeyState{config = DEFAULT_KEY_CONFIG}
    state.key_states[.LEFT] = KeyState{config = DEFAULT_KEY_CONFIG}
    state.key_states[.RIGHT] = KeyState{config = DEFAULT_KEY_CONFIG}
    state.key_states[.TAB] = KeyState{config = KeyConfig{initial_delay = 0.5, repeat_rate = 0.2}}
    
    append(&state.key_bindings, KeyBinding{rl.KeyboardKey.W, .Move_Up})
    append(&state.key_bindings, KeyBinding{rl.KeyboardKey.S, .Move_Down})
    append(&state.key_bindings, KeyBinding{rl.KeyboardKey.A, .Move_Left})
    append(&state.key_bindings, KeyBinding{rl.KeyboardKey.D, .Move_Right})
    append(&state.key_bindings, KeyBinding{rl.KeyboardKey.SPACE, .Jump})
    append(&state.key_bindings, KeyBinding{rl.KeyboardKey.E, .Interact})
    append(&state.key_bindings, KeyBinding{rl.KeyboardKey.TAB, .FocusNext})
    append(&state.key_bindings, KeyBinding{rl.KeyboardKey.ESCAPE, .ClearFocus})
    append(&state.key_bindings, KeyBinding{rl.KeyboardKey.LEFT, .PreviousDimension})
    append(&state.key_bindings, KeyBinding{rl.KeyboardKey.RIGHT, .NextDimension})
    append(&state.key_bindings, KeyBinding{rl.KeyboardKey.ENTER, .Enter})
    append(&state.key_bindings, KeyBinding{rl.KeyboardKey.BACKSPACE, .Backspace})
    append(&state.key_bindings, KeyBinding{rl.KeyboardKey.F1, .ToggleHelp})
}

destroy_input_state :: proc(state: ^InputState) {
    delete(state.key_bindings)
}

get_action_for_key :: proc(state: ^InputState, key: rl.KeyboardKey) -> InputAction {
    for binding in state.key_bindings {
        if binding.key == key {
            return binding.action
        }
    }
    return .None
}

update_key_state :: proc(state: ^KeyState, is_down: bool, current_time: f32) -> bool {
    if is_down {
        if !state.is_held {
            state.is_held = true
            state.held_time = 0
            state.last_repeat_time = current_time
            return true
        } else {
            state.held_time += rl.GetFrameTime()
            if state.held_time >= state.config.initial_delay {
                time_since_last := current_time - state.last_repeat_time
                if time_since_last >= state.config.repeat_rate {
                    state.last_repeat_time = current_time
                    return true
                }
            }
        }
    } else {
        state.is_held = false
        state.held_time = 0
    }
    return false
}

handle_numeric_input :: proc(state: ^InputState, key: rune) -> bool {
    if state.active_input == .X || state.active_input == .Z {
        buffer := &state.input_buffers[state.active_input == .X ? 0 : 1]
        
        if (key >= '0' && key <= '9') || (key == '-') {
            i: int = 0
            for i < len(buffer) && buffer[i] != 0 {
                i += 1
            }
            
            if i >= 9 {
                return false
            }
            
            if i < len(buffer) - 1 { // Leave room for null terminator
                if state.should_clear {
                    for j := 0; j < len(buffer); j += 1 {
                        buffer[j] = 0
                    }
                    i = 0
                    state.should_clear = false
                }
                
                if key == '-' && i > 0 do return false
                
                buffer[i] = u8(key)
                buffer[i+1] = 0
                return true
            }
        }
    }
    return false
}

update_input_state :: proc(state: ^InputState) -> bool {
    current_time := f32(rl.GetTime())
    
    state.mouse = rl.GetMousePosition()
    
    for key, &key_state in &state.key_states {
        if update_key_state(&key_state, rl.IsKeyDown(key), current_time) {
            action := get_action_for_key(state, key)
            #partial switch action {
            case .Backspace:
                if state.active_input == .X || state.active_input == .Z {
                    buffer := &state.input_buffers[state.active_input == .X ? 0 : 1]
                    if buffer[0] != 0 {
                        i: int = 0
                        for i < len(buffer) && buffer[i] != 0 {
                            i += 1
                        }
                        if i > 0 {
                            buffer[i-1] = 0
                            return true
                        }
                    }
                }
            case .FocusNext:
                if rl.IsKeyDown(.LEFT_SHIFT) || rl.IsKeyDown(.RIGHT_SHIFT) {
                    switch state.active_input {
                    case .X:
                        state.active_input = .Dimension
                    case .Z:
                        state.active_input = .X
                    case .Dimension:
                        state.active_input = .Z
                    case .None:
                        state.active_input = .Dimension
                    }
                } else {
                    switch state.active_input {
                    case .X:
                        state.active_input = .Z
                    case .Z:
                        state.active_input = .Dimension
                    case .Dimension:
                        state.active_input = .X
                    case .None:
                        state.active_input = .X
                    }
                }
                state.should_clear = state.active_input == .X || state.active_input == .Z
            case .PreviousDimension, .NextDimension:
                if state.active_input == .Dimension {
                    state.needs_dimension_toggle = true
                }
            }
        }
    }
    
    if rl.IsKeyPressed(.ESCAPE) {
        state.active_input = .None
    }
    
    key := rl.GetCharPressed()
    if key != 0 {
        if handle_numeric_input(state, key) {
            return true
        }
    }
    
    return false
}

is_action_pressed :: proc(state: ^InputState, action: InputAction) -> bool {
    for binding in state.key_bindings {
        if binding.action == action {
            return rl.IsKeyPressed(binding.key)
        }
    }
    return false
}

is_action_down :: proc(state: ^InputState, action: InputAction) -> bool {
    for binding in state.key_bindings {
        if binding.action == action {
            return rl.IsKeyDown(binding.key)
        }
    }
    return false
}

is_action_released :: proc(state: ^InputState, action: InputAction) -> bool {
    for binding in state.key_bindings {
        if binding.action == action {
            return rl.IsKeyReleased(binding.key)
        }
    }
    return false
}

bind_key :: proc(state: ^InputState, key: rl.KeyboardKey, action: InputAction) {
    for i := len(state.key_bindings) - 1; i >= 0; i -= 1 {
        if state.key_bindings[i].action == action {
            ordered_remove(&state.key_bindings, i)
        }
    }
    
    append(&state.key_bindings, KeyBinding{key, action})
}

unbind_key :: proc(state: ^InputState, action: InputAction) {
    for i := len(state.key_bindings) - 1; i >= 0; i -= 1 {
        if state.key_bindings[i].action == action {
            ordered_remove(&state.key_bindings, i)
        }
    }
}

get_key_for_action :: proc(state: ^InputState, action: InputAction) -> rl.KeyboardKey {
    for binding in state.key_bindings {
        if binding.action == action {
            return binding.key
        }
    }
    return rl.KeyboardKey.KEY_NULL
}

MouseState :: struct {
    position: rl.Vector2,
    delta: rl.Vector2,
    wheel: f32,
    buttons: [5]bool,
}

update_coordinates_from_input :: proc(input: ^InputState, coords: ^CoordinateState, state: ^AppState) {
    if input.active_input == .None {
        return
    }
    
    // Parse input buffers to integers
    x_str := strings.trim_right(string(input.input_buffers[0][:]), "\x00")
    z_str := strings.trim_right(string(input.input_buffers[1][:]), "\x00")
    
    if len(x_str) == 0 || len(z_str) == 0 {
        return
    }
    
    x, x_ok := strconv.parse_int(x_str)
    z, z_ok := strconv.parse_int(z_str)
    
    if !x_ok || !z_ok {
        return
    }
    
    // Only mark as changed if the coordinates actually changed
    old_x := coords.source.x
    old_z := coords.source.z
    
    update_coordinates(coords, x, z)
    
    if old_x != coords.source.x || old_z != coords.source.z {
        state.state_tracking.has_unsaved_changes = true
    }
}

string_from_bytes :: proc(bytes: []u8) -> string {
    i: int = 0
    for i < len(bytes) && bytes[i] != 0 {
        i += 1
    }
    return string(bytes[:i])
}

// Handle dimension button clicks
handle_dimension_click :: proc(state: ^AppState, dimension: Dimension) {
    if state.coordinates.source_dimension != dimension {
        state.coordinates.source_dimension = dimension
        state.coordinates.needs_conversion = true
        state.state_tracking.has_unsaved_changes = true
    }
}

// Handle location operations that modify state
handle_location_operation :: proc(state: ^AppState, operation: LocationOperation) {
    switch operation {
    case .Add:
        // Add new location logic
        state.state_tracking.has_unsaved_changes = true
    case .Remove:
        // Remove location logic
        state.state_tracking.has_unsaved_changes = true
    case .Edit:
        // Edit location logic
        state.state_tracking.has_unsaved_changes = true
    }
}

// Handle shader parameter updates
handle_shader_param_update :: proc(state: ^AppState, param: ShaderParameter, value: f32) {
    old_value: f32
    switch param {
    case .NoiseScale:
        old_value = state.title.digital_noise_params.noise_scale
        state.title.digital_noise_params.noise_scale = value
    case .GlitchIntensity:
        old_value = state.title.digital_noise_params.glitch_intensity
        state.title.digital_noise_params.glitch_intensity = value
    case .ScanLineDensity:
        old_value = state.title.digital_noise_params.scan_line_density
        state.title.digital_noise_params.scan_line_density = value
    case .TearFrequency:
        old_value = state.title.digital_noise_params.tear_frequency
        state.title.digital_noise_params.tear_frequency = value
    case .RGBSplitAmount:
        old_value = state.title.digital_noise_params.rgb_split_amount
        state.title.digital_noise_params.rgb_split_amount = value
    case .StaticAmount:
        old_value = state.title.digital_noise_params.static_amount
        state.title.digital_noise_params.static_amount = value
    case .PulseSpeed:
        old_value = state.title.digital_noise_params.pulse_speed
        state.title.digital_noise_params.pulse_speed = value
    case .PulseIntensity:
        old_value = state.title.digital_noise_params.pulse_intensity
        state.title.digital_noise_params.pulse_intensity = value
    }
    
    if old_value != value {
        state.state_tracking.has_unsaved_changes = true
    }
}

// Location operations that can modify state
LocationOperation :: enum {
    Add,
    Remove,
    Edit,
}

// Shader parameters that can be modified
ShaderParameter :: enum {
    NoiseScale,
    GlitchIntensity,
    ScanLineDensity,
    TearFrequency,
    RGBSplitAmount,
    StaticAmount,
    PulseSpeed,
    PulseIntensity,
}
