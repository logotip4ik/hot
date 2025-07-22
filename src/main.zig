const std = @import("std");

const Options = struct {
    maxRetries: ?u16 = 10,

    retryDelay: u32 = 500,

    help: bool = false,

    const Self = @This();

    pub fn init() Self {
        return Self{};
    }

    pub fn parseAndAssign(self: *Self, comptime fieldName: []const u8, value: []const u8) !void {
        const fieldType = @FieldType(Self, fieldName);

        switch (fieldType) {
            ?u16 => {
                if (std.mem.eql(u8, value, "null")) {
                    @field(self, fieldName) = null;
                } else if (std.fmt.parseInt(u16, value, 10)) |int| {
                    @field(self, fieldName) = int;
                } else |_| {
                    return error.InvalidArgument;
                }
            },
            u32 => {
                if (std.fmt.parseInt(fieldType, value, 10)) |int| {
                    @field(self, fieldName) = int;
                } else |_| {
                    return error.InvalidArgument;
                }
            },
            bool => {
                if (std.mem.eql(u8, value, "true")) {
                    @field(self, fieldName) = true;
                } else if (std.mem.eql(u8, value, "false")) {
                    @field(self, fieldName) = false;
                } else {
                    return error.InvalidArgument;
                }
            },
            else => @compileError("unhandled types during options parsing"),
        }
    }
};

pub fn main() !void {
    if (!std.process.can_spawn) {
        @compileError("Spawning isn't available here fot this target");
    }

    var pages: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    const alloc = pages.allocator();
    defer pages.deinit();

    const stdoutFile = std.io.getStdOut();
    const out = stdoutFile.writer();

    const args = std.process.argsAlloc(alloc) catch |e| {
        out.print("Failed getting process args with: {any}\n", .{@errorName(e)}) catch unreachable;
        return;
    };

    if (args.len < 2) {
        return error.NotEnoughOptions;
    }

    var commandToRun: ?[]u8 = null;
    var options = Options.init();

    var i: u16 = 1;
    while (i < args.len) : (i += 1) {
        const arg = args[i];

        if (commandToRun == null and !std.mem.startsWith(u8, arg, "--")) {
            commandToRun = arg;
            continue;
        }

        const fields = @typeInfo(Options).@"struct".fields;
        inline for (fields) |field| {
            const fieldArg = std.fmt.comptimePrint("--{s}", .{field.name});

            if (std.mem.startsWith(u8, arg, fieldArg)) {
                const fieldParam: ?[]const u8 = blk: {
                    // user probably provided param for this field in next arg
                    if (arg.len == fieldArg.len and i + 1 < args.len and !std.mem.startsWith(u8, args[i + 1], "--")) {
                        i += 1;
                        break :blk args[i];
                    } else if (arg[fieldArg.len] == '=') {
                        break :blk arg[fieldArg.len + 1 ..];
                    }

                    break :blk null;
                };

                if (fieldParam) |param| {
                    options.parseAndAssign(field.name, param) catch {
                        out.print("wrong argument \"{s}\" provided for {s}, expected {s}\n", .{
                            param,
                            field.name,
                            @typeName(field.type),
                        }) catch unreachable;

                        return;
                    };
                } else {
                    switch (field.type) {
                        ?u16, u32 => {},
                        bool => {
                            @field(options, field.name) = !field.defaultValue().?;
                        },
                        else => @compileError("unhandled types during options parsing"),
                    }
                }
            }
        }
    }

    if (options.help) {
        out.writeAll(
            \\hot - simple process supervisor
            \\
            \\Usage: hot [command] [[...args]]
            \\
            \\Optional arguments:
            \\  --maxRetries - number of retries to do, accepts `number` or `null` (default is 10)
            \\  --retryDelay - delay between each retries in ms (default is 500ms)
            \\
            \\Example:
            \\ hot ./my-bot --maxRetries 10 --retryDelay 100
            \\
        ) catch unreachable;
        return;
    }

    if (commandToRun) |argv| {
        // that's probably a good thing that we have a hard limit on max retries...
        const maxRetries = options.maxRetries orelse std.math.maxInt(u16);
        var retries: u16 = 0;

        while (retries < maxRetries) : (retries += 1) {
            if (options.retryDelay > 0 and retries != 0) {
                std.Thread.sleep(options.retryDelay * 1000 * 1000);
            }

            var process = std.process.Child.init(&[_][]const u8{
                "/bin/sh",
                "-c",
                argv,
            }, alloc);

            _ = process.spawnAndWait() catch |e| {
                out.print("failed spawining with: {s}, retrying...\n", .{@errorName(e)}) catch unreachable;
            };

        }

        out.print("Max retries reached, stopping until re-run manually.\n", .{}) catch unreachable;
    } else {
        out.print("Command to run missing.\n", .{}) catch unreachable;
    }
}
