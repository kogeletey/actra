#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
cd "$root"

os="${TARGET_OS:-$(uname -s | tr '[:upper:]' '[:lower:]')}"
arch="${TARGET_ARCH:-$(uname -m)}"
link_mode="${LINK_MODE:-dynamic}"

case "$os" in
  linux|darwin) ;;
  *) echo "unsupported TARGET_OS: $os" >&2; exit 1 ;;
esac

case "$arch" in
  x86_64|amd64) arch="amd64" ;;
  aarch64|arm64) arch="arm64" ;;
  *) echo "unsupported TARGET_ARCH: $arch" >&2; exit 1 ;;
esac

version="${VERSION:-}"
if [[ -z "$version" ]]; then
  if [[ -n "${GITHUB_REF_NAME:-}" && "${GITHUB_REF_NAME}" =~ ^v ]]; then
    version="${GITHUB_REF_NAME#v}"
  elif command -v git >/dev/null 2>&1; then
    tag="$(git describe --tags --exact-match 2>/dev/null || true)"
    version="${tag#v}"
  fi
fi
if [[ -z "$version" ]]; then
  version="$(awk -F': ' '/^version:/ {print $2; exit}' shard.yml)"
fi

mkdir -p .crystal/cache bin dist
export CRYSTAL_CACHE_DIR="${CRYSTAL_CACHE_DIR:-$root/.crystal/cache}"

shards install

out="bin/wacli-${version}-${os}-${arch}-${link_mode}"
build_args=(--release -o "$out")
if [[ "$link_mode" == "static" ]]; then
  build_args+=(--static)
fi

crystal build src/wacli.cr "${build_args[@]}"
chmod +x "$out"

echo "built: $out"
