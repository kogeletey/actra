// The Swift Programming Language
// https://docs.swift.org/swift-book

enum Types {
   case path
   case method
   case bin
   case uri
}

struct Aliases {
   enum Alias {
       case single(String)
       case multiple([String])
   }
   var alias: Alias,
   var type: Types,
   var description: String?,
   var content: String
}

struct Tool {
    var integrity: String,
    var source: String,
    var installPath: String,
    var alias: String?,
    var version: string,
}

typealias Tools = [String : Tool]

struct LockFile {
    var fileVersion: Int = 1,
    var bins: Tools,
    var ains: Tools
}

struct OauthFlows {
    var implict: struct {
        var authrizationUrl:  String
        var scopes: [String: String]
    }
}

struct SettingsAuth {
    enum Scheme {
        case basic
        case bearer
        case oauth2
    }
    var scheme: Scheme?,
    var tokenName: String?
    var flows: OauthFlows?
}

struct WellKnownSettings {
    var contentType: String = "application/json"
    var headers: [String]?
    var aliases:  [Aliases]?
    var auth: SettingsAuth?
}

struct UserSettings {
    dbPath: String = "$HOME/.cache/wacrd.db",
    installDir: String = "$HOME/.local/bin",
    uriSchems: [String : String]?
}

struct WellKnownSchema = struct {
    enum Path {
        var path
    }
    var api: String?
    var registry: Boolean?
    var manifests: [String: Path]?
    var bin: [String : [String : String]]?
    var settings: WellKnownSettings?
}

