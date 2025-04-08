# Minecraft Coordinate Management Tool

## Overview
A GUI application built with Odin to manage and convert Minecraft coordinates between dimensions, featuring an intuitive interface with plans for location management.

## Technical Stack
- **Language**: Odin
- **GUI Framework**: [raylib](https://www.raylib.com/)
- **Font**: [Minecraft Ten by NubeFonts](https://www.fontspace.com/minecraft-ten-font-f40317)
- **Persistence**: Planned JSON file for storing saved locations

## Core Features

### 1. Coordinate Conversion
- Real-time coordinate conversion between Overworld and Nether
- Input fields for X and Y coordinates
- Dimension toggle buttons (Overworld/Nether)
- Clear display of converted coordinates

### 2. User Interface
- Intuitive input field behavior:
  - Fields clear automatically when focused
  - Supports negative numbers
  - Comfortable key repeat timing (0.5s initial delay, then 20 chars/sec)
  - Backspace and Delete keys work naturally
- Dimension switching controls:
  - Space key to toggle
  - Right arrow to switch to Nether (from Overworld)
  - Left arrow to switch to Overworld (from Nether)
  - Mouse click on dimension buttons
- Navigation:
  - Tab to move forward
  - Shift+Tab to move backward
  - Mouse click to select any field
  - Tab cycle: X field → Y field → Dimension switch → X field

### 3. Location Management (Planned)
- Save locations with:
  - Custom name
  - Coordinates (X, Y)
  - Dimension
  - Optional description/tags
- List view of saved locations
- Search/filter functionality
- Edit and delete saved locations

### 4. Data Structure

```odin
// Current Implementation
AppState :: struct {
    input_x: [32]u8,
    input_y: [32]u8,
    input_x_len: int,
    input_y_len: int,
    current_dimension: conversion.Dimension,
    converted_x: i32,
    converted_y: i32,
    active_input: int, // 0 = none, 1 = x, 2 = y, 3 = dimension
    backspace_held_time: f32,
    delete_held_time: f32,
    field_just_focused: bool,
}

// Planned Location Management
Location :: struct {
    name: string,
    x: int,
    y: int,
    dimension: Dimension,
    description: string,
    tags: []string,
}

LocationDatabase :: struct {
    locations: [dynamic]Location,
    current_filter: string,
    selected_index: int,
}
```

### 5. UI Layout

```
+----------------------------------------+
|  Minecraft Coordinate Converter         |
+----------------------------------------+
|  X: [____________]                      |
|  Y: [____________]                      |
|                                        |
|  [Overworld] [Nether]                  |
|                                        |
|  Converted Coordinates:                |
|  X: ___  Y: ___                        |
+----------------------------------------+
|  Saved Locations (Planned)             |
|  [Search: _______________________]     |
|  +----------------------------------+ |
|  | * Home Base (Overworld)          | |
|  |   X: 100, Y: 200                 | |
|  | * Nether Portal (Nether)         | |
|  |   X: -16, Y: 24                  | |
|  | ...                              | |
|  +----------------------------------+ |
|  [Add Location] [Edit] [Delete]       |
+----------------------------------------+
```

## Implementation Details

### Current Features
- Real-time coordinate validation
- Intuitive field focus behavior
- Comfortable key repeat timing
- Natural dimension switching
- Complete keyboard navigation
- Clean monospace font display
- Visual feedback for active elements
- Consistent spacing and alignment
- Clear dimension indicators

### Implementation Plan

#### Phase 1: Core Functionality (Completed)
1. Set up basic Odin project structure
2. Implement coordinate conversion logic
3. Create basic raylib window and input handling

#### Phase 2: UI Implementation (Completed)
1. Design and implement the main window layout
2. Add coordinate input fields and conversion display
3. Implement dimension toggle
4. Add keyboard navigation

#### Phase 3: Location Management (Planned)
1. Implement location data structure
2. Add location saving/loading functionality
3. Create location list view
4. Implement search/filter functionality

#### Phase 4: Data Persistence (Planned)
1. Implement JSON serialization/deserialization
2. Add file I/O for saving/loading location database
3. Add auto-save functionality

#### Phase 5: Polish (Planned)
1. Add error handling
2. Implement input validation
3. Add tooltips and help text
4. Polish UI styling
5. Add keyboard shortcuts

## File Structure

```
minecraft_coords/
├── src/
│   ├── main.odin
│   ├── conversion/
│   │   └── coordinates.odin
│   ├── ui/
│   │   ├── main_window.odin
│   │   ├── location_list.odin (planned)
│   │   └── input_fields.odin
│   ├── data/
│   │   ├── location.odin (planned)
│   │   └── persistence.odin (planned)
│   └── utils/
│       └── helpers.odin
├── resources/
│   └── locations.json (planned)
└── build/
    └── minecraft_coords.exe
```

## Future Enhancements
1. Add support for Y-axis (vertical) coordinates
2. Integration with Minecraft server API
3. Import/Export functionality
4. Multiple location databases
5. Location categories/folders
6. Distance calculation between points
7. Path planning/waypoint system
8. Map visualization
9. Multi-language support
