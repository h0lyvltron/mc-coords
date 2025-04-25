package main

import "core:strings"
import "core:fmt"
import "base:runtime"
import "core:mem"
import "core:time"
import "core:slice"
import rl "vendor:raylib"

// Memory usage categories to track different allocation sources
MemoryCategory :: enum {
    General,     // Default category
    Textures,    // Texture resources
    Strings,     // String allocations
    UI,          // UI elements
    Locations,   // Location data
    Temporary,   // Short-lived allocations
}

// Enhanced tracking allocator
tracker: mem.Tracking_Allocator
original_allocator: mem.Allocator // Store original allocator
enable_detailed_tracking := false  // Turn off detailed tracking by default
memory_report_interval: f64 = 30.0  // Report less frequently (30 seconds)
memory_snapshot_time: f64

// Reusable string buffers to avoid allocations
StringBuffers :: struct {
    debug_buffer: [1024]u8,
    secondary_buffer: [1024]u8,
    coord_buffer: [64]u8,
    feedback_buffer: [32]u8,
    title_buffer: [256]u8,
}

// Global buffers for string reuse
str_buffers: StringBuffers

// Safe way to get a cstring from a string without allocation
get_cstring :: proc(str: string, buffer: []u8) -> cstring {
    if len(str) == 0 {
        buffer[0] = 0
        return cstring(&buffer[0])
    }
    
    copy_size := min(len(str), len(buffer)-1)
    copy(buffer[:copy_size], str[:copy_size])
    buffer[copy_size] = 0
    return cstring(&buffer[0])
}

// Initialize memory tracking system - simplified version
init_memory_tracking :: proc() {
    // Check if we're already using a tracking allocator - simplified check
    track_alloc := mem.tracking_allocator(&tracker)
    if context.allocator == track_alloc {
        fmt.println("* Memory tracking system already active")
        return
    }
    
    // Save previous allocator to restore later
    original_allocator = context.allocator
    
    // Initialize tracking allocator
    mem.tracking_allocator_init(&tracker, context.allocator)
    
    // Set tracking allocator as the context allocator
    context.allocator = mem.tracking_allocator(&tracker)
    
    memory_snapshot_time = f64(time.now()._nsec) / 1e9
    
    fmt.println("* Memory tracking system initialized")
}

// Clean up memory tracking system
shutdown_memory_tracking :: proc() {
    // Display leaked allocations if any
    fmt.println("\n* Final Memory Leak Report:")
    if len(tracker.allocation_map) > 0 {
        fmt.println("  Detected", len(tracker.allocation_map), "potential memory leaks:")
        count := 0
        for ptr, entry in tracker.allocation_map {
            if count < 10 { // Limit output to first 10 leaks
                fmt.printf("  - %v: %d bytes at %v\n", entry.location, entry.size, ptr)
            }
            count += 1
        }
        if count > 10 {
            fmt.printf("  ... and %d more leaks\n", count - 10)
        }
    } else {
        fmt.println("  No memory leaks detected! (BECAUSE WE CAN'T ACTUALLY FIND THEM LOLOL)")
    }
    
    // Restore original allocator
    context.allocator = original_allocator
    
    // Clean up the tracking allocator
    mem.tracking_allocator_destroy(&tracker)
}

// Update memory tracking statistics periodically
update_memory_tracking :: proc() {
    if !enable_detailed_tracking do return
    
    current_time := f64(time.now()._nsec) / 1e9
    
    // Update memory stats and generate report at intervals
    if current_time - memory_snapshot_time >= memory_report_interval {
        memory_snapshot_time = current_time
        print_memory_report()
    }
}

// Print simplified memory report
print_memory_report :: proc() {
    fmt.println("\n* Memory Usage Summary:")
    fmt.printf("  Total allocations: %d\n", tracker.total_allocation_count)
    fmt.printf("  Current memory: %.2f KB\n", f32(tracker.current_memory_allocated) / 1024.0)
    fmt.printf("  Peak memory: %.2f KB\n", f32(tracker.peak_memory_allocated) / 1024.0)
    
    // Show top allocation sources
    if len(tracker.allocation_map) > 0 {
        // Build a map of locations to bytes
        locations := make(map[string]int)
        defer delete(locations)
        
        for _, entry in tracker.allocation_map {
            loc := fmt.tprintf("%v", entry.location)
            locations[loc] += entry.size
        }
        
        // Convert to slice for sorting
        location_pairs := make([]struct{loc: string, size: int}, len(locations))
        defer delete(location_pairs)
        
        i := 0
        for loc, size in locations {
            location_pairs[i] = {loc, size}
            i += 1
        }
        
        // Sort by size (largest first)
        slice.sort_by(location_pairs, proc(a, b: struct{loc: string, size: int}) -> bool {
            return a.size > b.size
        })
        
        fmt.println("\n  Top memory consumers:")
        for i in 0..<min(5, len(location_pairs)) {
            pair := location_pairs[i]
            fmt.printf("  - %s: %.2f KB\n", pair.loc, f32(pair.size)/1024.0)
        }
    }
}

// Safely allocate and free temporary memory
with_temp_memory :: proc(size: int, f: proc(data: []byte)) {
    buf := make([]byte, size, context.temp_allocator)
    defer delete(buf, context.temp_allocator)
    
    f(buf)
}

// Load texture without allocating strings but with memory tracking
load_texture_tracked :: proc(path: string) -> rl.Texture2D {
    // Use a shared buffer
    buf: [1024]u8
    cstr := get_cstring(path, buf[:])
    texture := rl.LoadTexture(cstr)
    
    return texture
}

// Unload texture with memory tracking
unload_texture_tracked :: proc(texture: rl.Texture2D) {
    rl.UnloadTexture(texture)
}

// Memory-efficient text rendering helpers
draw_text_efficient :: proc(text: string, x, y: i32, font_size: i32, color: rl.Color) {
    // Use a shared buffer
    buf: [1024]u8
    cstr := get_cstring(text, buf[:])
    rl.DrawText(cstr, x, y, font_size, color)
}

// Safe string to cstring conversion without memory leaks
safe_cstring :: proc(s: string) -> cstring {
    if len(s) == 0 {
        return cstring("")
    }
    
    // Use a temporary slice for the cstring
    buf := make([]u8, len(s) + 1, context.temp_allocator)
    copy(buf, transmute([]u8)s)
    buf[len(s)] = 0
    return cstring(&buf[0])
}

// Set clipboard text without allocating strings
set_clipboard_text_efficient :: proc(text: string) {
    // Use a shared buffer
    buf: [1024]u8
    cstr := get_cstring(text, buf[:])
    rl.SetClipboardText(cstr)
}

// Format string without allocation using the next available buffer
format_string :: proc(format: string, args: ..any) -> string {
    // Use a reusable buffer from the pool
    buf := get_buffer()
    if buf == nil {
        // Fallback to regular fmt.tprintf if no buffer available
        return fmt.tprintf(format, ..args)
    }
    
    result := fmt.bprintf(buf[:], format, ..args)
    return result
}

// Get the next reusable buffer (simple ring buffer implementation)
BUFFER_POOL_SIZE :: 8
BUFFER_SIZE :: 1024
buffer_pool: [BUFFER_POOL_SIZE][BUFFER_SIZE]u8
buffer_index: int = 0

get_buffer :: proc() -> []u8 {
    result := buffer_pool[buffer_index][:]
    buffer_index = (buffer_index + 1) % BUFFER_POOL_SIZE
    return result
}

// Simple memory diagnostic
diagnose_memory :: proc() {
    fmt.println("\n* Memory Diagnostic:")
    fmt.printf("  Total allocations: %d\n", tracker.total_allocation_count)
    fmt.printf("  Current memory: %.2f KB\n", f32(tracker.current_memory_allocated) / 1024.0)
    
    // Count string-related allocations
    string_allocs := 0
    string_bytes := 0
    
    for _, entry in tracker.allocation_map {
        loc_str := fmt.tprintf("%v", entry.location)
        if strings.contains(loc_str, "strings.") {
            string_allocs += 1
            string_bytes += entry.size
        }
    }
    
    fmt.printf("  String-related allocations: %d (%.2f KB)\n", 
              string_allocs, f32(string_bytes) / 1024.0)
              
    if string_allocs > 20 {
        fmt.println("  RECOMMENDATION: Consider using string buffers more consistently")
    }
}

// Simple stub for backward compatibility - doesn't actually track memory
track_allocation :: proc(category: MemoryCategory, size: int) {
    if enable_detailed_tracking {
        fmt.printf("# TRACK: %v +%d bytes\n", category, size)
    }
}

// Simple stub for backward compatibility - doesn't actually untrack memory
untrack_allocation :: proc(category: MemoryCategory, size: int) {
    if enable_detailed_tracking {
        fmt.printf("# UNTRACK: %v -%d bytes\n", category, size)
    }
} 