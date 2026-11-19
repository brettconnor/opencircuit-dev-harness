# SDD: Idempotent Open Circuit First Run

Status: Finalized

## Decision

The supported first-run entry point is `oc init`. The non-production fallback
wrapper is `scripts/bootstrap.sh` in this harness. The wrapper locates an
installed `oc` first and otherwise invokes a caller-supplied or checkout-local
CLI entry point; it contains no duplicate provider or file-generation logic.

## Goals and boundaries

- Keep initialization local-only. `oc init` validates YAML and model presence
  without contacting a provider or the hosted Open Circuit API.
- Make initialization safe to rerun. Existing config and environment files are
  preserved; existing onboarding state is preserved.
- Keep secrets out of YAML, command-line arguments, logs, and test output.
- Support OpenAI, Anthropic, Gemini, and `openai-compatible` BYOM endpoints.
- Keep all non-production scripts and integration tests in
  `opencircuit-dev-harness`, never in `opencircuit-dev-personal`.

## Behavior

1. `oc init` supports Node.js 24.x from `24.19.0` onward and warns outside
   that line. The current verified LTS patch is `24.21.0`.
2. It creates or secures `~/.ocircuit` as mode `700`.
3. If `config.yaml` exists, it validates it locally, preserves it, and creates
   `.onboarding_complete` unless `--check` was supplied. Invalid files fail
   closed with an actionable error and are never overwritten.
4. Otherwise it selects one provider, copies the matching packaged template,
   safely applies the model and (for BYOM) an absolute `http`/`https` API base,
   and creates the config with exclusive mode `600` creation.
5. `.env` creation is opt-in. Interactive secret entry is hidden, atomic, and
   mode `600`; an existing `.env` is preserved. Non-interactive mode never
   prompts.
6. Successful initialization validates the generated config, creates the
   marker atomically, and prints the explicit live smoke-test command. It does
   not execute that command.

## CLI surface

```text
oc init [--provider <provider>] [--model <model>] [--api-base <url>]
        [--create-env|--no-env] [--check] [--non-interactive]
```

`--check` is read-only validation of an existing config. Provider names are
exactly `openai`, `anthropic`, `gemini`, and `openai-compatible`. BYOM rejects
non-HTTP(S) URLs and URLs containing embedded credentials.

## Startup integration

Normal startup accepts a valid existing default config before onboarding and
creates `.onboarding_complete`. An invalid existing default config is reported
as invalid and preserved; startup does not silently replace it or prompt for a
different provider. Explicit `--config` errors retain their existing
fail-loudly behavior.

## TDD and gates

The harness regression test covers reruns, byte-for-byte preservation, invalid
configs, directory/file permissions, all provider selections, BYOM URL
validation, environment-file preservation, and the bootstrap fallback. The
production CLI gates are typecheck, build, unit tests, and smoke tests. The
policy gates are install-script policy, dependency policy, shell syntax, and
the code-guard checks for unbounded writes, shell evaluation, secret output,
and unsafe destructive commands.

## Rollback and recovery

The command never overwrites an existing config or `.env`. If initialization
fails after a newly-created config, the user can remove only that newly-created
file and rerun; no existing user file is targeted. A provider key is recovered
by changing the environment source, not by editing the YAML secret reference.
