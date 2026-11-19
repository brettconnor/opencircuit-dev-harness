#!/usr/bin/env bash
set -euo pipefail

: "${OCIRCUIT_PUBLIC_CHECKOUT:?Set OCIRCUIT_PUBLIC_CHECKOUT to the clean public checkout}"
cli="$OCIRCUIT_PUBLIC_CHECKOUT/extensions/cli/dist/oc.js"
bootstrap="$(cd "$(dirname "$0")/.." && pwd)/scripts/bootstrap.sh"

[[ -f "$cli" ]] || { printf 'Missing built CLI: %s\n' "$cli" >&2; exit 1; }

workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT

mode() {
  if stat -f '%Lp' "$1" >/dev/null 2>&1; then
    stat -f '%Lp' "$1"
  else
    stat -c '%a' "$1"
  fi
}

run_init() {
  local home="$1"
  shift
  OCIRCUIT_GLOBAL_DIR="$home" OCIRCUIT_API_BASE=http://127.0.0.1:1 \
    node "$cli" init "$@"
}

assert_contains() {
  local needle="$1"
  local file="$2"
  rg -F "$needle" "$file" >/dev/null || {
    printf 'Expected %s in %s\n' "$needle" "$file" >&2
    exit 1
  }
}

openai="$workdir/openai"
run_init "$openai" --provider openai --non-interactive --no-env >/dev/null
[[ "$(mode "$openai")" == 700 ]] || exit 1
[[ "$(mode "$openai/config.yaml")" == 600 ]] || exit 1
[[ "$(mode "$openai/.onboarding_complete")" == 600 ]] || exit 1
assert_contains 'provider: openai' "$openai/config.yaml"
before="$(shasum -a 256 "$openai/config.yaml")"
run_init "$openai" --provider anthropic --non-interactive --no-env >/dev/null
after="$(shasum -a 256 "$openai/config.yaml")"
[[ "$before" == "$after" ]] || { printf 'Rerun changed config\n' >&2; exit 1; }

preserved="$workdir/preserved"
mkdir -p "$preserved"
cat > "$preserved/config.yaml" <<'YAML'
name: Preserved
version: 1.0.0
schema: v1
models:
  - name: Preserved model
    provider: openai
    model: preserved-model
    apiKey: ${{ secrets.OPENAI_API_KEY }}
    roles:
      - chat
YAML
secret_name="OPENAI_API_KEY"
printf '%s\n' "${secret_name}=existing-value" > "$preserved/.env"
before="$(shasum -a 256 "$preserved/config.yaml" "$preserved/.env")"
run_init "$preserved" --non-interactive --no-env >/dev/null
after="$(shasum -a 256 "$preserved/config.yaml" "$preserved/.env")"
[[ "$before" == "$after" ]] || { printf 'Existing files changed\n' >&2; exit 1; }

invalid="$workdir/invalid"
mkdir -p "$invalid"
printf 'name: [invalid\n' > "$invalid/config.yaml"
before="$(shasum -a 256 "$invalid/config.yaml")"
if run_init "$invalid" --non-interactive --no-env >/dev/null 2>&1; then
  printf 'Invalid config unexpectedly succeeded\n' >&2
  exit 1
fi
after="$(shasum -a 256 "$invalid/config.yaml")"
[[ "$before" == "$after" && ! -e "$invalid/.onboarding_complete" ]] || exit 1

for provider in anthropic gemini; do
  home="$workdir/$provider"
  run_init "$home" --provider "$provider" --non-interactive --no-env >/dev/null
  assert_contains "provider: $provider" "$home/config.yaml"
done

byom="$workdir/byom"
run_init "$byom" --provider openai-compatible --model local-model \
  --api-base http://127.0.0.1:8000/v1/ --non-interactive --no-env >/dev/null
assert_contains 'provider: openai-compatible' "$byom/config.yaml"
assert_contains 'apiBase: "http://127.0.0.1:8000/v1/"' "$byom/config.yaml"
if run_init "$workdir/bad-byom" --provider openai-compatible \
  --api-base file:///tmp/model --non-interactive --no-env >/dev/null 2>&1; then
  printf 'Invalid BYOM endpoint unexpectedly succeeded\n' >&2
  exit 1
fi

fallback="$workdir/fallback"
PATH="$(dirname "$(command -v node)"):/usr/bin:/bin:/usr/sbin:/sbin" \
  OCIRCUIT_GLOBAL_DIR="$fallback" OCIRCUIT_CLI_ENTRYPOINT="$cli" \
  "$bootstrap" --provider openai --non-interactive --no-env >/dev/null
[[ -f "$fallback/config.yaml" ]] || exit 1

printf 'first-run helper regression: PASS\n'
