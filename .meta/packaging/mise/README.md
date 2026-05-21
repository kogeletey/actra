# Lua release download helper

This helper downloads a published `actra` release tarball, verifies it using `SHA256SUMS`, and installs the binary.

## Usage

```sh
lua .meta/packaging/mise/download.lua <version> [os] [arch] [dynamic|static] [install_dir]
```

Examples:

```sh
lua .meta/packaging/mise/download.lua 0.1.0 linux amd64 dynamic ./bin
lua .meta/packaging/mise/download.lua v0.1.0 darwin arm64 dynamic /usr/local/bin
```

Environment:

- `GITHUB_REPOSITORY` (optional): defaults to `kogeletey/actra`
