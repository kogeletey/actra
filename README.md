# Browser command line

The idea is to transform api methods into command line interface

The default shell command, like:

```sh
wacli <tool.dns> <api_methods>
```

You can also install localy

Binary, if exist

```sh
wacli bin <tool.dns>
```

API

```sh
wacli ain <tool.dns>
```

On your website you will need to use `.well-know/wacli.json` file:

```js
{
    "api": "<api_url>",
    "bin": {
        "<platform>": [{
            "<architecture>": "<path_for_file" 
        }]
    }
    "settings": {
        // By default using application json, and it doesn't need to be specified
        "contentType": "application/json",
        "headers": Array<headers>,
        "aliases": [{
            "alias": "<short_hand>" | ["short_hand","long_hand"], 
            "type": "path" | "method" | "bin" | "uri",
            "description": "description of cli command"
            "content": "<path>"
        }],
        "auth": {
            "scheme": "basic" | "bearer" | "oauth2"
            "tokenName": "<name_of_token>" // - bearer
            // oauth2
            "flows": { 
                "implict": {
                    authorizationUrl: "url",
                    scopes: {}
                }
            }
        }
    }
}
```

## Example as:

```json
{
    "api": "https://git.0ut0f.space/swagger.v1.json",
    "settings": {
        "aliases": [
            {
                "alias": "issues",
                "type": "path",
                "content": "/repos/{owner}/{repo}/issues"
            },
            {
              "alias": ["c","create"],
              "type": "method",
              "content": "POST"
            },
            {
              "alias": "tea",
              "type": "bin",
              "content": "tea"
            }
        ]
    },
    "bin": {
      "linux": [{"x86": "https://dl.gitea.com/tea/main/tea-main-linux-amd64.xz"}],
      "windows": [{"x86": "https://dl.gitea.com/tea/main/tea-main-windows-amd64.xz"}],
      "darwin": [
          {"arm64": "https://dl.gitea.com/tea/main/tea-main-darwin-arm64"},
          {"x86": "https://dl.gitea.com/tea/main/tea-main-darwin-amd64.xz"}
      ]
    }
}
```

Next REST API - `https://git.0ut0f.space/api/v1/repos/{owner}/{repo}/issues` method is transform command:

By default - GET request:

```sh
wacli git.0ut0f.space repos issues [owner] [repo]
```

If you need a request other than GET, then add the command

```sh
wacli git.0ut0f.space post|delete|put|path repos issues [owner] [repo]
```

Such requests may require authorization, so you must log in separately:

```sh
wacli auth git.0ut0f.space
```

tokens are stored separately in the database.

Methods can be overridden:

```sh
wacli git.0ut0f.space create repos issues [owner] [repo]
```

By default, all request in clearnet and tor go via `https`, but i2p - `http`.

But sometimes you need to specify a specific protocol

```sh
wacli bin "git+http://git.0ut0f.space/"
```

Binaries is install of user directory `$HOME/.local/bin`, for root user - `/usr/local/bin`.

Perhaps not everyone will add tools to their sites, so for popular tools using directive:

```sh
wacli registry:forgejo repos issues
```

You can create registry, by writing to `.well-know/wacli.json` next lines

```json
{
    "registry": true,
    "manifests": {
        "<name_tool>": {
            "path": "<path_to_file_of_wacli_format>"
        }
    }
}
```

You can also get help on all api methods using the command

```sh
wacli help git.0ut0f.space
```

Settings format is on Linux by address `$HOME/.config/wacli/wacfg.json`

```json
{
    "db_path": "<path_of_secrets_db>",
    "install_dir": "<path_of_install_tools>",
    "uri_schemes": {
        "registry": "<default_registry_website>"
    }
}
```
