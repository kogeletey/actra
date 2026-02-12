#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
cd "$root"

resolver=".meta/packaging/scripts/resolve-homebrew-asset.sh"
generator=".meta/packaging/scripts/generate-homebrew-formula.sh"
fixtures=".meta/packaging/test-fixtures"

tmp="$(mktemp -d)"
formula_out=".meta/packaging/homebrew/wacli.rb"
formula_backup="$tmp/wacli.rb.backup"
formula_preexisting=0

cleanup() {
  if [[ "$formula_preexisting" -eq 1 ]]; then
    mv "$formula_backup" "$formula_out"
  else
    rm -f "$formula_out"
  fi
  rm -rf "$tmp"
}
trap cleanup EXIT

if [[ -f "$formula_out" ]]; then
  cp "$formula_out" "$formula_backup"
  formula_preexisting=1
fi

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

assert_eq() {
  local actual="$1"
  local expected="$2"
  local msg="$3"
  if [[ "$actual" != "$expected" ]]; then
    fail "$msg (expected '$expected', got '$actual')"
  fi
}

kv_value() {
  local key="$1"
  local input="$2"
  awk -F'=' -v k="$key" '$1 == k {print substr($0, index($0, "=") + 1); exit}' <<<"$input"
}

exact_out="$(bash "$resolver" "1.2.3" "kogeletey/wacli" "v1.2.3" "$fixtures/homebrew-sha256sums-exact.txt")"
assert_eq \
  "$(kv_value BREW_ASSET "$exact_out")" \
  "wacli-1.2.3-darwin-arm64-dynamic.tar.gz" \
  "exact resolver picked wrong asset"
assert_eq \
  "$(kv_value BREW_SHA "$exact_out")" \
  "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" \
  "exact resolver picked wrong sha"
assert_eq \
  "$(kv_value BREW_URL "$exact_out")" \
  "https://github.com/kogeletey/wacli/releases/download/v1.2.3/wacli-1.2.3-darwin-arm64-dynamic.tar.gz" \
  "exact resolver produced wrong URL"

fallback_stderr="$tmp/fallback.stderr"
fallback_out="$(bash "$resolver" "1.2.3" "kogeletey/wacli" "v1.2.3" "$fixtures/homebrew-sha256sums-fallback.txt" 2>"$fallback_stderr")"
assert_eq \
  "$(kv_value BREW_ASSET "$fallback_out")" \
  "wacli-1.2.3-darwin-amd64-dynamic.tar.gz" \
  "fallback resolver picked wrong asset"
assert_eq \
  "$(kv_value BREW_SHA "$fallback_out")" \
  "cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc" \
  "fallback resolver picked wrong sha"
grep -q "falling back" "$fallback_stderr" || fail "fallback resolver did not emit warning"

set +e
bash "$resolver" "1.2.3" "kogeletey/wacli" "v1.2.3" "$fixtures/homebrew-sha256sums-no-darwin.txt" >"$tmp/no-darwin.out" 2>"$tmp/no-darwin.err"
no_darwin_status=$?
set -e
assert_eq "$no_darwin_status" "1" "no-darwin resolver should fail with status 1"
grep -q "no darwin release archive found" "$tmp/no-darwin.err" || fail "no-darwin resolver error message missing"

set +e
bash "$resolver" "1.2.3" "kogeletey/wacli" "v1.2.3" "$tmp/missing-sha.txt" >"$tmp/missing.out" 2>"$tmp/missing.err"
missing_status=$?
set -e
assert_eq "$missing_status" "2" "missing checksum file should fail with status 2"
grep -q "checksum file not found" "$tmp/missing.err" || fail "missing checksum resolver error message missing"

bash "$generator" \
  "1.2.3" \
  "https://github.com/kogeletey/wacli/releases/download/v1.2.3/wacli-1.2.3-darwin-amd64-dynamic.tar.gz" \
  "cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc" \
  "https://github.com/kogeletey/wacli"

grep -q 'homepage "https://github.com/kogeletey/wacli"' "$formula_out" || fail "formula homepage was not templated"
grep -q 'version "1.2.3"' "$formula_out" || fail "formula version was not templated"
grep -q 'sha256 "cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"' "$formula_out" || fail "formula sha256 was not templated"

echo "homebrew packaging tests passed"
