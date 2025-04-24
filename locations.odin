package main

import "core:fmt"
import "core:strings"
import rl "vendor:raylib"

Location :: struct {
    name: string,
    world: string,
    x: i32,
    z: i32,
    dimension: Dimension,
    description: string,
}

LocationDatabase :: struct {
    locations: [dynamic]Location,
    current_filter: string,
    selected_index: int,
}

init_location_database :: proc() -> LocationDatabase {
    return LocationDatabase {
        locations = make([dynamic]Location),
        current_filter = "",
        selected_index = -1,
    }
}

add_location :: proc(db: ^LocationDatabase, name: string, world: string, x: i32, z: i32, dimension: Dimension, description: string) {
    location := Location {
        name = strings.clone(name),
        world = strings.clone(world),
        x = x,
        z = z,
        dimension = dimension,
        description = strings.clone(description),
    }
    append(&db.locations, location)
}

delete_location :: proc(db: ^LocationDatabase, index: int) {
    if index >= 0 && index < len(db.locations) {
        delete(db.locations[index].name)
        delete(db.locations[index].world)
        delete(db.locations[index].description)
        unordered_remove(&db.locations, index)
        if db.selected_index >= len(db.locations) {
            db.selected_index = len(db.locations) - 1
        }
    }
}

destroy_location_database :: proc(db: ^LocationDatabase) {
    for location in db.locations {
        delete(location.name)
        delete(location.world)
        delete(location.description)
    }
    delete(db.locations)
}

filter_locations :: proc(db: ^LocationDatabase, filter: string) {
    db.current_filter = strings.clone(filter)
}

clear_filter :: proc(db: ^LocationDatabase) {
    delete(db.current_filter)
    db.current_filter = ""
}
