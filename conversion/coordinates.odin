package conversion

import "core:math"

Dimension :: enum {
    Overworld,
    Nether,
}

// Convert coordinates between Overworld and Nether
// In Minecraft, the Nether is 1/8th the size of the Overworld
convert_coordinates :: proc(x: int, dimension: Dimension) -> int {
    switch dimension {
    case .Overworld:
        return x / 8
    case .Nether:
        return x * 8
    }
    return x
}

// Convert coordinates from one dimension to another
convert_between_dimensions :: proc(x: int, from: Dimension, to: Dimension) -> int {
    if from == to {
        return x
    }
    return convert_coordinates(x, from)
} 