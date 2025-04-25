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
    selected_index: int,
    scroll_offset: f32,         // Scrolling position for the location list
    filtered_locations: [dynamic]int, // Indices of filtered locations for search
    current_filter: string,     // Current search filter text
}

init_location_database :: proc() -> LocationDatabase {
    return LocationDatabase {
        locations = make([dynamic]Location),
        selected_index = -1,
        scroll_offset = 0,
        filtered_locations = make([dynamic]int),
        current_filter = "",
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
    delete(db.filtered_locations)
}

// Simple fuzzy search - checks if characters appear in the correct order in the string
fuzzy_match :: proc(s, pattern: string) -> bool {
    fmt.printf("* DEBUG Fuzzy: Matching '%s' against pattern '%s'\n", s, pattern)

    if len(pattern) == 0 { 
        fmt.println("* DEBUG Fuzzy: Empty pattern, auto-match")
        return true 
    }
    
    if len(s) == 0 { 
        fmt.println("* DEBUG Fuzzy: Empty string, no match")
        return false 
    }
    
    s_lower := strings.to_lower(s)
    pattern_lower := strings.to_lower(pattern)
    
    s_idx, p_idx: int
    
    for p_idx < len(pattern_lower) {
        // If we've reached the end of the string before matching all pattern chars, no match
        if s_idx >= len(s_lower) { 
            fmt.println("* DEBUG Fuzzy: Reached end of string without full match")
            return false 
        }
        
        // If characters match, advance both indices
        if s_lower[s_idx] == pattern_lower[p_idx] {
            fmt.printf("* DEBUG Fuzzy: Matched '%c' at position %d\n", s_lower[s_idx], s_idx)
            p_idx += 1
        }
        s_idx += 1
    }
    
    // If we've gone through all pattern characters, we have a match
    result := p_idx == len(pattern_lower)
    fmt.printf("* DEBUG Fuzzy: %s (matched %d of %d pattern chars)\n", 
              result ? "MATCH" : "NO MATCH", p_idx, len(pattern_lower))
    return result
}

// Update the filter function to use fuzzy search with better safety
filter_locations :: proc(db: ^LocationDatabase, filter: string) {
    if db == nil {
        fmt.eprintln("! Error: null LocationDatabase pointer in filter_locations")
        return
    }
    
    fmt.printf("* DEBUG: filter_locations called with filter: '%s'\n", filter)
    
    // Skip processing if the filter is empty - show all locations
    if len(filter) == 0 {
        // Clean up previous filter
        clear(&db.filtered_locations)
        fmt.println("* DEBUG: Empty filter, showing all locations")
        return
    }
    
    // Clean up previous filter safely
    clear(&db.filtered_locations)
    
    total_matches := 0
    
    // Apply substring filtering to populate filtered_locations
    for location, idx in db.locations {
        // Guard against null strings
        name := location.name != "" ? location.name : ""
        world := location.world != "" ? location.world : ""
        desc := location.description != "" ? location.description : ""
        
        filter_lower := strings.to_lower(filter)
        
        // Check if any field matches the filter
        name_match := strings.contains(strings.to_lower(name), filter_lower)
        world_match := strings.contains(strings.to_lower(world), filter_lower)
        desc_match := strings.contains(strings.to_lower(desc), filter_lower)
        
        // Check if coordinates match
        coords_buf: [32]u8
        coords_str := fmt.bprintf(coords_buf[:], "%d %d", location.x, location.z)
        coords_match := strings.contains(strings.to_lower(coords_str), filter_lower)
        
        // Add location index to filtered list if any match is found
        if name_match || world_match || desc_match || coords_match {
            append(&db.filtered_locations, idx)
            total_matches += 1
            
            fmt.printf("* DEBUG: Match found for location %d '%s': name=%v, world=%v, desc=%v, coords=%v\n", 
                      idx, name, name_match, world_match, desc_match, coords_match)
        }
    }
    
    fmt.printf("* DEBUG: Found %d matches total for filter '%s'\n", total_matches, filter)
    
    // Reset scroll position when filter changes
    db.scroll_offset = 0
    
    // Adjust selected index to remain within available items
    if len(db.filtered_locations) > 0 {
        if db.selected_index >= len(db.locations) || db.selected_index < 0 {
            db.selected_index = 0
            fmt.println("* DEBUG: Setting selected index to 0")
        } else {
            // Check if the currently selected index is in filtered results
            found := false
            for filtered_idx in db.filtered_locations {
                if filtered_idx == db.selected_index {
                    found = true
                    break
                }
            }
            
            // If not found, select the first filtered result
            if !found {
                db.selected_index = db.filtered_locations[0]
                fmt.printf("* DEBUG: Setting selected index to filtered[0] = %d\n", db.selected_index)
            }
        }
    } else {
        db.selected_index = -1
        fmt.println("* DEBUG: No matches found, setting selected index to -1")
    }
}

// Clear the filter and reset scrolling
clear_filter :: proc(db: ^LocationDatabase) {
    clear(&db.filtered_locations)
    db.scroll_offset = 0
}
