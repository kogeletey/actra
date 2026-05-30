#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
cd "$root"

version="${VERSION:-}"
os="${TARGET_OS:-}"
arch="${TARGET_ARCH:-}"
link_mode="${LINK_MODE:-dynamic}"

if [[ -z "$version" ]]; then
  if [[ -n "${GITHUB_REF_NAME:-}" && "${GITHUB_REF_NAME}" =~ ^v ]]; then
    version="${GITHUB_REF_NAME#v}"
  else
    version="$(awk -F': ' '/^version:/ {print $2; exit}' shard.yml)"
  fi
fi

if [[ -z "$os" ]]; then
  os="$(uname -s | tr '[:upper:]' '[:lower:]')"
fi
if [[ -z "$arch" ]]; then
  arch="$(uname -m)"
fi

case "$arch" in
  x86_64|amd64) arch="amd64" ;;
  aarch64|arm64) arch="arm64" ;;
esac

bin_path="bin/actra-${version}-${os}-${arch}-${link_mode}"
[[ -x "$bin_path" ]] || { echo "missing binary: $bin_path" >&2; exit 1; }

name="actra-${version}-${os}-${arch}-${link_mode}"
tmp_dir="dist/$name"
archive="dist/${name}.tar.gz"

rm -rf "$tmp_dir"
mkdir -p "$tmp_dir"
cp "$bin_path" "$tmp_dir/actra"
cp LICENSE README.md "$tmp_dir/"

tar -C dist -czf "$archive" "$name"
echo "packaged: $archive"
