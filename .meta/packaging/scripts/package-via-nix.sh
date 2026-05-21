#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
cd "$root"

os="${TARGET_OS:-$(uname -s | tr '[:upper:]' '[:lower:]')}"
arch="${TARGET_ARCH:-$(uname -m)}"
link_mode="${LINK_MODE:-dynamic}"
version="${VERSION:-}"

case "$os" in
  linux|darwin) ;;
  *) echo "unsupported TARGET_OS: $os" >&2; exit 1 ;;
esac

case "$arch" in
  x86_64|amd64) arch="amd64" ;;
  aarch64|arm64) arch="arm64" ;;
  *) echo "unsupported TARGET_ARCH: $arch" >&2; exit 1 ;;
esac

if [[ -z "$version" ]]; then
  if [[ -n "${GITHUB_REF_NAME:-}" && "${GITHUB_REF_NAME}" =~ ^v ]]; then
    version="${GITHUB_REF_NAME#v}"
  else
    version="$(awk -F': ' '/^version:/ {print $2; exit}' shard.yml)"
  fi
fi

if [[ "$link_mode" != "dynamic" ]]; then
  echo "nix flake packaging currently supports only dynamic builds" >&2
  exit 1
fi

nix_flags=(--extra-experimental-features nix-command --extra-experimental-features flakes)
nix_out="$(nix "${nix_flags[@]}" build .#actra --print-out-paths --no-link)"
binary="$nix_out/bin/actra"
if [[ ! -x "$binary" ]]; then
  echo "built binary missing: $binary" >&2
  exit 1
fi

out_bin="bin/actra-${version}-${os}-${arch}-${link_mode}"
mkdir -p bin dist
cp "$binary" "$out_bin"
chmod +x "$out_bin"

export VERSION="$version"
export TARGET_OS="$os"
export TARGET_ARCH="$arch"
export LINK_MODE="$link_mode"
bash .meta/packaging/scripts/package-tarball.sh

archive="dist/actra-${version}-${os}-${arch}-${link_mode}.tar.gz"
echo "packaged via nix: $archive"
