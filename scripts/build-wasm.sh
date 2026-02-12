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

# Crystal resolves `-lc` through CRYSTAL_LIBRARY_PATH. For WASI builds, point it
# at the wasi-sdk libc directory instead of passing --sysroot to wasm-ld.
if [[ -n "${WASI_SDK_PATH:-}" ]]; then
  wasi_lib_dir="${WASI_SDK_PATH}/share/wasi-sysroot/lib/wasm32-wasi"
  if [[ -d "$wasi_lib_dir" ]]; then
    export CRYSTAL_LIBRARY_PATH="${wasi_lib_dir}${CRYSTAL_LIBRARY_PATH:+:${CRYSTAL_LIBRARY_PATH}}"
  fi
fi

build_one() {
  local src="$1"
  local name="$2"

  local in="dist/wasm/${name}.wasm"
  local out="dist/wasm/${name}.opt.wasm"

  crystal build "$src" \
    --target wasm32-wasi \
    -O z \
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
