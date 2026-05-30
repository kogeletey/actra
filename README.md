# Actra

Actra turns OpenAPI/Swagger sites, local agent providers, and ForgeFed actors
into shell-native commands. It is based on `wacli`, with an added `@` launcher
for agent, file, action, and actor workflows.

Status: v0.1 (Crystal). The core implemented pieces are:
- `.well-known/actra.json` manifest parsing and OpenAPI fetching
- OpenAPI JSON detection (Swagger 2.0, OpenAPI 3.0, OpenAPI 3.1)
- Operation routing by path tokens
- RCL config at `~/.config/actra/config.rcl`
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

## Install from registries

Published JavaScript registry packages install a small launcher named `actra`.
On first run it downloads the matching native binary from the GitHub release,
verifies `SHA256SUMS`, caches it under `~/.cache/actra/npm`, and then executes
the native CLI.

```sh
npm install -g @kogeletey/actra
actra --help
```

The same package metadata is published to JSR as `@kogeletey/actra`.

## Packaging and Release Artifacts

Packaging assets and scripts live in `.meta/packaging`.

Release artifacts are built with:
- Native Crystal builds in GitHub Actions (no `mise` in CI)
- Tarballs named `actra-<version>-<os>-<arch>-<link_mode>.tar.gz`
- `dist/SHA256SUMS` checksum file
- Homebrew formula generated at `.meta/packaging/homebrew/actra.rb`
- Homebrew release tooling at `.github/workflows/homebrew-formula.yml`
- Container image published to `ghcr.io/<owner>/actra`
- Nix flake package and release helper:
  - `flake.nix`
  - `.meta/packaging/scripts/package-via-nix.sh`
- npm package published as `@kogeletey/actra`
- JSR package published as `@kogeletey/actra`

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
@ "review this patch"
@ ollama "explain this repository"
@alice@mastodon.social "create a federated task"
@example.org get ping --dry-run
?example.org
? example.org
?example.org docs
```

`@actor@domain.name` creates a ForgeFed task for the actor inbox at
`https://domain.name/users/actor/inbox`, which matches common Mastodon/Pleroma
layouts. `@domain.name` uses the OpenAPI flow. `?tool` prints tool information
by default and can generate Markdown docs with `?tool docs`. Bare `@ text`
goes to the default configured agent provider and default model
`@auto@lefine.pro`; `@ <provider> text` runs through that provider, and
`@ <model> text` runs the default provider with the selected model.

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
actra --list-prompts
actra --prompt review "review this patch"
actra --prompt debug "why does Tab flicker?"
actra --export <session-id> session.html
actra -c "continue the last session"
actra --fork <session-id> "try a different approach"
```

Zerostack-style prompt modes are built in. The default is `code`; available
modes are `default`, `code`, `plan`, `review`, `debug`, `ask`, `brainstorm`,
`frontend-design`, `review-security`, `simplify`, and `write-prompt`. Use
`--prompt <mode>` or `--prompt-mode <mode>` with `actra` or `actra agent`.

RPC is JSONL over stdin/stdout. Minimal prompt command:

```json
{"id":"req-1","type":"prompt","message":"Hello"}
```

Provider config is RCL-native:

```rcl
base do
  default_provider = "openai"
  default_model = "@auto@lefine.pro"
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

ForgeFed actors can also be exposed as agent providers. The provider posts the
prompt as a ForgeFed `Create(Ticket)` to the configured actor inbox:

```rcl
provider "remote-code" do
  api = "forgefed"
  server = "lefine.pro"
  actor = "code"
end
```

Specific `@` actions can choose optimized agent defaults without changing the
global provider:

```rcl
at do
  action "review" do
    kind = "agent"
    label = "Review"
    provider = "remote-code"
    model = "ticket"
    prompt_modes = ["review"]
  end
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

The shell activation does not install direct `@claude` or `@codex` shortcuts;
use configured providers from the `@` launcher or explicit dispatch commands
when a local bridge is required.

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
@
@ cli
@ rev
actra -p '@src/actra/cli.cr' '@README.md' "review these files"
```

Bare `@ text` starts the default agent. Bare `@` prints quick agent/action/file
results below the prompt. Press `Tab`
or `j`/`k` on an `@...` line to move forward/backward through actions, with
`Shift+Tab` also available as a fallback for backward navigation. The shell prints
the selected action and its preview inline in the same terminal window. Actions
cycle through run, background, remote, and container. Model rows such as
`model   @auto@lefine.pro (default)` can be selected as `@ @auto@lefine.pro ...`
to keep the default provider and override only the model. Provider rows such as
`agent   openai (default)` and `agent   ollama` can be selected as `@ openai ...`
or `@ ollama ...`.
Selecting a file opens a file action menu: insert a shell-safe `@path`, open it
with the matching `filetype` editor, copy or insert its absolute path, run it,
delete it, or `cd` to its folder. Actra expands `@path` prompt arguments into file
contents. `actra activate <bash|zsh>` also installs completion for configured
actors and local `@path` prompt attachments.

Explicit command routing:

```sh
@search "forgefed inbox examples"
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
actra launch --mode container --runtime podman --image alpine:latest @example.org get ping
actra launch --mode container --runtime containerd --image alpine:latest @example.org get ping
actra launch --mode background @example.org get ping
```

`?tool` is an informational shortcut. Use `?tool launch` when you want the
remote/container/background launcher. Background launches write logs under
`$XDG_CACHE_HOME/actra/launches` and keep running after the terminal exits.
Container mode requires `--image` or `ACTRA_LAUNCH_IMAGE` and uses Docker by
default. Override the runtime with `--runtime`, `ACTRA_LAUNCH_RUNTIME`, or
`ACTRA_CONTAINER_RUNTIME`; supported compatible runtimes are `docker`,
`podman`, `nerdctl`, and `containerd` (via `nerdctl`). Remote Lefine mode
submits a task to `@remote@lefine.pro` by default; override it with
`--remote @actor@domain` or `ACTRA_LAUNCH_REMOTE`.

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
- `--json @path.json` reads request JSON from a file.
- `--render auto|table|json|raw` formats JSON output (default: `auto`) for request output.
- `--out PATH` saves the response to a file (use `--out -` to force raw bytes to stdout).
- For `POST/PUT/PATCH` without `--json`, `actra` prompts interactively when stdin is a TTY (disable with `--no-interactive`).
- `--dry-run` prints the resolved request instead of sending it.

## Output rendering

Use `--render table|json|raw|auto` with normal request commands to control JSON output formatting.

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
- `$XDG_CONFIG_HOME/actra/config.rcl` (default: `$HOME/.config/actra/config.rcl`)
- legacy fallback: `$XDG_CONFIG_HOME/astra/config.rcl`

Migration:

```sh
actra config migrate
actra config update
```

Both commands move a legacy `astra/config.rcl` into the current `actra/config.rcl`
path when needed. Existing current config files are validated and left untouched.

Example:

```rcl
base do
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

## Local agent providers and permissions

Actra ships OpenAI-compatible local provider presets for Ollama and llama.cpp:

```sh
actra --provider ollama --model llama3.1:8b "explain this repo"
@ ollama "fix this bug"
actra --provider llama.cpp --model local "summarize README"
@ llamacpp "trace config loading"
```

Agent tool permissions can be selected per run:

```sh
actra --restrictive "inspect this repo"
actra --permission-mode accept "trusted extension flow"
actra --accept-all "use tools without prompting inside this session"
actra --yolo "trusted local automation"
actra --sandbox "run shell tools through bwrap when available"
actra --permission-state --session <session-id>
actra --session <session-id> --permission-allow read:README.md
actra --session <session-id> --permission-deny 'bash:make *'
actra --session <session-id> --permission-revoke read:README.md
actra --session <session-id> --permission-clear
```

The permission state JSON includes `session_id` and `session_path`, so callers
can keep using the same session after a direct CLI mutation creates or resolves
one.

`accept` and `accept-all` are accepted permission mode names in config/RPC; the
CLI flag is `--accept-all`.

RCL config supports a top-level permissions block:

```rcl
permissions do
  default_mode = "standard"
  sandbox = false
  doom_loop_threshold = 8

  tool "read" do
    allow = ["src/**", "README.md"]
    ask = ["tmp/**"]
    deny = ["/etc/**"]
  end
end
```

For overlapping per-tool patterns, precedence is `deny`, then `ask`, then
`allow`; default mode behavior applies only when no explicit rule matches.

JSONL RPC sessions can inspect and update permission state without a TTY prompt:

```json
{"id":"1","type":"permissions"}
{"id":"2","type":"permission_mode","mode":"restrictive"}
{"id":"3","type":"permission_allow","tool":"read","pattern":"README.md"}
{"id":"4","type":"prompt","message":"read README.md and summarize it"}
```

A saved allowlist grant can be revoked in the same JSONL session:

```json
{"id":"5","type":"permission_revoke","tool":"read","pattern":"README.md"}
```

Pending requests can also be dismissed or denied without granting future access:

```json
{"id":"6","type":"permission_deny","tool":"read","pattern":"README.md"}
```

Extension tools are also permission-checked. Use a session grant or an explicit mode
when you trust an extension tool:

```sh
actra --accept-all --extension .actra/extensions/tool.cr "use this extension tool"
```

Permission state payloads include `mode_source` and `sandbox_source` so JSON/RPC
clients can distinguish config values from CLI/RPC overrides.

When a non-interactive tool call requires approval, the active session records a
`permissionRequest` entry and exposes unresolved requests in the JSON/RPC
permission state `requests` array. Session grants support glob patterns such as
`src/**` and remove matching requests from the pending list; revoking the grant
makes matching requests pending again.

Session denials are enforced on future matching tool calls in the same session,
not only hidden from the pending request list.

Pending permission requests include `reason` and `count` metadata when available;
`reason` is `policy` for normal policy asks and `doom-loop` when the repeated
request threshold is hit.

For the same `tool` + `pattern`, session permission decisions are replayed in
order: later `permission_allow`, `permission_deny`, and `permission_revoke`
entries supersede earlier entries.

Use `permission_clear` or `--permission-clear` to clear all effective session
permission decisions while preserving the append-only session history.

Permission state also includes `decisions`, a latest-wins effective list of
session allow/deny decisions by `tool` + `pattern`; `allowlist` and `denials`
are derived views of the same replay result.
