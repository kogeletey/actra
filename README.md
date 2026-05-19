# Actra

Actra turns OpenAPI/Swagger sites and ForgeFed actors into shell-native commands.
It is based on `wacli`, with an added `@*` shell dispatch layer for actor tasks
such as `@code`, `@plan`, and `@actor@domain.name`.

Status: v0.1 (Crystal). The core implemented pieces are:
- `.well-known/actra.json` manifest parsing and OpenAPI fetching
- OpenAPI JSON detection (Swagger 2.0, OpenAPI 3.0, OpenAPI 3.1)
- Operation routing by path tokens
- RCL config at `~/.config/astra/config.rcl`
- `actra activate` shell hooks for `@*` commands
- ForgeFed `Create(Ticket)` dry-run and delivery helpers
- Pi-like agent modes: print, JSON events, JSONL RPC, sessions, and extension hooks
- OpenAI Responses and OpenAI Chat Completions compatible providers
- OpenAI function/tool calls with built-in `read`, `ls`, `grep`, `find`, `bash`, `write`, and `edit` tools
- `actra oas validate` internal compatibility check

## Build (native Crystal)

1. Install Crystal (1.8+) and `shards` on your platform.

2. Install dependencies and run tests:

```sh
shards install
crystal spec
```

3. Build:

```sh
shards build --release
```

The binary will be at `bin/actra`.

## Packaging and Release Artifacts

Packaging assets and scripts live in `.meta/packaging`.

Release artifacts are built with:
- Native Crystal builds in GitHub Actions (no `mise` in CI)
- Tarballs named `actra-<version>-<os>-<arch>-<link_mode>.tar.gz`
- `dist/SHA256SUMS` checksum file
- Homebrew formula generated at `.meta/packaging/homebrew/actra.rb`
- Container image published to `ghcr.io/<owner>/actra`

Lua release download helper:
- `.meta/packaging/mise/download.lua`

## CLI

### Activate shell commands

Print shell integration:

```sh
eval "$(actra activate zsh)"
```

Install the integration into your shell rc file:

```sh
actra activate zsh --install
```

After activation:

```sh
@code "review this patch"
@plan "split this implementation into steps"
@claude "use Claude SDK auth"
@codex "use Codex API auth"
@alice@mastodon.social "create a federated task"
@example.org get ping --dry-run
?example.org
? example.org
?example.org docs
```

`@actor@domain.name` creates a ForgeFed task for the actor inbox at
`https://domain.name/users/actor/inbox`, which matches common Mastodon/Pleroma
layouts. `@domain.name` uses the OpenAPI flow. `?tool` prints tool information
by default and can generate Markdown docs with `?tool docs`. Actor commands such
as `@code` and `@plan` come from `config.rcl`; `@claude` and `@codex` are local
CLI bridges for `claude -p` and `codex exec`.

### Configure Actra

```sh
actra config init
actra config validate
actra config print
```

### Agent mode

Print one answer and exit:

```sh
actra -p "summarize this repo"
cat README.md | actra -p "summarize this text"
actra "plain text goes to the default provider"
```

Pi-like machine modes:

```sh
actra --mode json "explain this file" @src/actra/cli.cr
actra --mode rpc
actra --list-models
actra --export <session-id> session.html
actra -c "continue the last session"
actra --fork <session-id> "try a different approach"
```

RPC is JSONL over stdin/stdout. Minimal prompt command:

```json
{"id":"req-1","type":"prompt","message":"Hello"}
```

Provider config is RCL-native:

```rcl
base do
  default_provider = "openai"
  default_model = "gpt-4.1-mini"
end

provider "openai" do
  api = "openai-responses"
  base_url = "https://api.openai.com/v1"
  api_key = "OPENAI_API_KEY"
  auth_header = true
end

provider "openai-chat" do
  api = "openai-completions"
  base_url = "https://api.openai.com/v1"
  api_key = "OPENAI_API_KEY"
  auth_header = true
end
```

`api_key` can be an environment variable name, a literal token, or a shell command prefixed with `!`.

Shell auth helpers keep Lefine as the primary profile and expose standard SDK/API
environment variables without printing secret values:

```sh
eval "$(actra auth shell bash)"
actra_auth_status
```

- Lefine: `LEFINE_TOKEN`
- Claude CLI/SDK: `ANTHROPIC_API_KEY`
- Codex CLI/OpenAI API: `OPENAI_API_KEY`

`@claude` calls `claude -p <task>` by default. Override the binary with
`ACTRA_CLAUDE_CLI`. `@codex` calls `codex exec <task>` by default. Override the
binary with `ACTRA_CODEX_CLI`.

Extension hooks run external commands with a JSON event on stdin. If the command prints JSON, that JSON replaces the payload for the next step:

```rcl
extension "rewrite" do
  command = "crystal run src/actra.cr -- __cr-extension .actra/extensions/rewrite.cr"
  events = ["input", "before_provider_request", "agent_end"]
end
```

Extensions can also be loaded explicitly or discovered from `.actra/extensions`
and `~/.config/actra/extensions`:

```sh
actra -p --extension .actra/extensions/rewrite.cr "hello"
actra -p --no-extensions "hello"
```

Crystal extensions can use a Pi-like API:

```crystal
Actra::Extension.run do |pi|
  pi.on("before_provider_request") do |_payload|
    JSON.parse({"model" => "test-model", "input" => "rewritten"}.to_json)
  end

  schema = JSON.parse({"type" => "object", "properties" => {"text" => {"type" => "string"}}}.to_json)
  pi.register_tool("crystal_echo", "Echo text from Crystal", schema) do |args|
    "crystal says: #{args["text"].as_s}"
  end

  pi.register_command("hello", "Say hello") do |args|
    "hello #{args}"
  end
end
```

Prompt templates and skills can be injected as files:

```sh
actra -p --prompt-template .actra/prompts/review.md @src/actra/cli.cr
actra -p --skill ./skills/actra "use the local workflow"
```

Pick local files for prompt context:

```sh
actra activate bash --install
@file
actra -p '@src/actra/cli.cr' '@README.md' "review these files"
@?
```

`@file` opens a bottom `fzf` picker. After choosing a file, it opens an action
menu: attach it as a shell-safe `@path` token, open it in the default editor, or
copy its absolute path. Actra expands `@path` prompt arguments into file
contents. `actra activate <bash|zsh>` also installs completion for `@file`,
`@?`, configured actors such as `@code`, and local `@path` prompt attachments.
`@?` prints the shortcut help.

Explicit command routing:

```sh
@search "forgefed inbox examples"
@code "fix parser"
actra "what is ForgeFed?"
```

Actra classifies bare input before request dispatch:
- plain text goes to the default provider
- domain-like refs, such as `example.org`, keep using the OpenAPI flow
- non-standard or remote commands use explicit `@name` shell routing

Tool info, docs, and launch:

```sh
?example.org
? example.org
?example.org help get ping
?example.org docs --out example.md
?example.org docs post things
?example.org launch
actra launch --mode remote-lefine @example.org get ping
actra launch --mode container --image alpine:latest @example.org get ping
actra launch --mode background @example.org get ping
@ printf ok
```

`?tool` is an informational shortcut. Use `?tool launch` when you want the
remote/container/background launcher. Background launches write logs under
`$XDG_CACHE_HOME/actra/launches` and keep running after the terminal exits.
Container mode requires `--image` or `ACTRA_LAUNCH_IMAGE`. Remote Lefine mode
submits a task to `@code` by default; override it with `--remote @actor` or
`ACTRA_LAUNCH_REMOTE`. `@ <command...>` opens the same lightweight picker for
ad hoc commands: run in the background, send the resolved command path and
command line to the assistant, or run locally.

Agent tools are enabled by default. Restrict or disable them with:

```sh
actra -p --tools read,grep "inspect this repo"
actra -p --no-builtin-tools --extension .actra/extensions/tool.cr "use extension tools only"
actra -p --no-tools "answer without tools"
```

### Validate OpenAPI JSON compatibility

```sh
actra oas validate <file_or_url>
```

Exit codes:
- `0`: compatible (parseable + has `paths`)
- `2`: valid JSON but unsupported OpenAPI version
- `3`: invalid JSON or missing required OpenAPI fields (for v0.1: missing/invalid `paths`)

### Fetch tool spec (`ain`)

Downloads a tool manifest, then downloads its OpenAPI JSON and caches it (and records it in the lock file).

```sh
actra ain @<tool_ref>
```

### Show tool operations (`help`)

```sh
actra help @<tool_ref>
```

### Store bearer token

```sh
actra auth @<tool_ref> --bearer TOKEN
actra auth shell <bash|zsh>
```

Tokens are stored in a sqlite DB (`db_path` from config).
The token is applied in both modes:
- manifest mode (`.well-known/actra.json`)
- fallback mode (`/openapi.json` or `/swagger.json`)

### Execute a request (v0.1)

```sh
actra @<tool_ref> [method] <path_tokens...> [key=value...] [--json STR] [--header k:v] [--render MODE] [--out PATH] [--interactive|--no-interactive] [--dry-run]
```

Notes:
- `method` is optional; defaults to `GET`.
- `path_tokens` are matched against an OpenAPI path template. Example template `/repos/{owner}/{repo}/issues` matches tokens `repos alice demo issues`.
- `key=value` args become query parameters.
- `--json` sets the request body and defaults `Content-Type` to `application/json` if not already specified in headers.
- `--json @file.json` reads request JSON from a file.
- `--render auto|table|json|raw` formats JSON output (default: `auto`).
- `--out PATH` saves the response to a file (use `--out -` to force raw bytes to stdout).
- For `POST/PUT/PATCH` without `--json`, `actra` prompts interactively when stdin is a TTY (disable with `--no-interactive`).
- `--dry-run` prints the resolved request instead of sending it.

## Render JSON (like a minimal formatter)

```sh
cat response.json | actra render --render table
actra render --in response.json --render json
```

## Shell Mode (bash/zsh)

The old OpenAPI alias mode is still available:

```sh
eval "$(actra shell bash @example.org)"
example.org get ping --dry-run
?example.org
```

For all locally installed/cached tools (from `actra.lock`):

```sh
eval "$(actra shell bash --installed)"
```

## Tool Reference (`tool_ref`)

`tool_ref` forms:
- `example.com` (assumes `https://example.com`)
- `https://example.com` (explicit)
- `registry:<name>` (resolved using config `uri_schemes.registry`)

## Website Manifest: `.well-known/actra.json`

Your website should host:
- `https://<host>/.well-known/actra.json`

For backward compatibility, `actra` also tries:
- `https://<host>/.well-know/actra.json` (deprecated)

Fallback (when no manifest exists):
- `https://<host>/openapi.json`
- `https://<host>/swagger.json`

In fallback mode, `actra` treats the OpenAPI JSON as the tool spec (no headers/aliases/auth from a manifest).

## Resolution Order (What actra Tries First)

When you run `actra @<tool_ref> ...`, the resolution order is:

1. Local tool manifest override: `$XDG_CONFIG_HOME/actra/tools/<tool>.json` (for aliases/headers/auth)
2. Local cached OpenAPI JSON from `actra ain @<tool_ref>` (for the OpenAPI spec)
3. Remote manifest: `https://<host>/.well-known/actra.json` (then `/.well-know/actra.json`)
4. Remote fallback: `https://<host>/openapi.json` then `https://<host>/swagger.json`

## Local Tools And Aliases

You can define local per-tool aliases/headers/auth by creating a local manifest override:

- `$XDG_CONFIG_HOME/actra/tools/<tool>.json` (default: `$HOME/.config/actra/tools/<tool>.json`)

Where `<tool>` is derived from the tool reference (for example `example.org.json`).
This file has the same schema as `.well-known/actra.json` (tool manifest).

You can also pass a manifest file path directly as `@<tool_ref>`:

```sh
actra help @example.org
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

A registry is also served from `.well-known/actra.json` but sets `registry: true` and a `manifests` map:

```json
{
  "registry": true,
  "manifests": {
    "forgejo": { "path": "https://actra.ofs.lol/registry/forgejo.json" }
  }
}
```

When `tool_ref` is `registry:forgejo`, actra:
1. Loads the registry base URL from config `uri_schemes.registry`
2. Fetches the registry manifest from its `.well-known/actra.json`
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

## Local Config: `config.rcl`

Path:
- `$XDG_CONFIG_HOME/astra/config.rcl` (default: `$HOME/.config/astra/config.rcl`)
- legacy fallback: `$XDG_CONFIG_HOME/actra/config.rcl`

Example:

```rcl
base do
  default_server = "lefine.pro"
  db_path = "$HOME/.cache/actra/actra.db"
  install_dir = "$HOME/.local/bin"
end

uri_schemes do
  registry = "https://actra.ofs.lol"
end

filetype "code" do
  extensions = [".cr", ".rb", ".py", ".js", ".ts", ".go", ".rs"]
  editor = "nvim"
end

filetype "markdown" do
  extensions = [".md", ".markdown", ".org"]
  editor = "code --reuse-window {}"
end

filetype "images" do
  patterns = ["*.png", "*.jpg", "*.jpeg", "*.gif", "*.webp"]
  editor = "xdg-open"
end

server "lefine.pro" do
  base_url = "https://lefine.pro"
  actor_id = "https://lefine.pro/actor/shell"
  inbox = "/inbox"
  outbox = "/outbox"

  http_signature do
    key_id = "https://lefine.pro/actor/shell#main-key"
    private_key_path = "$HOME/.config/actra/keys/shell.pem"
    algorithm = "rsa-sha256"
  end

  actor "code" do
    command = "@code"
    inbox = "/inbox/code"
    outbox = "/outbox/code"
    work_type = "code"
  end

  actor "plan" do
    command = "@plan"
    inbox = "/inbox/plan"
    outbox = "/outbox/plan"
    work_type = "plan"
  end
end
```

## Lock File: `actra.lock`

Path:
- `$XDG_CONFIG_HOME/actra/actra.lock`

v0.1 writes `ains` entries when you run `actra ain @<tool_ref>`.

## Examples

See:
- `examples/re128.org/.well-known/actra.json`
- `examples/wareg.re128.org/.well-known/actra.json`
- `examples/settings.json`

## Skill

This repo includes a skill for using `actra` against platform APIs (discovery, dry-run, auth, troubleshooting):
- `skills/actra/SKILL.md`

To install it into Codex:

```sh
mkdir -p ~/.codex/skills
ln -s "$(pwd)/skills/actra" ~/.codex/skills/actra
```

Skill metadata name is `actra` (file stays in that folder).
