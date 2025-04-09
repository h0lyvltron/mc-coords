# Minecraft Coordinate Converter - Development Context

## Formatting Instructions
- files will be named in all lowercase and in kebab format
- modules will start with package main and files will be set in the root directory alongside main.odin

## Current Implementation

### Core Systems
- Basic coordinate conversion between Overworld and Nether dimensions
- Input validation for coordinate values
- Font loading with fallback mechanism
- Layout management for UI elements
- Input system separated into dedicated module
- Debug mode for troubleshooting

### Input System (input-handle.odin)
- Structured input handling
- Key state management with repeat functionality
- Mouse input handling
- Tab navigation between input elements
- Dimension toggle via keyboard and mouse
- Input buffer management for coordinate values
- Debug logging for input processing

### UI Elements
- X and Z coordinate input boxes
- Dimension selection buttons (Overworld/Nether)
- Title and section headers with outline effects
- Converted coordinate display
- Clickable converted coordinates with clipboard support

### Debug System
- Debug mode toggle for detailed logging
- Input buffer inspection
- Coordinate conversion tracking
- State transition logging
- Performance monitoring
- Error condition reporting

## Systems to Implement

### Input Management
- [x] Input state tracking
- [x] Key binding system
- [x] Mouse input handling
- [ ] Debug logging
- [ ] Input validation feedback
- [ ] Custom key binding support
- [ ] Clipboard integration

### UI State
- [x] Active element tracking
- [x] Focus management
- [ ] Debug mode UI
- [ ] Modal dialog system
- [ ] Animation system
- [ ] Theme support
- [ ] Hover state tracking
- [ ] Clipboard feedback

### Settings
- [x] Basic settings structure
- [ ] Debug mode configuration
- [ ] Theme configuration
- [ ] Font size adjustment
- [ ] Auto-save preferences
- [ ] Default dimension setting

### Location Management
- [ ] Location database
- [ ] Save/load functionality
- [ ] Location labeling
- [ ] Filtering system
- [ ] Import/export

## File Structure
```
mc-coords/
├── main.odin           # Main application entry point
├── input-handle.odin   # Input system implementation
├── modes.odin          # Modal state management
├── location-manager.odin # Location management system
├── shader.odin         # Shader management
├── assets/             # Resource files
│   └── tree-house.png  # Background image
└── vendor/             # External dependencies
    └── raylib/         # Graphics library
```

## Implementation Order
1. [x] Input system separation and refinement
2. [ ] Debug system implementation
3. [ ] Settings system implementation
4. [ ] UI state management
5. [ ] Location management
6. [ ] Additional features

## Debugging Best Practices
1. Implement debug mode early in development
2. Use structured logging for state transitions
3. Track input processing with detailed logs
4. Monitor coordinate conversion steps
5. Log error conditions and edge cases
6. Use debug mode to verify state changes
7. Document common debugging patterns
8. Keep debug logs clean and focused
9. Use debug mode to validate assumptions
10. Maintain debug mode in production for troubleshooting

## Notes
- Input system successfully separated into dedicated module
- Coordinate conversion working with proper input validation
- UI elements properly integrated with input system
- Debug mode implemented for troubleshooting, needs more work
- Focus on maintaining clean separation of concerns
- Future enhancements planned for settings and location management
- Testing systems in isolation before integration
- Documenting function signatures and data flow
- Considering performance implications of input handling
- Debug mode essential for maintaining system reliability and troubleshooting bugs efficiently