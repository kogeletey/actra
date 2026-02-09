---
name: wacli
description: Use wacli to make API requests to any platform that exposes OpenAPI/Swagger JSON; includes discovery, auth, dry-run, and troubleshooting.
---

# wacli: API Requests To Platforms

Use this skill when you want to call a platform API via `wacli` (list endpoints, test routing, make a request, handle auth).

## Quick Workflow

1. Discover the tool spec source
   - Prefer manifest: `https://<host>/.well-known/wacli.json`
   - If absent, `wacli` may fall back to:
     - `https://<host>/openapi.json`
     - `https://<host>/swagger.json`
   - If you need custom aliases/headers/auth locally, create:
     - `$XDG_CONFIG_HOME/wacli/tools/<tool>.json`

2. Validate OpenAPI JSON (internal check)
   - `wacli oas validate <file_or_url>`
   - Exit codes:
     - `0`: ok
     - `2`: unsupported OpenAPI version (valid JSON)
     - `3`: invalid JSON or missing required fields

3. List available operations
   - `wacli help <tool_ref>`

4. Dry-run a request (recommended before real calls)
   - `wacli <tool_ref> [method] <path_tokens...> [key=value...] --dry-run`

Examples:
- `wacli example.org get health --dry-run`
- `wacli example.org get repos alice demo issues page=2 --dry-run`
- `wacli example.org post repos alice demo issues --json '{"title":"hi"}' --dry-run`

## Shell Mode

If you want to call tools directly as commands:
- `eval "$(wacli shell bash example.org)"`
- Then run: `example.org get health --dry-run`

5. Auth (bearer)
   - Store token: `wacli auth <tool_ref> --bearer TOKEN`
   - Then run the request normally (token will be applied in both manifest mode and fallback mode).

## Local Overrides

If you need custom aliases/headers/auth for a platform without publishing a `.well-known/wacli.json`, create:
- `$XDG_CONFIG_HOME/wacli/tools/<tool>.json`

Then `wacli` will use your local settings and prefer any cached spec from `wacli ain <tool_ref>`.

## Troubleshooting

- `manifest not found ...` and no fallback:
  - Provide a `.well-known/wacli.json` manifest on the host, or ensure `openapi.json`/`swagger.json` exists at root.
- `missing or invalid 'paths'`:
  - The JSON is not an OpenAPI document usable for routing.
- `ambiguous operation match`:
  - Your token sequence matches multiple templates; add more path tokens or use a different aliasing strategy in the manifest.
