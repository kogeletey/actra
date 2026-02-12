#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
cd "$root"

version="${1:-${VERSION:-}}"
repo="${2:-${REPO:-}}"
tag="${3:-${TAG:-}}"
sha_file="${4:-${SHA_FILE:-dist/SHA256SUMS}}"

if [[ -z "$version" || -z "$repo" || -z "$tag" ]]; then
  echo "usage: resolve-homebrew-asset.sh <version> <repo> <tag> [sha_file]" >&2
  exit 1
fi

if [[ ! -f "$sha_file" ]]; then
  echo "checksum file not found: $sha_file" >&2
  exit 2
fi

declare -A sha_by_asset=()
candidates=()

while IFS= read -r line; do
  [[ -n "$line" ]] || continue

  sha="$(awk '{print $1}' <<<"$line")"
  path="$(awk '{print $2}' <<<"$line")"
  [[ -n "$sha" && -n "$path" ]] || continue

  path="${path#\*}"
  asset="${path##*/}"

  case "$asset" in
    "wacli-${version}-darwin-"*.tar.gz)
      sha_by_asset["$asset"]="$sha"
      candidates+=("$asset")
      ;;
  esac
done < "$sha_file"

if [[ ${#candidates[@]} -eq 0 ]]; then
  echo "no darwin release archive found in $sha_file for version $version" >&2
  echo "available entries:" >&2
  sed 's/^/  /' "$sha_file" >&2
  exit 1
fi

expected="wacli-${version}-darwin-arm64-dynamic.tar.gz"
selected=""

if [[ -n "${sha_by_asset[$expected]:-}" ]]; then
  selected="$expected"
else
  selected="$(printf '%s\n' "${candidates[@]}" | sort | head -n1)"
  {
    echo "warning: expected archive not found: $expected"
    echo "warning: falling back to: $selected"
    echo "warning: candidates were:"
    printf '  %s\n' "${candidates[@]}" | sort
  } >&2
fi

sha="${sha_by_asset[$selected]:-}"
if [[ -z "$sha" ]]; then
  echo "missing checksum for selected archive: $selected" >&2
  exit 2
fi

url="https://github.com/${repo}/releases/download/${tag}/${selected}"

echo "BREW_ASSET=$selected"
echo "BREW_SHA=$sha"
echo "BREW_URL=$url"
