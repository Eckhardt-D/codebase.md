const std = @import("std");
const fs = std.fs;

const MAX_DEPTH: usize = 10;
var stdout = std.io.getStdOut().writer();

pub fn main() !void {
    const cwd = fs.cwd();
    const start = try cwd.openDir(".", .{.iterate = true});
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const allocator = arena.allocator();
    try printFileTree(start, 0, null);
    try printFileContents(allocator, start);
}

fn printFileContents(allocator: std.mem.Allocator, dir: fs.Dir) !void {
    var iter = dir.iterate();

    while (try iter.next()) |entry| {
        if (std.mem.eql(u8, entry.name, ".zig-cache") or std.mem.eql(u8, entry.name, "zig-out")) {
            continue;
        }

        if (entry.kind == .file) {
            try stdout.print("=== {s} START ===\n", .{entry.name});
            const contents = try dir.readFileAlloc(allocator, entry.name, 1024 * 1024 * 10);
            try stdout.print("{s}\n", .{contents});
            try stdout.print("=== {s} END ===\n", .{entry.name});
        } else if (entry.kind == .directory) {
            const inner_dir = try dir.openDir(entry.name, .{.iterate = true});
            try printFileContents(allocator, inner_dir);
        }
    }
}

fn printFileTree(dir: fs.Dir, depth: usize, current_dirname: ?[]const u8) !void {
    if (depth >= MAX_DEPTH) {
        std.log.warn("Max depth reached, skipping..\n", .{});
        return;
    }

    var iter = dir.iterate();

    if (current_dirname) |name| {
      try stdout.print("- {s}\n", .{name});
    }

    while (try iter.next()) |entry| {
        for (0..depth) |_| {
            try stdout.print("  ", .{});
        }

        if (entry.kind == .directory) {
            const inner_dir = try dir.openDir(entry.name, .{.iterate = true});
            try printFileTree(inner_dir, depth + 1, entry.name);
        } else if (entry.kind == .file) {
            try stdout.print("- {s}\n", .{entry.name});
        }
    }
}
