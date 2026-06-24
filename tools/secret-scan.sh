#!/usr/bin/env bash
# Minimal secret scanner. Fails (exit 1) if likely secrets are found in tracked files.
# Run before pushing; also suitable for a pre-commit hook or CI gate.
set -euo pipefail

cd "$(dirname "$0")/.."

# Patterns: Anthropic keys, generic API tokens, Apple p12/mobileprovision contents.
PATTERNS=(
  'sk-ant-[A-Za-z0-9_-]{20,}'
  'AKIA[0-9A-Z]{16}'
  '-----BEGIN [A-Z ]*PRIVATE KEY-----'
)

# Only scan tracked, text files (skip docs that legitimately mention "sk-ant-…" as a placeholder).
FILES=$(git ls-files | grep -Ev '\.(png|jpg|jpeg|gif|pdf|ipa|app|dSYM)$' || true)

found=0
for pat in "${PATTERNS[@]}"; do
  # Exclude the literal placeholder examples used in UI/docs.
  if matches=$(printf '%s\n' "$FILES" | xargs -r grep -nE "$pat" 2>/dev/null \
      | grep -v 'sk-ant-…' | grep -v 'sk-ant-test' | grep -v 'sk-ant-x'); then
    if [ -n "$matches" ]; then
      echo "Potential secret ($pat):"
      echo "$matches"
      found=1
    fi
  fi
done

if [ "$found" -ne 0 ]; then
  echo "ERROR: potential secrets found. Remove them before committing." >&2
  exit 1
fi
echo "secret-scan: clean"
