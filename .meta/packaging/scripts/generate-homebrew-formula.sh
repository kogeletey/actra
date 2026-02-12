#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
cd "$root"

version="${1:-${VERSION:-}}"
url="${2:-${HOMEBREW_URL:-}}"
sha="${3:-${HOMEBREW_SHA256:-}}"
homepage="${4:-${HOMEBREW_HOMEPAGE:-https://github.com/wacli/wacli}}"

if [[ -z "$version" || -z "$url" || -z "$sha" ]]; then
  echo "usage: generate-homebrew-formula.sh <version> <url> <sha256> [homepage]" >&2
  exit 1
fi

tmpl=".meta/packaging/homebrew/wacli.rb.tmpl"
out=".meta/packaging/homebrew/wacli.rb"

sed \
  -e "s|@VERSION@|$version|g" \
  -e "s|@HOMEPAGE@|$homepage|g" \
  -e "s|@URL@|$url|g" \
  -e "s|@SHA256@|$sha|g" \
  "$tmpl" > "$out"

echo "generated: $out"
