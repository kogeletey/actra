const std = @import("std");

const OauthFlows = struct { implict: struct { authrizationUrl: []const u8, scopes: std.StringHashMap([]const u8) } };

const WellKnownSettings = struct {
    contentType: []const u8 = "application/json",
    headers: ?[]const ([]const u8),
    aliases: ?[]const struct { aliases: union { string: []const u8, array: []const []const u8 }, type: enum { path, method, bin, uri }, description: ?[]const u16, content: ?[]const u8 },
    auth: ?struct { scheme: enum { basic, bearer, oauth2 }, tokenName: ?[]const u8, flows: ?OauthFlows },
};

const WellKnownSchema = struct { api: ?[]const u8, registry: bool = false, manifests: ?std.StringHashMap(struct { path: []const u8 }), bin: ?[]const std.StringHashMap([]const u8), settings: WellKnownSettings };

const UserSettings = struct { db_path: []const u8 = "$HOME/.cache/wacrd.bin", install_dir: []const u8 = "$HOME/.local/bin", uri_shemes: ?std.StringHashMap([]const u8) };

pub fn main() !void {}

test "spec" {}
