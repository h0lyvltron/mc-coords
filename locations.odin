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
    name_clone := strings.clone(name)
    track_allocation(.Locations, len(name_clone))
    
    world_clone := strings.clone(world)
    track_allocation(.Locations, len(world_clone))
    
    desc_clone := strings.clone(description)
    track_allocation(.Locations, len(desc_clone))
    
    location := Location {
        name = name_clone,
        world = world_clone,
        x = x,
        z = z,
        dimension = dimension,
        description = desc_clone,
    }
    append(&db.locations, location)
    track_allocation(.Locations, size_of(Location))
}

delete_location :: proc(db: ^LocationDatabase, index: int) {
    if index >= 0 && index < len(db.locations) {
        // Untrack memory before deleting
        untrack_allocation(.Locations, len(db.locations[index].name))
        untrack_allocation(.Locations, len(db.locations[index].world))
        untrack_allocation(.Locations, len(db.locations[index].description))
        
        delete(db.locations[index].name)
        delete(db.locations[index].world)
        delete(db.locations[index].description)
        
        untrack_allocation(.Locations, size_of(Location))
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
