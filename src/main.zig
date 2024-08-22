const std = @import("std");

/// The cow is not mine, but a BratishkaErik
const Samsa = union(enum) {
    array: []const []const u8,
    string: []const u8,

    pub fn jsonParse(allocator: std.mem.Allocator, source: anytype, options: std.json.ParseOptions) !Samsa {
        return switch (try source.peekNextTokenType()) {
            .array_begin => .{ .array = try std.json.innerParse([]const []const u8, allocator, source, options) },
            .string => .{ .string = try std.json.innerParse([]const u8, allocator, source, options) },
            else => error.UnexpectedToken,
        };
    }
};

const Aliases = struct {
    alias: Samsa,
    type: enum { path, method, bin, uri },
    description: ?[]const u8 = null,
    content: []const u8,
};

const OauthFlows = struct { implict: struct { authrizationUrl: []const u8, scopes: std.json.ArrayHashMap([]const u8) } };

const WellKnownSettings = struct {
    contentType: []const u8 = "application/json",
    headers: ?[]const []const u8 = null,
    aliases: ?[]const Aliases = null,
    auth: ?struct { scheme: enum { basic, bearer, oauth2 }, tokenName: ?[]const u8 = null, flows: ?OauthFlows = null } = null,
};

const WellKnownSchema = struct { api: ?[]const u8 = null, registry: ?bool = false, manifests: ?std.json.ArrayHashMap(struct { path: []const u8 }) = null, bin: ?std.json.ArrayHashMap([]const std.json.ArrayHashMap([]const u8)) = null, settings: ?WellKnownSettings = null };

const UserSettings = struct { db_path: []const u8 = "$HOME/.cache/wacrd.db", install_dir: []const u8 = "$HOME/.local/bin", uri_schemes: ?std.json.ArrayHashMap([]const u8) = null };

const json = std.json;

pub fn getHomeDir() !?std.fs.Dir {
    return try std.fs.openDirAbsolute(std.posix.getenv("HOME") orelse {
        return null;
    }, .{ .iterate = true });
}

pub fn getXDGConfigHomeDir() !?std.fs.Dir {
    return try std.fs.openDirAbsolute(std.posix.getenv("XDG_CONFIG_HOME") orelse {
        return null;
    }, .{ .iterate = true });
}

pub fn readTypedConfig(allocator: std.mem.Allocator, comptime T: type, filePath: []const u8, buffer_size: usize) !json.Parsed(T) {
    const contents = try std.fs.cwd().readFileAlloc(allocator, filePath, buffer_size);
    defer allocator.free(contents);
    return json.parseFromSlice(T, allocator, contents, .{
        .allocate = .alloc_always,
        .ignore_unknown_fields = true,
    });
}

pub fn main() !void {}

test "parse registry schema:" {
    const parsedExampleSettings = try readTypedConfig(std.testing.allocator, UserSettings, "examples/settings.json", 512);
    const parsedWaCLISchema = try readTypedConfig(std.testing.allocator, WellKnownSchema, "examples/wacli.ofs.lol/.well-known/wacli.json", 512);
    defer {
        parsedExampleSettings.deinit();
        parsedWaCLISchema.deinit();
    }

    const waCLISettings = parsedExampleSettings.value;
    const waCLISchema = parsedWaCLISchema.value;

    // const uri_schemes = waCLISettings.uri_schemes.?.map;

    //    std.debug.print("{any}\n", .{waCLISchema});
    try std.testing.expect(waCLISchema.registry == true);
    try std.testing.expect(waCLISchema.api == null);
    try std.testing.expect(std.mem.eql(u8, waCLISettings.db_path, "$HOME/.cache/wacrd.db"));
}

test "parse schema:" {
    const parsedWaCLISchema = try readTypedConfig(std.testing.allocator, WellKnownSchema, "examples/git.0ut0f.space/.well-known/wacli.json", 2048);
    var AliasesArray = std.MultiArrayList(Aliases){};

    defer {
        parsedWaCLISchema.deinit();
        AliasesArray.deinit(std.testing.allocator);
    }

    const waCLISchema = parsedWaCLISchema.value;

    //const binaryPathLinux = waCLISchema.bin.?.map.get("linux").?[0].map.get("x86").?;
    //std.debug.print("{s}\n", .{binaryPathLinux});
    try std.testing.expect(std.mem.eql(u8, waCLISchema.api.?, "https://git.0ut0f.space/swagger.v1.json"));
    try AliasesArray.insert(std.testing.allocator, 0, .{
        .alias = .{ .string = "issues" },
        .type = .path,
        .content = "/repos/{owner}/{repo}/issues",
    });
    try AliasesArray.append(std.testing.allocator, .{
        .alias = .{ .array = &[_][]const u8{ "c", "create" } },
        .type = .method,
        .content = "POST",
    });
    try AliasesArray.append(std.testing.allocator, .{ .alias = .{ .array = &[_][]const u8{ "d", "delete" } }, .type = .method, .content = "DELETE" });
    try AliasesArray.append(std.testing.allocator, .{ .alias = .{ .string = "tea" }, .type = .bin, .content = "tea" });
    try std.testing.expect(@TypeOf(AliasesArray.get(0)) == @TypeOf(waCLISchema.settings.?.aliases.?[0]));
}
