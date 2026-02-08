#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

os="$(uname -s | tr '[:upper:]' '[:lower:]')"
arch="$(uname -m)"

case "$arch" in
  x86_64|amd64) arch="amd64" ;;
  aarch64|arm64) arch="arm64" ;;
esac

version="0.1.0"
if command -v git >/dev/null 2>&1; then
  tag="$(git describe --tags --exact-match 2>/dev/null || true)"
  if [[ -n "$tag" ]]; then
    version="${tag#v}"
  fi
fi

dist="dist"
name="wacli-${version}-${os}-${arch}"
tmp="${dist}/${name}"

rm -rf "$tmp"
mkdir -p "$tmp"

if [[ ! -f "bin/wacli" ]]; then
  echo "missing bin/wacli (run: shards build --release)" >&2
  exit 1
fi

cp -a "bin/wacli" "$tmp/"
cp -a "LICENSE" "$tmp/"
cp -a "README.md" "$tmp/"

mkdir -p "$dist"
tar -C "$dist" -czf "${dist}/${name}.tar.gz" "$name"

if command -v sha256sum >/dev/null 2>&1; then
  sha256sum "${dist}/${name}.tar.gz" > "${dist}/${name}.tar.gz.sha256"
elif command -v shasum >/dev/null 2>&1; then
  shasum -a 256 "${dist}/${name}.tar.gz" > "${dist}/${name}.tar.gz.sha256"
else
  echo "no sha256 tool found; skipping checksum" >&2
fi

echo "built ${dist}/${name}.tar.gz"

