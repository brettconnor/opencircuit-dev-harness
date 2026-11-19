#!/usr/bin/env bash
set -euo pipefail

# Fallback only: all initialization behavior lives in `oc init`.
if command -v oc >/dev/null 2>&1; then
  exec oc init "$@"
fi

node_bin="${NODE_BIN:-node}"
if ! command -v "$node_bin" >/dev/null 2>&1; then
  printf 'Open Circuit bootstrap requires Node.js on PATH.\n' >&2
  exit 127
fi

entrypoint="${OCIRCUIT_CLI_ENTRYPOINT:-}"
if [[ -z "$entrypoint" ]]; then
  for candidate in "$PWD/extensions/cli/dist/oc.js" "$PWD/dist/oc.js"; do
    if [[ -f "$candidate" ]]; then
      entrypoint="$candidate"
      break
    fi
  done
fi

if [[ -z "$entrypoint" || ! -f "$entrypoint" ]]; then
  printf 'Open Circuit CLI was not found. Install `oc` or set OCIRCUIT_CLI_ENTRYPOINT to dist/oc.js.\n' >&2
  exit 127
fi

exec "$node_bin" "$entrypoint" init "$@"
