# wacli

Turn a website's OpenAPI/Swagger JSON into a CLI.

Status: v0.1 (Crystal). The core implemented pieces are:
- `.well-known/wacli.json` manifest parsing and fetching
- OpenAPI JSON detection (Swagger 2.0, OpenAPI 3.0, OpenAPI 3.1)
- Operation routing by path tokens
- `wacli oas validate` internal compatibility check

## Install (mise)

This repo is intended to be built with `mise`.

1. Install tools:

```sh
mise install
```

2. Install Crystal deps and run tests:

```sh
mise exec -- shards install
mise run test
```

3. Build:

```sh
mise run build
```

The binary will be at `bin/wacli`.

## CLI

### Validate OpenAPI JSON compatibility

```sh
wacli oas validate <file_or_url>
```

Exit codes:
- `0`: compatible (parseable + has `paths`)
- `2`: valid JSON but unsupported OpenAPI version
- `3`: invalid JSON or missing required OpenAPI fields (for v0.1: missing/invalid `paths`)

### Fetch tool spec (`ain`)

Downloads a tool manifest, then downloads its OpenAPI JSON and caches it (and records it in the lock file).

```sh
wacli ain <tool_ref>
```

### Show tool operations (`help`)

```sh
wacli help <tool_ref>
```

### Store bearer token

```sh
wacli auth <tool_ref> --bearer TOKEN
```

Tokens are stored in a sqlite DB (`db_path` from config).
The token is applied in both modes:
- manifest mode (`.well-known/wacli.json`)
- fallback mode (`/openapi.json` or `/swagger.json`)

### Execute a request (v0.1)

```sh
wacli <tool_ref> [method] <path_tokens...> [key=value...] [--json STR] [--header k:v] [--render MODE] [--out PATH] [--interactive|--no-interactive] [--dry-run]
```

Notes:
- `method` is optional; defaults to `GET`.
- `path_tokens` are matched against an OpenAPI path template. Example template `/repos/{owner}/{repo}/issues` matches tokens `repos alice demo issues`.
- `key=value` args become query parameters.
- `--json` sets the request body and defaults `Content-Type` to `application/json` if not already specified in headers.
- `--json @file.json` reads request JSON from a file.
- `--render auto|table|json|raw` formats JSON output (default: `auto`).
- `--out PATH` saves the response to a file (use `--out -` to force raw bytes to stdout).
- For `POST/PUT/PATCH` without `--json`, `wacli` prompts interactively when stdin is a TTY (disable with `--no-interactive`).
- `--dry-run` prints the resolved request instead of sending it.

## Render JSON (like a minimal formatter)

```sh
cat response.json | wacli render --render table
wacli render --in response.json --render json
```

## Shell Mode (bash/zsh)

To call tools directly from your shell without typing `wacli` each time, generate aliases:

```sh
eval "$(wacli shell bash example.org)"
example.org get ping --dry-run
```

For all locally installed/cached tools (from `wa.lock`):

```sh
eval "$(wacli shell bash --installed)"
```

## Tool Reference (`tool_ref`)

`tool_ref` forms:
- `example.com` (assumes `https://example.com`)
- `https://example.com` (explicit)
- `registry:<name>` (resolved using config `uri_schemes.registry`)

## Website Manifest: `.well-known/wacli.json`

Your website should host:
- `https://<host>/.well-known/wacli.json`

For backward compatibility, `wacli` also tries:
- `https://<host>/.well-know/wacli.json` (deprecated)

Fallback (when no manifest exists):
- `https://<host>/openapi.json`
- `https://<host>/swagger.json`

In fallback mode, `wacli` treats the OpenAPI JSON as the tool spec (no headers/aliases/auth from a manifest).

## Resolution Order (What wacli Tries First)

When you run `wacli <tool_ref> ...`, the resolution order is:

1. Local tool manifest override: `$XDG_CONFIG_HOME/wacli/tools/<tool>.json` (for aliases/headers/auth)
2. Local cached OpenAPI JSON from `wacli ain <tool_ref>` (for the OpenAPI spec)
3. Remote manifest: `https://<host>/.well-known/wacli.json` (then `/.well-know/wacli.json`)
4. Remote fallback: `https://<host>/openapi.json` then `https://<host>/swagger.json`

## Local Tools And Aliases

You can define local per-tool aliases/headers/auth by creating a local manifest override:

- `$XDG_CONFIG_HOME/wacli/tools/<tool>.json` (default: `$HOME/.config/wacli/tools/<tool>.json`)

Where `<tool>` is derived from the tool reference (for example `example.org.json`).
This file has the same schema as `.well-known/wacli.json` (tool manifest).

You can also pass a manifest file path directly as `<tool_ref>`:

```sh
wacli help example.org 
```

### Tool Manifest

Minimal:

```json
{
  "api": "https://example.com/openapi.json"
}
```

Full (v0.1 fields):

```json
{
  "api": "https://example.com/openapi.json",
  "settings": {
    "headers": [
      { "name": "Accept", "value": "application/json" }
    ],
    "aliases": [
      {
        "alias": "issues",
        "type": "path",
        "content": "/repos/{owner}/{repo}/issues"
      }
    ],
    "auth": {
      "scheme": "bearer",
      "tokenName": "Authorization"
    }
  }
}
```

Alias behavior (v0.1):
- `type: "path"` aliases replace a matching token with `content` split by `/`.
- Placeholder segments like `{owner}` will consume subsequent CLI tokens as values.

Auth behavior (v0.1):
- Only `bearer` is implemented.
- `tokenName` is treated as the header name. If it is `"Authorization"`, the header value becomes `Bearer <token>`. Otherwise the token is sent as-is.

### Registry Manifest

A registry is also served from `.well-known/wacli.json` but sets `registry: true` and a `manifests` map:

```json
{
  "registry": true,
  "manifests": {
    "forgejo": { "path": "https://wacli.ofs.lol/registry/forgejo.json" }
  }
}
```

When `tool_ref` is `registry:forgejo`, wacli:
1. Loads the registry base URL from config `uri_schemes.registry`
2. Fetches the registry manifest from its `.well-known/wacli.json`
3. Fetches `manifests.forgejo.path` as the tool manifest

## OpenAPI Support (v0.1)

Accepted versions:
- Swagger 2.0 (`"swagger": "2.x"`)
- OpenAPI 3.0 (`"openapi": "3.0.x"`)
- OpenAPI 3.1 (`"openapi": "3.1.x"`)

Routing:
- The selected operation is matched by `method` + path template segment match.
- Template segments like `{id}` match any token and are extracted as path parameters.

Base URL:
- Swagger 2.0: `schemes[0]://host + basePath` (falls back to `tool_ref` base if missing)
- OpenAPI 3.x: `servers[0].url` (falls back to `tool_ref` base if missing)

## Local Config: `wacfg.json`

Path:
- `$XDG_CONFIG_HOME/wacli/wacfg.json` (default: `$HOME/.config/wacli/wacfg.json`)

Example:

```json
{
  "db_path": "$HOME/.cache/wacrd.db",
  "install_dir": "$HOME/.local/bin",
  "uri_schemes": {
    "registry": "https://wareg.re128.org"
  }
}
```

## Lock File: `wa.lock`

Path:
- `$XDG_CONFIG_HOME/wacli/wa.lock`

v0.1 writes `ains` entries when you run `wacli ain <tool_ref>`.

## Examples

See:
- `examples/re128.org/.well-known/wacli.json`
- `examples/wareg.re128.org/.well-known/wacli.json`
- `examples/settings.json`

## Skill

This repo includes a skill for using `wacli` against platform APIs (discovery, dry-run, auth, troubleshooting):
- `skills/wacli/SKILL.md`

To install it into Codex:

```sh
mkdir -p ~/.codex/skills
ln -s "$(pwd)/skills/wacli" ~/.codex/skills/wacli
```

Skill metadata name is `wacli` (file stays in that folder).
