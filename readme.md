# Command line getting from browser

The idea is to transform api methods in command line interface

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

```jsonc
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
        "aliases": [{
            "alias": "<short_hand>" | ["short_hand","long_hand"], 
            "type": "path" | "method",
            "description": "description of cli command"
            "path": "<path>"
        }],
        "auth": {
            "sheme": "basic" | "bearer" | "oauth2"
            "token": "<name_of_token>" // - bearer
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
    "api": "https://codeberg.org/api/v1",
    "settings": {
        "aliases": [
            {
                "alias": "i",
                "type": "path",
                "path": "/repos/{owner}/{repo}/issues"
            },
            {
              "alias": "create",
              "type": "method",
              "method": "POST"
            },
            {
              "alias": "tea",
              "type": "bin",
              "bin": "tea"
            }
        ]
    },
    "bin": {
      "linux": [{"x86": "https://dl.gitea.com/tea/main/tea-main-linux-amd64.xz"}]
    }
}
```

Next REST API - `https://codeberg.org/api/v1/repos/{owner}/{repo}/issues` method is transform command:

By default - GET request:

```sh
wacli codeberg.org repos issues [owner] [repo]
```

If you need a request other than GET, then add the command

```sh
wacli codeberg.org post|delete|put|path repos issues [owner] [repo]
```

Such requests may require authorization, so you must log in separately:

```sh
wacli auth codeberg.org
```

tokens are stored separately in the database.

Methods can be overridden:

```sh
wacli codeberg.org create repos issues [owner] [repo]
```

By default, all request in clearnet and tor go via `https`, but i2p - `http`.

But sometimes you need to specify a specific protocol

```sh
pwact bin "git+http://codeberg.org/"
```

Binaries is install of user directory `$HOME/.local/bin`, for root user - `/usr/local/bin`.
