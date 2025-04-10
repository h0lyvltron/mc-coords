package main

import "core:fmt"
import "core:strings"
import rl "vendor:raylib"

Location :: struct {
    name: string,
    x: int,
    z: int,
    dimension: Dimension,
    description: string,
    tags: []string,
}

LocationManager :: struct {
    locations: [dynamic]Location,
    selected_index: int,
}

LocationDatabase :: struct {
    locations: [dynamic]Location,
    current_filter: string,
    selected_index: int,
}

init_location_manager :: proc() -> LocationManager {
    return LocationManager {
        locations = make([dynamic]Location),
        selected_index = -1,
    }
}

add_location :: proc(manager: ^LocationManager, name: string, x: int, z: int, dimension: Dimension) {
    location := Location {
        name = strings.clone(name),
        x = x,
        z = z,
        dimension = dimension,
    }
    append(&manager.locations, location)
}

delete_location :: proc(manager: ^LocationManager, index: int) {
    if index >= 0 && index < len(manager.locations) {
        delete(manager.locations[index].name)
        unordered_remove(&manager.locations, index)
        if manager.selected_index >= len(manager.locations) {
            manager.selected_index = len(manager.locations) - 1
        }
    }
}

destroy_location_manager :: proc(manager: ^LocationManager) {
    for location in manager.locations {
        delete(location.name)
    }
    delete(manager.locations)
}
