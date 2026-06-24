#!/usr/bin/env bash
# Regenerate AnkiAI.xcodeproj from project.yml. Run on macOS.
set -euo pipefail
cd "$(dirname "$0")/.."
if ! command -v xcodegen >/dev/null 2>&1; then
  echo "Installing XcodeGen…"
  brew install xcodegen
fi
xcodegen generate
echo "Generated AnkiAI.xcodeproj"
