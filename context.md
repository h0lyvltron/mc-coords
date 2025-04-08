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