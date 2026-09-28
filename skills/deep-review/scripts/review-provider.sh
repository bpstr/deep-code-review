#!/usr/bin/env bash
# Shared provider identity resolution. Bash 3.2; no provider processes are started.
# Installation, credentials, model names and skill paths do NOT identify the caller.
deep_review_provider_name() {
  case "$1" in
    codex|claude|copilot|grok|gemini) printf '%s\n' "$1" ;;
    *) echo "Unsupported provider '$1'. Use codex, claude, copilot, grok, or gemini; no fallback is permitted." >&2; return 2 ;;
  esac
}

deep_review_resolve_provider() {
  local requested="${1:-auto}" caller="${DEEP_REVIEW_CALLER:-}"
  # --provider overrides DEEP_REVIEW_PROVIDER in both entry points. A concrete
  # choice is intentional, even when different from the caller's native client.
  if [ "$requested" != auto ]; then
    deep_review_provider_name "$requested"
    return $?
  fi
  # The skill supplies this on EVERY invocation. It beats inherited outer-session
  # markers when one coding CLI has launched another one.
  if [ -n "$caller" ]; then
    deep_review_provider_name "$caller"
    return $?
  fi
  # Conservative compatibility for known native session markers. Never infer an
  # active client from an API key, config directory, or command availability.
  if [ -n "${CLAUDECODE:-}" ] && [ -n "${CODEX_THREAD_ID:-}" ]; then
    echo 'Conflicting caller identities. Set DEEP_REVIEW_CALLER to the invoking CLI or select --provider explicitly.' >&2
    return 2
  fi
  if [ -n "${CLAUDECODE:-}" ]; then printf 'claude\n'; return 0; fi
  if [ -n "${CODEX_THREAD_ID:-}" ]; then printf 'codex\n'; return 0; fi
  echo 'Cannot identify the invoking CLI. Set DEEP_REVIEW_CALLER or --provider (codex|claude|copilot|grok|gemini). Installed CLIs are not a fallback.' >&2
  return 2
}
