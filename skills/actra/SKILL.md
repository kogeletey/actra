---
name: actra
description: Use actra to make API requests to any platform that exposes OpenAPI/Swagger JSON; includes discovery, auth, dry-run, and troubleshooting.
---

# actra: API Requests To Platforms

Use this skill when you want to call a platform API via `actra` (list endpoints, test routing, make a request, handle auth).

## Quick Workflow

1. Discover the tool spec source
   - Prefer manifest: `https://<host>/.well-known/actra.json`
   - If absent, `actra` may fall back to:
     - `https://<host>/openapi.json`
     - `https://<host>/swagger.json`
   - If you need custom aliases/headers/auth locally, create:
     - `$XDG_CONFIG_HOME/actra/tools/<tool>.json`

2. Validate OpenAPI JSON (internal check)
   - `actra oas validate <file_or_url>`
   - Exit codes:
     - `0`: ok
     - `2`: unsupported OpenAPI version (valid JSON)
     - `3`: invalid JSON or missing required fields

3. List available operations
   - `actra help <tool_ref>`

4. Dry-run a request (recommended before real calls)
   - `actra <tool_ref> [method] <path_tokens...> [key=value...] --dry-run`

Examples:
- `actra example.org get health --dry-run`
- `actra example.org get repos alice demo issues page=2 --dry-run`
- `actra example.org post repos alice demo issues --json '{"title":"hi"}' --dry-run`

## Shell Mode

If you want to call tools directly as commands:
- `eval "$(actra shell bash example.org)"`
- Then run: `example.org get health --dry-run`

5. Auth (bearer)
   - Store token: `actra auth <tool_ref> --bearer TOKEN`
   - Then run the request normally (token will be applied in both manifest mode and fallback mode).

## Local Overrides

If you need custom aliases/headers/auth for a platform without publishing a `.well-known/actra.json`, create:
- `$XDG_CONFIG_HOME/actra/tools/<tool>.json`

Then `actra` will use your local settings and prefer any cached spec from `actra ain <tool_ref>`.

## Troubleshooting

- `manifest not found ...` and no fallback:
  - Provide a `.well-known/actra.json` manifest on the host, or ensure `openapi.json`/`swagger.json` exists at root.
- `missing or invalid 'paths'`:
  - The JSON is not an OpenAPI document usable for routing.
- `ambiguous operation match`:
  - Your token sequence matches multiple templates; add more path tokens or use a different aliasing strategy in the manifest.
