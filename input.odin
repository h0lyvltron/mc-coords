package main

import "core:fmt"
import "core:strings"
import "core:strconv"
import rl "vendor:raylib"

// Define maximum buffer sizes
LOCATION_NAME_MAX :: 64
LOCATION_WORLD_MAX :: 64
LOCATION_DESCRIPTION_MAX :: 256
LOCATION_COORD_MAX :: 16 // For location dialog coordinates
MAIN_COORD_MAX :: 16 // For main X, Z coordinates
LOCATION_SEARCH_MAX :: 128

InputType :: enum {
    None,
    X,
    Z,
    Dimension,
    LocationSearch,
    LocationName,
    LocationWorld,
    LocationDescription,
    LocationX,  // New: for location dialog coordinate input
    LocationZ,  // New: for location dialog coordinate input
    RenameLocation, // For renaming a location in place
}

is_in_location_dialog :: proc(state: ^InputState) -> bool {
    return state.active_input == .LocationName ||
           state.active_input == .LocationWorld ||
           state.active_input == .LocationDescription ||
           state.active_input == .LocationX ||
           state.active_input == .LocationZ
}

is_in_main_input :: proc(state: ^InputState) -> bool {
    return state.active_input == .X ||
           state.active_input == .Z ||
           state.active_input == .Dimension
}

handle_escape :: proc(state: ^InputState) -> (handled: bool, should_exit: bool) {
    // First check if we're in any modal dialog
    if is_in_location_dialog(state) {
        // Reset location dialog state
        state.location_dialog_buffers.name[0] = 0
        state.location_dialog_buffers.world[0] = 0
        state.location_dialog_buffers.description[0] = 0
        state.location_dialog_buffers.x[0] = 0
        state.location_dialog_buffers.z[0] = 0
        // Reset location dialog dimension back to current source dimension
        state.location_dialog_dimension = .Overworld
        state.active_input = .None
        return true, false  // Handled, don't exit
    }
    
    // Then check for search or other input states
    if state.active_input != .None {
        state.active_input = .None
        return true, false  // Handled, don't exit
    }
    
    // If we're not in any modal state or input state, don't do anything special
    // but don't exit the program either
    return false, false  // Not handled, don't exit
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

LocationDialogInputBuffers :: struct {
    name:        [LOCATION_NAME_MAX]u8,
    world:       [LOCATION_WORLD_MAX]u8,
    description: [LOCATION_DESCRIPTION_MAX]u8,
    x:           [LOCATION_COORD_MAX]u8,
    z:           [LOCATION_COORD_MAX]u8,
}

InputState :: struct {
    active_input: InputType,
    coord_buffers: [3][MAIN_COORD_MAX]u8,       // For X, Z coordinates and Dimension in main view
    search_buffer: [LOCATION_SEARCH_MAX]u8, // For the main search bar
    
    location_dialog_buffers: LocationDialogInputBuffers,
    location_dialog_dimension: Dimension,  // Track selected dimension in the location dialog
    
    rename_buffer: [LOCATION_NAME_MAX]u8, // Buffer for renaming a location
    rename_location_index: int,          // Index of the location being renamed

    key_states: map[rl.KeyboardKey]KeyState, // Use KeyState for handling repeats
    should_clear: bool,
    mouse: rl.Vector2,
    mouse_handled: bool,  // Flag to track if a mouse click has been handled
    key_bindings: [dynamic]KeyBinding,
    needs_dimension_toggle: bool,
    last_backspace: f64,
    text_input_active: bool,
    tab_pressed: bool,  // Track tab key press state to prevent repeats
    locations: ^LocationDatabase,  // Reference to the locations database
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

init_input_state :: proc(state: ^InputState, locations: ^LocationDatabase) {
    state.key_bindings = make([dynamic]KeyBinding)
    state.key_states = make(map[rl.KeyboardKey]KeyState) // Initialize map
    state.active_input = .None
    state.should_clear = false
    state.needs_dimension_toggle = false
    state.text_input_active = false
    state.tab_pressed = false
    state.mouse_handled = false
    state.locations = locations
    state.rename_location_index = -1 // Initialize rename index
    state.location_dialog_dimension = .Overworld // Default dimension for new locations

    // Initialize main input buffers by setting the first byte to 0 (null terminator)
    state.coord_buffers[0][0] = 0 // X coord
    state.coord_buffers[1][0] = 0 // Z coord
    state.coord_buffers[2][0] = 0 // Dimension (assuming it uses the same buffer type for now)
    state.search_buffer[0] = 0 
    
    // Initialize location dialog input buffers
    state.location_dialog_buffers.name[0] = 0
    state.location_dialog_buffers.world[0] = 0
    state.location_dialog_buffers.description[0] = 0
    state.location_dialog_buffers.x[0] = 0
    state.location_dialog_buffers.z[0] = 0

    // Initialize rename buffer
    state.rename_buffer[0] = 0
    
    // Set up key states for repeatable keys
    state.key_states[rl.KeyboardKey.BACKSPACE] = KeyState{config = DEFAULT_KEY_CONFIG}
    state.key_states[rl.KeyboardKey.LEFT]      = KeyState{config = DEFAULT_KEY_CONFIG}
    state.key_states[rl.KeyboardKey.RIGHT]     = KeyState{config = DEFAULT_KEY_CONFIG}
    state.key_states[rl.KeyboardKey.TAB]       = KeyState{config = DEFAULT_KEY_CONFIG}
    state.key_states[rl.KeyboardKey.ESCAPE]    = KeyState{config = DEFAULT_KEY_CONFIG}

    // Set up key bindings
    append(&state.key_bindings, KeyBinding{rl.KeyboardKey.W, .Move_Up})
    append(&state.key_bindings, KeyBinding{rl.KeyboardKey.S, .Move_Down})
    append(&state.key_bindings, KeyBinding{rl.KeyboardKey.A, .Move_Left})
    append(&state.key_bindings, KeyBinding{rl.KeyboardKey.D, .Move_Right})
    append(&state.key_bindings, KeyBinding{rl.KeyboardKey.SPACE, .Jump})
    append(&state.key_bindings, KeyBinding{rl.KeyboardKey.E, .Interact})
    append(&state.key_bindings, KeyBinding{rl.KeyboardKey.TAB, .FocusNext})
    append(&state.key_bindings, KeyBinding{rl.KeyboardKey.ESCAPE, .Toggle_Menu})  // Change to Toggle_Menu
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
        buffer := &state.coord_buffers[state.active_input == .X ? 0 : 1]
        result := handle_coordinate_input(buffer[:], key, state.should_clear)
        if result {
            state.should_clear = false  // Reset the flag after successful input
        }
        return result
    } else if state.active_input == .LocationX || state.active_input == .LocationZ {
        buffer := state.active_input == .LocationX ? &state.location_dialog_buffers.x : &state.location_dialog_buffers.z
        result := handle_coordinate_input(buffer[:], key, state.should_clear)
        if result {
            state.should_clear = false  // Reset the flag after successful input
        }
        return result
    }
    return false
}

handle_coordinate_input :: proc(buffer: []u8, key: rune, should_clear: bool) -> bool {
    max_len := len(buffer) - 1 // Leave space for null terminator
    current_len := 0
    for ; current_len < len(buffer) && buffer[current_len] != 0; current_len += 1 {}

    if (key >= '0' && key <= '9') || (key == '-' && current_len == 0 && !should_clear) { // Allow '-' only at start if not clearing
        // If we should clear the buffer, do it before adding the new character
        if should_clear {
             fmt.println("Clearing coordinate buffer")
            for j := 0; j < len(buffer); j += 1 {
                buffer[j] = 0
            }
            current_len = 0 // Reset length after clearing
            // Now add the first character
            if key == '-' || (key >= '0' && key <= '9') {
                 if max_len > 0 { // Check if buffer has space
                     buffer[0] = u8(key)
                     buffer[1] = 0 // Null terminate
                     fmt.printf("Buffer cleared and updated: %s\n", cstring(&buffer[0]))
                     return true
                 }
            }
             fmt.println("Cannot add char after clear (buffer too small?)")
            return false // Cannot add char if buffer is size 0 or 1 after clear
        }

        // Append character if not clearing and space allows
        if current_len < max_len {
            buffer[current_len] = u8(key)
            buffer[current_len+1] = 0 // Null terminate
            fmt.printf("Buffer updated: %s\n", cstring(&buffer[0]))
            return true // Character added
        }
    }
     fmt.println("Coordinate character not added (invalid or buffer full)")
    return false // Character not added
}

handle_text_input :: proc(state: ^InputState) -> bool {
    if !state.text_input_active {
        return false
    }

    current_buffer: []u8
    max_len: int

    #partial switch state.active_input {
        case .LocationName:
            current_buffer = state.location_dialog_buffers.name[:]
            max_len = len(state.location_dialog_buffers.name) - 1
        case .LocationWorld:
            current_buffer = state.location_dialog_buffers.world[:]
            max_len = len(state.location_dialog_buffers.world) - 1
        case .LocationDescription:
            current_buffer = state.location_dialog_buffers.description[:]
            max_len = len(state.location_dialog_buffers.description) - 1
        case .LocationX:
            current_buffer = state.location_dialog_buffers.x[:]
            max_len = len(state.location_dialog_buffers.x) - 1
        case .LocationZ:
            current_buffer = state.location_dialog_buffers.z[:]
            max_len = len(state.location_dialog_buffers.z) - 1
        case .LocationSearch:
            current_buffer = state.search_buffer[:]  // Search buffer
            max_len = len(state.search_buffer) - 1
        case:
            return false
    }

    if state.should_clear {
        for i := 0; i < len(current_buffer); i += 1 {
            current_buffer[i] = 0
        }
        state.should_clear = false
    }

    // Find current length by looking for first null character or end of buffer
    text_len := 0
    for text_len < len(current_buffer) {
        if current_buffer[text_len] == 0 {
            break
        }
        text_len += 1
    }

    // Handle character input
    char := rl.GetCharPressed()
    for char != 0 {
        if text_len < max_len && char >= 32 && char <= 126 {
            current_buffer[text_len] = u8(char)
            current_buffer[text_len + 1] = 0  // Ensure null termination
            text_len += 1
            
            // Update filter if this is the search field
            if state.active_input == .LocationSearch {
                state.locations.current_filter = string(current_buffer[:text_len])
            }
        }
        char = rl.GetCharPressed()
    }

    // Handle backspace
    if rl.IsKeyPressed(.BACKSPACE) || (rl.IsKeyDown(.BACKSPACE) && rl.GetTime() - state.last_backspace > 0.12) {
        if text_len > 0 {
            text_len -= 1  // Move back one character
            current_buffer[text_len] = 0  // Set current character to null
            state.last_backspace = rl.GetTime()
            
            // Update filter if this is the search field
            if state.active_input == .LocationSearch {
                state.locations.current_filter = string(current_buffer[:text_len])
            }
        }
    }

    return true
}

update_input_state :: proc(state: ^InputState) -> bool {
    current_time := f32(rl.GetTime())
    
    // Reset mouse handling flag at the beginning of each frame
    state.mouse_handled = false
    
    // Direct escape key handling
    if rl.IsKeyPressed(.ESCAPE) {
        fmt.println("* Debug: Input state - escape key pressed")
        if is_in_location_dialog(state) {
            fmt.println("  - In location dialog, clearing dialog state")
            // Reset location dialog state
            state.location_dialog_buffers.name[0] = 0
            state.location_dialog_buffers.world[0] = 0
            state.location_dialog_buffers.description[0] = 0
            state.location_dialog_buffers.x[0] = 0
            state.location_dialog_buffers.z[0] = 0
            state.active_input = .None
            return true
        }
        
        if state.active_input != .None {
            // If we're in search box, clear it
            if state.active_input == .LocationSearch {
                // Reset search buffer
                for i in 0..<len(state.search_buffer) do state.search_buffer[i] = 0
                
                // Clear filter by passing empty string
                fmt.println("* DEBUG: Clearing search filter via escape key")
                apply_search_filter(state.locations, "")
            }
            
            fmt.println("  - In input field, clearing input state")
            state.active_input = .None
            return true
        }
        
        fmt.println("  - No input states to handle")
        return false
    }

    state.mouse = rl.GetMousePosition()
    
    // Update text input active state
    state.text_input_active = state.active_input == .LocationName || 
                            state.active_input == .LocationWorld || 
                            state.active_input == .LocationDescription ||
                            state.active_input == .LocationSearch ||
                            state.active_input == .LocationX ||
                            state.active_input == .LocationZ

    if state.text_input_active {
        if state.active_input == .LocationSearch {
            // Handle search input
            prev_search := string_from_bytes(state.search_buffer[:])
            
            char := rl.GetCharPressed()
            for char != 0 {
                if char >= 32 && char <= 126 {  // Printable characters
                    if state.should_clear {
                        for i in 0..<len(state.search_buffer) do state.search_buffer[i] = 0
                        state.should_clear = false
                    }
                    
                    // Find end of current text
                    i := 0
                    for i < len(state.search_buffer) && state.search_buffer[i] != 0 {
                        i += 1
                    }
                    
                    if i < len(state.search_buffer) - 1 {
                        state.search_buffer[i] = u8(char)
                        state.search_buffer[i + 1] = 0
                        
                        // Create a safe, temporary string for filtering
                        search_text := string(state.search_buffer[:i+1])
                        fmt.printf("* DEBUG Search text: '%s'\n", search_text)
                        
                        // Apply the simple filter directly
                        apply_search_filter(state.locations, search_text)
                    }
                }
                char = rl.GetCharPressed()
            }
            
            // Handle backspace for search
            if rl.IsKeyPressed(.BACKSPACE) || (rl.IsKeyDown(.BACKSPACE) && rl.GetTime() - state.last_backspace > 0.12) {
                i := 0
                for i < len(state.search_buffer) && state.search_buffer[i] != 0 {
                    i += 1
                }
                if i > 0 {
                    state.search_buffer[i-1] = 0
                    // Create a safe, temporary string for filtering
                    search_text := string(state.search_buffer[:i-1])
                    fmt.printf("* DEBUG Backspace: search now '%s'\n", search_text)
                    
                    // Apply the simple filter directly
                    apply_search_filter(state.locations, search_text)
                    
                    // Update backspace timer
                    state.last_backspace = rl.GetTime()
                }
            }
            
            return true
        } else {
            handle_text_input(state)
        }
    }

    // Handle Enter key for location fields
    if rl.IsKeyPressed(.ENTER) {
        if state.active_input == .LocationName {
            state.active_input = .LocationWorld
            return true
        } else if state.active_input == .LocationWorld {
            state.active_input = .LocationDescription
            return true
        }
        // LocationDescription Enter is handled in main.odin for creating the location
    }

    for key, &key_state in &state.key_states {
        if update_key_state(&key_state, rl.IsKeyDown(key), current_time) {
            action := get_action_for_key(state, key)
            #partial switch action {
            case .Toggle_Menu:  // Handle escape through the action system
                fmt.println("* Debug: Toggle_Menu action triggered")
                if is_in_location_dialog(state) {
                    fmt.println("  - Handling location dialog escape")
                    // Reset location dialog state
                    state.location_dialog_buffers.name[0] = 0
                    state.location_dialog_buffers.world[0] = 0
                    state.location_dialog_buffers.description[0] = 0
                    state.location_dialog_buffers.x[0] = 0
                    state.location_dialog_buffers.z[0] = 0
                    state.active_input = .None
                    return true
                } else if state.active_input != .None {
                    fmt.println("  - Clearing active input:", state.active_input)
                    state.active_input = .None
                    return true
                }
                fmt.println("  - No modal state to handle")
            case .Backspace:
                if state.active_input == .X || state.active_input == .Z {
                    buffer := &state.coord_buffers[state.active_input == .X ? 0 : 1]
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
                // Don't handle tab via the action system, defer to the main loop
                // which properly handles the tab_pressed flag
                return false
            case .PreviousDimension, .NextDimension:
                if state.active_input == .Dimension {
                    state.needs_dimension_toggle = true
                }
            }
        }
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
    x_str := strings.trim_right(string(input.coord_buffers[0][:]), "\x00")
    z_str := strings.trim_right(string(input.coord_buffers[1][:]), "\x00")
    
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
    
    update_coordinates(coords, i32(x), i32(z))
    
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

// Apply a simple filter to locations
apply_search_filter :: proc(db: ^LocationDatabase, search_text: string) {
    fmt.printf("* SEARCH: Applying filter '%s'\n", search_text)
    
    // Clear the filtered locations array
    clear(&db.filtered_locations)
    
    // If the search is empty, don't filter
    if len(search_text) == 0 {
        fmt.println("* SEARCH: Empty filter, showing all locations")
        return
    }
    
    // Apply a simple substring filter
    filter_lower := strings.to_lower(search_text)
    match_count := 0
    
    for location, idx in db.locations {
        // Guard against null strings
        name := location.name != "" ? location.name : ""
        world := location.world != "" ? location.world : ""
        desc := location.description != "" ? location.description : ""
        
        // Simple substring search using to_lower to make it case insensitive
        name_match := strings.contains(strings.to_lower(name), filter_lower)
        world_match := strings.contains(strings.to_lower(world), filter_lower) 
        desc_match := strings.contains(strings.to_lower(desc), filter_lower)
        
        // Check coords too
        coords_str := fmt.tprintf("%d %d", location.x, location.z)
        coords_match := strings.contains(strings.to_lower(coords_str), filter_lower)
        
        // Add location index to filtered list if any match is found
        if name_match || world_match || desc_match || coords_match {
            append(&db.filtered_locations, idx)
            match_count += 1
        }
    }
    
    fmt.printf("* SEARCH: Found %d matches for filter '%s'\n", match_count, search_text)
}

// Get the current search text from the buffer
get_search_text :: proc(state: ^InputState) -> string {
    return string_from_bytes(state.search_buffer[:])
}
