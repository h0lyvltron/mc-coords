# Minecraft Coordinate Manager - Refactoring Context

## Current State
The application currently provides basic coordinate conversion between Minecraft dimensions with a simple UI. Core functionality includes:
- Input fields for X/Y coordinates
- Dimension selection (Overworld/Nether)
- Automatic conversion
- Layout management

## Planned Refactoring

### 1. Input Management System
```odin
InputAction :: enum {
    Confirm,           // Enter - Confirm input/conversion
    FocusNext,        // Tab - Move to next field
    FocusPrevious,    // Shift+Tab - Move to previous field
    SelectAll,        // Ctrl+A - Select all text in active field
    DimensionToggle,  // Space - Toggle between dimensions
    DimensionNext,    // Right Arrow - Next dimension
    DimensionPrev,    // Left Arrow - Previous dimension
    ClearField,       // Escape - Clear current field
    OpenSettings,     // Ctrl+S - Open settings
    ToggleHelp,       // F1 - Toggle help overlay
    CopyDestination,  // Ctrl+C - copies destination coordinates to clipboard
}
```

#### Features
- Centralized input handling
- Configurable keybindings
- Support for modifier keys (Shift, Ctrl, Alt)
- Alternative key bindings
- Input action descriptions for help display

#### Implementation Notes
- Store bindings in a map[InputAction]InputBinding
- Support for both primary and secondary key bindings
- Handle modifier key states
- Provide easy-to-use interface for checking actions
- Consider gamepad/controller support for future

### 2. UI State Management

#### Components
- Active element tracking
- Focus management
- Modal states (settings, help overlay)
- Input field state
- Conversion state

#### Planned Structs
```odin
UIState :: struct {
    active_element: UIElement_ID,
    previous_element: UIElement_ID,
    keybind_ui: KeybindUI,
    show_help: bool,
}

UIElement_ID :: enum {
    None,
    Input_X,
    Input_Y,
    Button_Overworld,
    Button_Nether,
    Button_Settings,
}
```

### 3. Settings System

#### Features
- Keybinding configuration
- UI preferences
- Font settings
- Layout customization
- Save/Load functionality

#### Data Structure
```odin
Settings :: struct {
    input: InputManager,
    ui: struct {
        font_size: f32,
        spacing: f32,
        show_tooltips: bool,
    },
}
```

### 4. File Organization

#### Planned Structure
```
mc-coords/
├── src/
│   ├── main.odin           # Application entry point
│   ├── input.odin          # Input management
│   ├── ui_state.odin       # UI state management
│   ├── settings.odin       # Settings and configuration
│   ├── keybind_ui.odin     # Keybinding UI
│   ├── layout.odin         # Layout management
│   └── conversion/         # Coordinate conversion logic
├── assets/
│   └── fonts/             # Font files
└── config/                # User settings and keybinds
```

### 5. New Features to Implement

#### Phase 1: Core Systems
1. Input Management
   - Basic action mapping
   - Modifier key support
   - Action checking interface

2. Settings Framework
   - Basic settings storage
   - Save/load functionality
   - Default configuration

#### Phase 2: UI Improvements
1. Help System
   - Keybind display
   - Usage instructions
   - Tooltips

2. Settings UI
   - Keybind configuration
   - UI customization
   - Font selection

#### Phase 3: Enhanced Functionality
1. Coordinate Management
   - Multiple coordinate sets
   - Coordinate history
   - Import/Export

2. Quality of Life
   - Copy to clipboard
   - Paste coordinates
   - Quick actions


### 6. Future Considerations

- Localization support
- Theme system
- Plugin architecture
- Additional dimension support
- Coordinate set management
- Network features (multiplayer coordination)
- Backup/restore settings

## Implementation Priority

1. Input Management System
   - Essential for all other improvements
   - Enables better user interaction

2. Settings System
   - Required for storing keybinds
   - Enables user customization

3. UI State Management
   - Improves code organization
   - Enables new features

4. Help System
   - Makes new features discoverable
   - Improves user experience

## Notes

- Keep existing functionality working during refactor
- Maintain current performance
- Consider backward compatibility
- Document all new systems
- Add proper error handling
- Consider user feedback mechanisms

# System Design

## Current State
- Coordinate conversion between Overworld/Nether
- Input validation and null handling
- Font system with fallback chain
- Basic layout management using structs

## Data Structure Consolidations

### 1. Coordinate System
```odin
CoordinatePair :: struct {
    x, y: int,
    dimension: conversion.Dimension,
}

CoordinateState :: struct {
    source: CoordinatePair,
    converted: CoordinatePair,
    needs_conversion: bool,  // Indicates if conversion needs to be recalculated
}

// Conversion interface
convert_coordinate_pair :: proc(pair: CoordinatePair) -> CoordinatePair {
    target_dimension := pair.dimension == conversion.Dimension.Overworld ? conversion.Dimension.Nether : conversion.Dimension.Overworld
    return CoordinatePair {
        x = conversion.convert_between_dimensions(pair.x, pair.dimension, target_dimension),
        y = conversion.convert_between_dimensions(pair.y, pair.dimension, target_dimension),
        dimension = target_dimension,
    }
}

// Integration with AppState
AppState :: struct {
    coordinates: CoordinateState,
    // ... other fields
}
```

### 2. Input System
```odin
InputBuffer :: struct {
    buffer: [10]u8,
    length: int,
    is_active: bool,
    cursor_pos: int,
    selection_start: int,
    selection_end: int,
}

InputState :: struct {
    x: InputBuffer,
    y: InputBuffer,
    dimension: conversion.Dimension,
    backspace_held_time: f32,
    delete_held_time: f32,
}

// Integration with AppState
AppState :: struct {
    input: InputState,
    // ... other fields
}
```

### 3. UI Element System
```odin
UIElementState :: struct {
    element: UIElement,
    is_active: bool,
    is_hovered: bool,
    color: rl.Color,
    active_color: rl.Color,
    hover_color: rl.Color,
    text_color: rl.Color,
}

UIState :: struct {
    elements: map[UIElement_ID]UIElementState,
    active_element: UIElement_ID,
    previous_element: UIElement_ID,
    modal_state: Modal_State,
}

// Integration with AppState
AppState :: struct {
    ui: UIState,
    // ... other fields
}
```

### 4. Layout System
```odin
LayoutCalculator :: struct {
    layout: Layout,
    current_pos: Position,
    section_stack: [dynamic]Position,
}

LayoutManager :: struct {
    calculator: LayoutCalculator,
    elements: map[UIElement_ID]UIElement,
    default_spacing: f32,
    default_margin: f32,
}

// Integration with AppState
AppState :: struct {
    layout: LayoutManager,
    // ... other fields
}
```

## Integration Points

### 1. Coordinate Updates
- Triggered by:
  - Input field changes
  - Dimension changes
  - Manual conversion requests
- Updates:
  - Source coordinates
  - Converted coordinates (only when needs_conversion is true)
  - UI display
- State Management:
  - Sets needs_conversion when source changes
  - Clears needs_conversion after conversion
  - Prevents unnecessary recalculations

### 2. Input Handling
- Processes:
  - Text input
  - Navigation
  - Special keys
- Updates:
  - Input buffers
  - Cursor positions
  - Selections
  - Coordinate state

### 3. UI Updates
- Handles:
  - Element states
  - Focus changes
  - Modal displays
  - Color updates
- Updates:
  - Visual feedback
  - Input focus
  - Modal visibility

### 4. Layout Management
- Manages:
  - Element positions
  - Spacing
  - Margins
  - Section organization
- Updates:
  - Element rectangles
  - Text positions
  - Visual hierarchy

## Implementation Order

1. Coordinate System
   - Implement CoordinatePair
   - Add conversion logic
   - Update AppState integration

2. Input System
   - Create InputBuffer
   - Implement input handling
   - Add state management

3. UI System
   - Build UIElementState
   - Implement state updates
   - Add visual feedback

4. Layout System
   - Create LayoutCalculator
   - Implement position management
   - Add section handling

## Notes
- Each system maintains its own state
- Clear interfaces between systems
- Minimal coupling between components
- Easy to extend and modify
- Performance considerations for frequent updates 