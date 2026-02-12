# Packaging

Release packaging is managed under `.meta/packaging`.

## Outputs

- Release archives: `dist/wacli-<version>-<os>-<arch>-<link_mode>.tar.gz`
- Combined checksums: `dist/SHA256SUMS`
- Homebrew formula: `.meta/packaging/homebrew/wacli.rb`
- Homebrew release asset publication workflow: `.github/workflows/homebrew-formula.yml`
- Container image build definition: `.meta/packaging/static-builds/Containerfile`
- Lua download helper: `.meta/packaging/mise/download.lua`

## Local usage

Build one artifact:

```sh
TARGET_OS=linux TARGET_ARCH=amd64 LINK_MODE=dynamic VERSION=0.1.0 \
  bash .meta/packaging/scripts/build-release.sh

TARGET_OS=linux TARGET_ARCH=amd64 LINK_MODE=dynamic VERSION=0.1.0 \
  bash .meta/packaging/scripts/package-tarball.sh
```

Generate checksums:

```sh
bash .meta/packaging/scripts/generate-checksums.sh
```

Generate Homebrew formula:

```sh
# Resolve archive URL + checksum from dist/SHA256SUMS
bash .meta/packaging/scripts/resolve-homebrew-asset.sh \
  0.1.0 \
  <owner>/<repo> \
  v0.1.0 \
  dist/SHA256SUMS

# Then generate formula (homepage is optional)
bash .meta/packaging/scripts/generate-homebrew-formula.sh \
  0.1.0 \
  https://github.com/<owner>/<repo>/releases/download/v0.1.0/wacli-0.1.0-darwin-arm64-dynamic.tar.gz \
  <sha256> \
  https://github.com/<owner>/<repo>
```
