package main

import "core:fmt"
import "core:math"
import rl "vendor:raylib"

Dimension :: enum {
    Overworld,
    Nether,
}

CoordinatePair :: struct {
    x, z: int,
    dimension: Dimension,
}

CoordinateState :: struct {
    source: CoordinatePair,
    converted: CoordinatePair,
    source_dimension: Dimension,
    needs_conversion: bool,
}

init_coordinate_state :: proc() -> CoordinateState {
    return CoordinateState {
        source = CoordinatePair{0, 0, Dimension.Overworld},
        converted = CoordinatePair{0, 0, Dimension.Nether},
        source_dimension = Dimension.Overworld,
        needs_conversion = true,
    }
}

get_converted_coordinates :: proc(coords: ^CoordinateState) {
    if !coords.needs_conversion {
        return
    }
    
    switch coords.source_dimension {
    case .Overworld:
        coords.converted.x = coords.source.x / 8
        coords.converted.z = coords.source.z / 8
    case .Nether:
        coords.converted.x = coords.source.x * 8
        coords.converted.z = coords.source.z * 8
    }
    
    coords.needs_conversion = false
}

update_coordinates :: proc(state: ^CoordinateState, x: int, z: int) {
    if x != state.source.x || z != state.source.z {
        state.source.x = x
        state.source.z = z
        state.needs_conversion = true
    }
}

update_dimension :: proc(state: ^CoordinateState, dimension: Dimension) {
    if dimension != state.source_dimension {
        state.source_dimension = dimension
        state.needs_conversion = true
    }
}

convert_coordinate_value :: proc(x: int, dimension: Dimension) -> int {
    switch dimension {
    case .Overworld:
        return x / 8
    case .Nether:
        return x * 8
    }
    return x
}

convert_between_dimensions :: proc(x: int, from: Dimension, to: Dimension) -> int {
    if from == to {
        return x
    }
    switch from {
    case .Overworld:
        return x / 8
    case .Nether:
        return x * 8
    }
    return x
}


coordinates_to_string :: proc(pair: CoordinatePair) -> string {
    return fmt.tprintf("X: %d, Z: %d (%v)", pair.x, pair.z, pair.dimension)
}
