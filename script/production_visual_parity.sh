#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mkdir -p "$ROOT_DIR/build/production-parity-driver"
xcrun swiftc -parse-as-library \
  "$ROOT_DIR/Tests/Migration/ProductionVisualReference.swift" \
  "$ROOT_DIR/script/production_visual_parity.swift" \
  -module-cache-path "$ROOT_DIR/build/ModuleCache" \
  -o "$ROOT_DIR/build/production-parity-driver/driver"
exec "$ROOT_DIR/build/production-parity-driver/driver" "$ROOT_DIR" "$@"
