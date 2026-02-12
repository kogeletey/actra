#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
cd "$root"

mkdir -p dist
output="dist/SHA256SUMS"
: > "$output"

shopt -s nullglob
archives=(dist/*.tar.gz)
if [[ ${#archives[@]} -eq 0 ]]; then
  echo "no dist/*.tar.gz archives found" >&2
  exit 1
fi

for file in "${archives[@]}"; do
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$file" >> "$output"
  else
    shasum -a 256 "$file" >> "$output"
  fi
done

echo "wrote: $output"
