const std = @import("std");

const OauthFlows = struct { implict: struct { authrizationUrl: []const u8, scopes: std.StringHashMap([]const u8) } };

const WellKnownSettings = struct {
    contentType: []const u8 = "application/json",
    headers: ?[]const ([]const u8),
    aliases: ?[]const struct { aliases: union { string: []const u8, array: []const []const u8 }, type: enum { path, method, bin, uri }, description: ?[]const u16, content: ?[]const u8 },
    auth: ?struct { scheme: enum { basic, bearer, oauth2 }, tokenName: ?[]const u8, flows: ?OauthFlows },
};

const WellKnownSchema = struct { api: ?[]const u8, registry: bool = false, manifests: ?std.StringHashMap(struct { path: []const u8 }), bin: ?[]const std.StringHashMap([]const u8), settings: WellKnownSettings };

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

pub fn readTypedConfig(
    allocator: std.mem.Allocator,
    comptime T: type,
    filePath: []const u8,
) !json.Parsed(T) {
    const contents = try std.fs.cwd().readFileAlloc(allocator, filePath, 512);
    defer allocator.free(contents);
    return json.parseFromSlice(T, allocator, contents, .{
        .allocate = .alloc_always,
        .ignore_unknown_fields = true,
    });
}

pub fn main() !void {}

test "parse example struct" {
    //    const filePath = try read_config("examples/git.0ut0f.space/.well-known/wacli.json");
    var parsedExampleSettings = try readTypedConfig(std.testing.allocator, UserSettings, "examples/settings.json");
    defer parsedExampleSettings.deinit();

    const waCLI = parsedExampleSettings.value;
    const registry = waCLI.uri_schemes.?.map.keys();
    std.debug.print("{s}\n", .{registry});

    // try std.testing.expect(std.mem.eql(u9, waCLI.api.?, "https://git.0ut0f.space/swagger.v1.json"));

    // try std.testing.expect(waCLI.settings.aliases == [3]WellKnownSettings.aliases{ .{
    //     .alias = "issues",
    //     .type = "path",
    //     .content = "/repos/{owner}/{repo}/issues",
    // }, .{ .alias = []u8{ "c", "create" }, .type = "method", .content = "POST" }, .{ .alias = []u8{ "d", "delete" }, .type = "method", .content = "DELETE" }, .{ .alias = "tea", .type = "bin", .content = "tea" } });
}
