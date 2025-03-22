const std = @import("std");
const fs = std.fs;

const help_text =
  \\codemd [flags] [path]
  \\
  \\path:
  \\  defaults to the current working directory
  \\
  \\flags:
  \\  -h, --help             prints this message
  \\  -o, --output  string   output file (defaults to stdout)
  \\  --ignore-path string   path to .gitignore file (default is <cwd>/.gitignore)
  ;

const Config = struct {
    stdout: fs.File,
    input_path: []const u8 = ".",
    max_depth: usize = 10,
    ignore_filepath: []const u8 = ".gitignore",
};

const Context = struct {
    allocator: std.mem.Allocator,
    filepaths: std.ArrayList([]const u8),
    output_file: fs.File,
    ignore_files: std.StringHashMap(void),
    config: *Config,

    pub fn init(allocator: std.mem.Allocator, config: *Config) Context {
        return .{
            .allocator = allocator,
            .filepaths = std.ArrayList([]const u8).init(allocator),
            .output_file = config.stdout,
            .ignore_files = std.StringHashMap(void).init(allocator),
            .config = config,
        };
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    var args = try std.process.argsWithAllocator(allocator);

    var config = Config{
        .stdout = std.io.getStdOut(),
    };

    var ctx = Context.init(allocator, &config);

    while(args.next()) |arg| {
        if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            try config.stdout.writer().print("{s}\n", .{help_text});
            return;
        }

        if(std.mem.eql(u8, arg, "--output") or std.mem.eql(u8, arg, "-o")) {
            if (args.next()) |next_arg| {
                const output_path = next_arg;
                const output_file = try fs.cwd().createFile(output_path, .{.mode=0o666});
                ctx.output_file = output_file;
            } else {
              try config.stdout.writer().print("Missing output file path\n", .{});
              return;
            }
        }

        if (std.mem.eql(u8, arg, "--ignore-path")) {
            if (args.next()) |next_arg| {
                config.ignore_filepath = next_arg;
            } else {
                try config.stdout.writer().print("Missing ignore file path\n", .{});
                return;
            }
        }
    }

    const cwd = fs.cwd();

    const default_ignore_files = &[_][]const u8{
        ".git",
        ".zig-cache",
        "node_modules",
        ".env",
        "zig-out",
    };

    inline for (default_ignore_files) |ignore_file| {
        try ctx.ignore_files.put(ignore_file, {});
    }

    // Load .gitignore entries
    try loadGitignore(&ctx);

    const start = try cwd.openDir(config.input_path, .{.iterate = true});

    try ctx.output_file.writeAll("## Project Tree\n\n");
    try printFileTree(&ctx, start, 0, null);

    try ctx.output_file.writeAll("\n## Project File Contents\n\n");
    try printFileContents(&ctx);
}

fn printFileContents(ctx: *Context) !void {
    for (ctx.filepaths.items) |path| {
        const file = try fs.openFileAbsolute(path, .{.mode = .read_only});
        defer file.close();

        const contents = try file.readToEndAlloc(ctx.allocator, 1024*1024*10);
        defer ctx.allocator.free(contents);

        const cwd_path = try fs.cwd().realpathAlloc(ctx.allocator, ".");
        defer ctx.allocator.free(cwd_path);

        var buff: [512]u8 = undefined;
        const num_replaced = std.mem.replace(u8, path, cwd_path, ".", &buff);
        // Dangerous, could have repeated patterns
        const size = path.len - (cwd_path.len * num_replaced) + 1;
        try ctx.output_file.writer().print("\n\n{s}\n", .{buff[0..size]});
        try ctx.output_file.writeAll("```\n");
        try ctx.output_file.writeAll(contents);
        try ctx.output_file.writeAll("\n```\n\n");
    }
}

fn printFileTree(ctx: *Context, dir: fs.Dir, depth: usize, current_dirname: ?[]const u8) !void {
    const stdout = ctx.config.stdout.writer();
    const out_writer = ctx.output_file.writer();

    if (depth >= ctx.config.max_depth) {
        try stdout.print("Max depth reached, skipping..\n", .{});
        return;
    }

    var iter = dir.iterate();

    if (current_dirname) |name| {
      if (ctx.ignore_files.contains(name)) {
          return;
      }

      try out_writer.print("- {s}\n", .{name});
    }

    while (try iter.next()) |entry| {
        for (0..depth) |_| {
            try out_writer.print("  ", .{});
        }

        if (entry.kind == .directory) {
            var inner_dir = try dir.openDir(entry.name, .{.iterate = true});
            defer inner_dir.close();
            try printFileTree(ctx, inner_dir, depth + 1, entry.name);
        } else if (entry.kind == .file) {
            const path = try dir.realpathAlloc(ctx.allocator, entry.name);
            try ctx.filepaths.append(path);
            try out_writer.print("- {s}\n", .{entry.name});
        }
    }
}

fn loadGitignore(ctx: *Context) !void {
    const ignore_file = fs.cwd().openFile(ctx.config.ignore_filepath, .{}) catch |err| {
        if (err == error.FileNotFound) return; // Skip if .gitignore doesn’t exist
        return err;
    };

    defer ignore_file.close();

    const content = try ignore_file.readToEndAlloc(ctx.allocator, 1024 * 1024); // Max 1MB
    defer ctx.allocator.free(content);

    var lines = std.mem.splitScalar(u8, content, '\n');

    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t");
        if (trimmed.len == 0 or trimmed[0] == '#') continue; // Skip empty lines and comments
        // Simplify: Treat as exact match (no globbing for now)
        const pattern = try ctx.allocator.dupe(u8, trimmed);
        try ctx.ignore_files.put(pattern, {});
    }
}
