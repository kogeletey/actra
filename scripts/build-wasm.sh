#!/usr/bin/env bash
set -euo pipefail

# Builds a WASI wasm module (no networking/db) and optimizes it with wasm-opt.
#
# Outputs (unoptimized + optimized):
#   dist/wasm/oas_validate.wasm
#   dist/wasm/oas_validate.opt.wasm
#   dist/wasm/oas_validate_db.wasm
#   dist/wasm/oas_validate_db.opt.wasm

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

mkdir -p dist/wasm

mkdir -p .crystal/cache
export CRYSTAL_CACHE_DIR="${CRYSTAL_CACHE_DIR:-$root/.crystal/cache}"

link_flags=""
if [[ -n "${WASI_SDK_PATH:-}" && -d "${WASI_SDK_PATH}/share/wasi-sysroot" ]]; then
  # Crystal doesn't always infer the WASI sysroot location; pass it explicitly.
  link_flags="--sysroot=${WASI_SDK_PATH}/share/wasi-sysroot"
fi

build_one() {
  local src="$1"
  local name="$2"

  local in="dist/wasm/${name}.wasm"
  local out="dist/wasm/${name}.opt.wasm"

  crystal build "$src" \
    --target wasm32-wasi \
    -O z \
    ${link_flags:+--link-flags "$link_flags"} \
    -o "$in"

  if command -v wasm-opt >/dev/null 2>&1; then
    wasm-opt -Oz --strip-debug --strip-producers "$in" -o "$out"
  else
    echo "wasm-opt not found; skipping optimization for ${name}" >&2
    cp -f "$in" "$out"
  fi

  echo "built: $in"
  echo "optimized: $out"
}

build_one "src/wasm/oas_validate_wasi.cr" "oas_validate"
build_one "src/wasm/oas_validate_wasi_db.cr" "oas_validate_db"
