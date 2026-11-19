#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
bash -n "$root/scripts/bootstrap.sh" "$root/tests/first-run.test.sh"
review_files=("$root/scripts/bootstrap.sh" "$root/tests/first-run.test.sh")
if rg -n '\beval\b|curl[^\n]*\|[^\n]*(sh|bash)|wget[^\n]*\|[^\n]*(sh|bash)' "${review_files[@]}"; then
  printf 'Code-guard policy violation found in harness scripts\n' >&2
  exit 1
fi
if rg -n 'OPENAI_API_KEY=|ANTHROPIC_API_KEY=|GEMINI_API_KEY=|BYOM_API_KEY=' "${review_files[@]}"; then
  printf 'Credential material must not be embedded in harness scripts\n' >&2
  exit 1
fi
printf 'harness script/code policy: PASS\n'
