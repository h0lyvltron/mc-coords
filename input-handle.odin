package main

import "core:fmt"
import "core:strings"
import "core:strconv"
import rl "vendor:raylib"

// Input box types
InputBox :: enum {
    X,
    Z,
    Dimension,
    None,
}

// Input action types
InputAction :: enum {
    None,
    // Future Inputs
    Move_Up,
    Move_Down,
    Move_Left,
    Move_Right,
    Jump,
    Roll,
    Interact,
    Attack_Primary,
    Attack_Secondary,
    Block,
    Toggle_Menu,
    // Navigation
    FocusNext,        // Tab
    FocusPrevious,    // Shift+Tab
    ClearFocus,       // Escape
    // Dimension Control
    ToggleDimension,  // Space
    NextDimension,    // Right Arrow
    PreviousDimension,// Left Arrow
    // Input Control
    Backspace,
    Enter,
    NumericInput,
    // UI Actions
    ToggleHelp,       // F1
    OpenSettings,     // Ctrl+S
    CopyDestination,  // Ctrl+C
}

// Key binding configuration
KeyBinding :: struct {
    key: rl.KeyboardKey,
    action: InputAction,
}

// Input state management
InputState :: struct {
    active_input: InputBox,
    should_clear: bool,
    input_buffers: [2][32]u8,
    key_states: map[rl.KeyboardKey]KeyState,
    mouse: rl.Vector2,
    key_bindings: [dynamic]KeyBinding,
    needs_dimension_toggle: bool,
}

// Key state configuration
KeyConfig :: struct {
    initial_delay: f32,  // Time before first repeat
    repeat_rate: f32,    // Time between repeats
}

// Key state tracking
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

// Initialize input state
init_input_state :: proc(state: ^InputState) {
    state.key_bindings = make([dynamic]KeyBinding)
    state.key_states = make(map[rl.KeyboardKey]KeyState)
    state.active_input = .None
    state.should_clear = false
    state.needs_dimension_toggle = false
    
    // Initialize key states
    state.key_states[.BACKSPACE] = KeyState{config = DEFAULT_KEY_CONFIG}
    state.key_states[.LEFT] = KeyState{config = DEFAULT_KEY_CONFIG}
    state.key_states[.RIGHT] = KeyState{config = DEFAULT_KEY_CONFIG}
    state.key_states[.TAB] = KeyState{config = KeyConfig{initial_delay = 0.5, repeat_rate = 0.2}}
    
    // Default key bindings
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

// Destroy input state
destroy_input_state :: proc(state: ^InputState) {
    delete(state.key_bindings)
}

// Get action for a given key
get_action_for_key :: proc(state: ^InputState, key: rl.KeyboardKey) -> InputAction {
    for binding in state.key_bindings {
        if binding.key == key {
            return binding.action
        }
    }
    return .None
}

// Update key state and check if it should trigger
update_key_state :: proc(state: ^KeyState, is_down: bool, current_time: f32) -> bool {
    if is_down {
        if !state.is_held {
            // Key was just pressed
            state.is_held = true
            state.held_time = 0
            state.last_repeat_time = current_time
            return true
        } else {
            // Key is being held
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
        // Key was released
        state.is_held = false
        state.held_time = 0
    }
    return false
}

// Handle numeric input
handle_numeric_input :: proc(state: ^InputState, key: rune) -> bool {
    if state.active_input == .X || state.active_input == .Z {
        buffer := &state.input_buffers[state.active_input == .X ? 0 : 1]
        
        // If this is a valid input character (number or minus)
        if (key >= '0' && key <= '9') || (key == '-') {
            // Find current length of buffer
            i: int = 0
            for i < len(buffer) && buffer[i] != 0 {
                i += 1
            }
            
            if i < len(buffer) - 1 { // Leave room for null terminator
                // Clear buffer on first character after focusing if needed
                if state.should_clear {
                    for j := 0; j < len(buffer); j += 1 {
                        buffer[j] = 0
                    }
                    i = 0
                    state.should_clear = false
                }
                
                // Only allow minus at start
                if key == '-' && i > 0 do return false
                
                buffer[i] = u8(key)
                buffer[i+1] = 0
                return true
            }
        }
    }
    return false
}

// Update input state
update_input_state :: proc(state: ^InputState) -> bool {
    current_time := f32(rl.GetTime())
    
    // Update mouse position
    state.mouse = rl.GetMousePosition()
    
    // Handle repeatable keys
    for key, &key_state in &state.key_states {
        if update_key_state(&key_state, rl.IsKeyDown(key), current_time) {
            action := get_action_for_key(state, key)
            #partial switch action {
            case .Backspace:
                if state.active_input == .X || state.active_input == .Z {
                    buffer := &state.input_buffers[state.active_input == .X ? 0 : 1]
                    if buffer[0] != 0 {
                        // Find the end of the string
                        i: int = 0
                        for i < len(buffer) && buffer[i] != 0 {
                            i += 1
                        }
                        if i > 0 {
                            buffer[i-1] = 0
                            // Trigger coordinate update on backspace
                            return true
                        }
                    }
                }
            case .FocusNext:
                if rl.IsKeyDown(.LEFT_SHIFT) || rl.IsKeyDown(.RIGHT_SHIFT) {
                    // Shift+Tab: Move backwards
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
                    // Tab: Move forwards
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
                    // Handle dimension toggle
                    state.needs_dimension_toggle = true
                }
            }
        }
    }
    
    // Handle one-shot keys
    if rl.IsKeyPressed(.ESCAPE) {
        state.active_input = .None
    }
    
    // Handle character input
    key := rl.GetCharPressed()
    if key != 0 {
        handle_numeric_input(state, key)
    }
    
    return false
}

// Check if an action is pressed
is_action_pressed :: proc(state: ^InputState, action: InputAction) -> bool {
    for binding in state.key_bindings {
        if binding.action == action {
            return rl.IsKeyPressed(binding.key)
        }
    }
    return false
}

// Check if an action is down
is_action_down :: proc(state: ^InputState, action: InputAction) -> bool {
    for binding in state.key_bindings {
        if binding.action == action {
            return rl.IsKeyDown(binding.key)
        }
    }
    return false
}

// Check if an action is released
is_action_released :: proc(state: ^InputState, action: InputAction) -> bool {
    for binding in state.key_bindings {
        if binding.action == action {
            return rl.IsKeyReleased(binding.key)
        }
    }
    return false
}

// Bind a key to an action
bind_key :: proc(state: ^InputState, key: rl.KeyboardKey, action: InputAction) {
    // Remove any existing binding for this action
    for i := len(state.key_bindings) - 1; i >= 0; i -= 1 {
        if state.key_bindings[i].action == action {
            ordered_remove(&state.key_bindings, i)
        }
    }
    
    // Add new binding
    append(&state.key_bindings, KeyBinding{key, action})
}

// Unbind a key from an action
unbind_key :: proc(state: ^InputState, action: InputAction) {
    for i := len(state.key_bindings) - 1; i >= 0; i -= 1 {
        if state.key_bindings[i].action == action {
            ordered_remove(&state.key_bindings, i)
        }
    }
}

// Get key for a given action
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

// Update coordinates from input buffers
update_coordinates_from_input :: proc(input: ^InputState, coords: ^CoordinateState) {
    // Convert input buffers to strings, properly handling null termination
    x_str := string_from_bytes(input.input_buffers[0][:])
    z_str := string_from_bytes(input.input_buffers[1][:])
    
    fmt.println("Input buffers:", x_str, z_str)
    
    // Convert strings to integers, defaulting to 0 if invalid
    x, x_ok := strconv.parse_int(x_str)
    z, z_ok := strconv.parse_int(z_str)
    
    fmt.println("Parsed values:", x, z, "Valid:", x_ok, z_ok)
    
    // Update coordinates even if one is invalid (default to 0)
    coords.source.x = x_ok ? x : 0
    coords.source.z = z_ok ? z : 0
    
    fmt.println("Updated source coordinates:", coords.source.x, coords.source.z)
    
    // Mark for conversion
    coords.needs_conversion = true
    fmt.println("Set needs_conversion to true")
}

// Convert bytes to string, properly handling null termination
string_from_bytes :: proc(bytes: []u8) -> string {
    i: int = 0
    for i < len(bytes) && bytes[i] != 0 {
        i += 1
    }
    return string(bytes[:i])
}
