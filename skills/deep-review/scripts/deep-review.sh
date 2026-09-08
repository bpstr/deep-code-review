#!/usr/bin/env bash
set -euo pipefail

# Durable orchestration wrapper for Deep Code Review.
# Keep compatible with Bash 3.2 (default Bash on macOS).

RUNNER_VERSION="1.1.0"
RUNNER_SCHEMA="2"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ENGINE="$SCRIPT_DIR/deep-review-engine.sh"

usage_extra() {
  cat <<'USAGE'

Durability and resource controls added by the resilient runner:
  --no-resume                 Never resume a matching interrupted run
  --artifacts-dir DIR         Persistent state/artifact root (default: XDG state dir)
  --list-runs                 List saved runs for this repository and exit
  --latest-artifacts          Print the latest saved run directory and exit
  --version                   Print Deep Code Review version and exit

Environment:
  DEEP_REVIEW_STATE_DIR               Override persistent state root.
  DEEP_REVIEW_MEMORY_RESERVE_MB       Memory kept outside review workers (default: 2048).
  DEEP_REVIEW_MEMORY_PER_WORKER_MB    Budget per concurrent provider process (default: 1024).
  DEEP_REVIEW_KEEP_COMPLETED_RUNS     Completed runs retained per repository (default: 20; 0 = unlimited).
  DEEP_REVIEW_ALLOW_MEMORY_OVERSUBSCRIBE=1 keeps an explicitly requested concurrency above the safe estimate.

Completed reviewer/stage outputs are checkpointed. After a crash, shutdown, OOM kill,
or terminal interruption, the next matching invocation resumes from the most recent
stale run and re-executes only work that did not finish cleanly. Completed runs and
reports are stored persistently and can be inspected with --list-runs.
USAGE
}

[ -s "$ENGINE" ] || { echo "Deep Code Review engine not found: $ENGINE" >&2; exit 1; }

RESUME=1
LIST_RUNS=0
LATEST_ONLY=0
ARTIFACT_BASE="${DEEP_REVIEW_STATE_DIR:-${XDG_STATE_HOME:-${HOME:-/tmp}/.local/state}/deep-code-review}"
EXPLICIT_MAX=""
ENGINE_ARGS=()
FINGERPRINT_ARGS=()

while [ "$#" -gt 0 ]; do
  case "$1" in
    --version)
      printf 'Deep Code Review %s\n' "$RUNNER_VERSION"
      exit 0
      ;;
    --no-resume)
      RESUME=0
      shift
      ;;
    --artifacts-dir)
      [ "$#" -ge 2 ] || { echo "--artifacts-dir requires a directory." >&2; exit 2; }
      ARTIFACT_BASE="$2"
      shift 2
      ;;
    --list-runs)
      LIST_RUNS=1
      shift
      ;;
    --latest-artifacts)
      LATEST_ONLY=1
      shift
      ;;
    --max-concurrent)
      [ "$#" -ge 2 ] || { echo "--max-concurrent requires a value." >&2; exit 2; }
      EXPLICIT_MAX="$2"
      # Resource tuning is intentionally excluded from the recovery fingerprint.
      shift 2
      ;;
    --keep-results)
      # Persistent artifacts are always retained by this wrapper.
      shift
      ;;
    -h|--help)
      bash "$ENGINE" --help
      usage_extra
      exit 0
      ;;
    *)
      ENGINE_ARGS+=("$1")
      FINGERPRINT_ARGS+=("$1")
      shift
      ;;
  esac
done

ROOT_DIR="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
ROOT_DIR="$(cd "$ROOT_DIR" && pwd)"
REPO_KEY="$(printf '%s\n' "$ROOT_DIR" | cksum | awk '{print $1 "-" $2}')"
REPO_STATE="$ARTIFACT_BASE/repos/$REPO_KEY"
RUNS_DIR="$REPO_STATE/runs"
mkdir -p "$RUNS_DIR"

if [ "$LIST_RUNS" -eq 1 ]; then
  found=0
  for run in "$RUNS_DIR"/run-*; do
    [ -d "$run" ] || continue
    found=1
    status="unknown"
    [ ! -s "$run/status" ] || status="$(cat "$run/status")"
    printf '%s\t%s\n' "$status" "$run"
  done
  [ "$found" -eq 1 ] || echo "No saved Deep Code Review runs for $ROOT_DIR"
  exit 0
fi

if [ "$LATEST_ONLY" -eq 1 ]; then
  if [ -s "$REPO_STATE/latest" ]; then
    cat "$REPO_STATE/latest"
    exit 0
  fi
  echo "No saved Deep Code Review run for $ROOT_DIR" >&2
  exit 1
fi

available_memory_mb() {
  if [ -r /proc/meminfo ]; then
    awk '/^MemAvailable:/ { print int($2 / 1024); found=1; exit } END { if (!found) exit 1 }' /proc/meminfo 2>/dev/null && return 0
  fi

  if command -v vm_stat >/dev/null 2>&1 && command -v sysctl >/dev/null 2>&1; then
    page_size="$(sysctl -n hw.pagesize 2>/dev/null || echo 4096)"
    vm_stat 2>/dev/null | awk -v page_size="$page_size" '
      /Pages free:/ { gsub("\\.", "", $3); free=$3 }
      /Pages inactive:/ { gsub("\\.", "", $3); inactive=$3 }
      /Pages speculative:/ { gsub("\\.", "", $3); speculative=$3 }
      /Pages purgeable:/ { gsub("\\.", "", $3); purgeable=$3 }
      END {
        pages=free+inactive+speculative+purgeable
        if (pages > 0) print int((pages * page_size) / 1048576)
        else exit 1
      }' && return 0
  fi

  return 1
}

case "${DEEP_REVIEW_MEMORY_RESERVE_MB:-2048}" in *[!0-9]*|'') echo "DEEP_REVIEW_MEMORY_RESERVE_MB must be an integer." >&2; exit 2;; esac
case "${DEEP_REVIEW_MEMORY_PER_WORKER_MB:-1024}" in *[!0-9]*|'') echo "DEEP_REVIEW_MEMORY_PER_WORKER_MB must be an integer." >&2; exit 2;; esac
MEMORY_RESERVE_MB="${DEEP_REVIEW_MEMORY_RESERVE_MB:-2048}"
MEMORY_PER_WORKER_MB="${DEEP_REVIEW_MEMORY_PER_WORKER_MB:-1024}"
[ "$MEMORY_PER_WORKER_MB" -gt 0 ] || { echo "DEEP_REVIEW_MEMORY_PER_WORKER_MB must be positive." >&2; exit 2; }

REQUESTED_MAX="${EXPLICIT_MAX:-${MAX_CONCURRENT:-12}}"
case "$REQUESTED_MAX" in *[!0-9]*|'') echo "MAX_CONCURRENT must be a positive integer." >&2; exit 2;; esac
[ "$REQUESTED_MAX" -gt 0 ] || { echo "MAX_CONCURRENT must be positive." >&2; exit 2; }
SAFE_MAX="$REQUESTED_MAX"
AVAILABLE_MB=""
if AVAILABLE_MB="$(available_memory_mb 2>/dev/null)"; then
  usable=$((AVAILABLE_MB - MEMORY_RESERVE_MB))
  if [ "$usable" -lt "$MEMORY_PER_WORKER_MB" ]; then
    memory_max=1
  else
    memory_max=$((usable / MEMORY_PER_WORKER_MB))
    [ "$memory_max" -gt 0 ] || memory_max=1
  fi
  [ "$memory_max" -lt "$SAFE_MAX" ] && SAFE_MAX="$memory_max"
fi

# Large repositories amplify per-agent indexing/context memory. Cap concurrency further
# without changing the semantic run fingerprint, so interrupted work can resume after
# lowering resource pressure.
if git -C "$ROOT_DIR" rev-parse --git-dir >/dev/null 2>&1; then
  TRACKED_FILES="$(git -C "$ROOT_DIR" ls-files 2>/dev/null | wc -l | tr -d ' ')"
else
  TRACKED_FILES=0
fi
case "$TRACKED_FILES" in *[!0-9]*|'') TRACKED_FILES=0;; esac
if [ "$TRACKED_FILES" -ge 100000 ] && [ "$SAFE_MAX" -gt 2 ]; then SAFE_MAX=2
elif [ "$TRACKED_FILES" -ge 20000 ] && [ "$SAFE_MAX" -gt 4 ]; then SAFE_MAX=4
fi

if [ -n "$EXPLICIT_MAX" ] && [ "$EXPLICIT_MAX" -gt "$SAFE_MAX" ] && [ "${DEEP_REVIEW_ALLOW_MEMORY_OVERSUBSCRIBE:-0}" = 1 ]; then
  SAFE_MAX="$EXPLICIT_MAX"
elif [ "$REQUESTED_MAX" -gt "$SAFE_MAX" ]; then
  printf 'Memory guard: limiting concurrency from %s to %s' "$REQUESTED_MAX" "$SAFE_MAX" >&2
  [ -z "$AVAILABLE_MB" ] || printf ' (available=%sMB, reserve=%sMB, worker-budget=%sMB)' "$AVAILABLE_MB" "$MEMORY_RESERVE_MB" "$MEMORY_PER_WORKER_MB" >&2
  [ "$TRACKED_FILES" -eq 0 ] || printf ' (tracked-files=%s)' "$TRACKED_FILES" >&2
  printf '.\n' >&2
fi

# Compute a semantic fingerprint. Concurrency/artifact location are deliberately absent;
# provider/model and repository input are present so completed work is never reused across
# meaningfully different reviews.
fingerprint_stream() {
  printf 'schema=%s\nroot=%s\nhead=%s\nprovider=%s\nmodel=%s\nfast_model=%s\n' \
    "$RUNNER_SCHEMA" "$ROOT_DIR" "$(git -C "$ROOT_DIR" rev-parse HEAD 2>/dev/null || echo no-head)" \
    "${DEEP_REVIEW_PROVIDER:-auto}" "${REVIEW_MODEL:-}" "${DEEP_REVIEW_FAST_MODEL:-}"
  for arg in "${FINGERPRINT_ARGS[@]}"; do printf 'arg=%s\n' "$arg"; done
  git -C "$ROOT_DIR" status --porcelain=v1 2>/dev/null || true
  git -C "$ROOT_DIR" diff --no-ext-diff HEAD 2>/dev/null || true
  git -C "$ROOT_DIR" diff --no-ext-diff --cached 2>/dev/null || true
}
FINGERPRINT="$(fingerprint_stream | cksum | awk '{print $1 "-" $2}')"

boot_identity() {
  if [ -r /proc/sys/kernel/random/boot_id ]; then cat /proc/sys/kernel/random/boot_id; return; fi
  if command -v sysctl >/dev/null 2>&1; then sysctl -n kern.boottime 2>/dev/null || true; return; fi
  echo unknown
}
BOOT_ID="$(boot_identity | cksum | awk '{print $1 "-" $2}')"

lock_is_live() {
  run="$1"
  [ -d "$run/.lock" ] || return 1
  [ -s "$run/.lock/pid" ] || return 1
  [ -s "$run/.lock/boot" ] || return 1
  lock_pid="$(cat "$run/.lock/pid" 2>/dev/null || true)"
  lock_boot="$(cat "$run/.lock/boot" 2>/dev/null || true)"
  [ "$lock_boot" = "$BOOT_ID" ] || return 1
  case "$lock_pid" in *[!0-9]*|'') return 1;; esac
  kill -0 "$lock_pid" 2>/dev/null
}

claim_run() {
  run="$1"
  if [ -d "$run/.lock" ]; then
    if lock_is_live "$run"; then return 1; fi
    rm -rf "$run/.lock"
  fi
  mkdir "$run/.lock" 2>/dev/null || return 1
  printf '%s\n' "$$" >"$run/.lock/pid"
  printf '%s\n' "$BOOT_ID" >"$run/.lock/boot"
  return 0
}

RUN_DIR=""
if [ "$RESUME" -eq 1 ]; then
  # Sort newest first. Run names contain no whitespace even if the state root does.
  candidates="$(find "$RUNS_DIR" -type d -name "run-$FINGERPRINT-*" -prune -print 2>/dev/null | sort -r || true)"
  old_ifs="$IFS"
  IFS='
'
  for run in $candidates; do
    [ -d "$run" ] || continue
    status="$(cat "$run/status" 2>/dev/null || echo running)"
    [ "$status" != completed ] || continue
    if claim_run "$run"; then
      RUN_DIR="$run"
      break
    fi
  done
  IFS="$old_ifs"
fi

if [ -z "$RUN_DIR" ]; then
  timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
  RUN_DIR="$RUNS_DIR/run-$FINGERPRINT-$timestamp-$$"
  mkdir -p "$RUN_DIR"
  claim_run "$RUN_DIR" || { echo "Could not claim review run: $RUN_DIR" >&2; exit 1; }
  printf '%s\n' "$FINGERPRINT" >"$RUN_DIR/fingerprint"
  printf '%s\n' "$ROOT_DIR" >"$RUN_DIR/repository"
  printf '%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >"$RUN_DIR/started-at"
  {
    printf 'version=%s\n' "$RUNNER_VERSION"
    for arg in "${FINGERPRINT_ARGS[@]}"; do printf 'arg=%s\n' "$arg"; done
  } >"$RUN_DIR/request.txt"
  echo "Starting durable review run: $RUN_DIR" >&2
else
  echo "Resuming interrupted review run: $RUN_DIR" >&2
fi
printf '%s\n' running >"$RUN_DIR/status"
cat >"$RUN_DIR/resource-plan.txt" <<EOF_RESOURCE
requested_concurrency=$REQUESTED_MAX
safe_concurrency=$SAFE_MAX
available_memory_mb=${AVAILABLE_MB:-unknown}
memory_reserve_mb=$MEMORY_RESERVE_MB
memory_per_worker_mb=$MEMORY_PER_WORKER_MB
tracked_files=$TRACKED_FILES
EOF_RESOURCE

# Ensure discovery is useful even while a run is active.
printf '%s\n' "$RUN_DIR" >"$REPO_STATE/latest.tmp.$$"
mv "$REPO_STATE/latest.tmp.$$" "$REPO_STATE/latest"

REAL_MKTEMP="$(command -v mktemp)"
REAL_CODEX="$(command -v codex 2>/dev/null || true)"
REAL_CLAUDE="$(command -v claude 2>/dev/null || true)"
SHIM_DIR="$RUN_DIR/.shims"
mkdir -p "$SHIM_DIR"

cat >"$SHIM_DIR/mktemp" <<'EOF_MKTEMP'
#!/usr/bin/env bash
set -e
for arg in "$@"; do
  case "$arg" in
    *deep-review.XXXXXX*)
      mkdir -p "$DEEP_REVIEW_ACTIVE_RUN_DIR"
      printf '%s\n' "$DEEP_REVIEW_ACTIVE_RUN_DIR"
      exit 0
      ;;
  esac
done
exec "$DEEP_REVIEW_REAL_MKTEMP" "$@"
EOF_MKTEMP
chmod +x "$SHIM_DIR/mktemp"

cat >"$SHIM_DIR/provider-shim" <<'EOF_PROVIDER'
#!/usr/bin/env bash
set -u
provider="$(basename "$0")"
case "$provider" in
  codex) real="${DEEP_REVIEW_REAL_CODEX:-}" ;;
  claude) real="${DEEP_REVIEW_REAL_CLAUDE:-}" ;;
  *) echo "Unknown provider shim: $provider" >&2; exit 127 ;;
esac
[ -n "$real" ] || { echo "Provider '$provider' is unavailable." >&2; exit 127; }

prompt=""
if [ "$provider" = codex ]; then
  for arg in "$@"; do prompt="$arg"; done
else
  want_prompt=0
  for arg in "$@"; do
    if [ "$want_prompt" -eq 1 ]; then prompt="$arg"; break; fi
    [ "$arg" != -p ] || want_prompt=1
  done
fi

run_dir="${DEEP_REVIEW_ACTIVE_RUN_DIR:?}"
target=""
case "$prompt" in
  *"specialized READ-ONLY code analysis agent"*)
    target="$(printf '%s\n' "$prompt" | sed -n 's/^Write your complete Markdown findings to: //p' | head -1)"
    ;;
  *"stack profiling instructions"*) target="$run_dir/stack-context.md" ;;
  *"synthesis agent for a multi-agent code review"*) target="$run_dir/REPORT.md" ;;
  *"extract every distinct code-review finding"*) target="$run_dir/findings/count.txt" ;;
  *"independent code-review confidence scorer"*)
    target="$(printf '%s\n' "$prompt" | sed -n 's/^Write exactly two lines to \(.*\):$/\1/p' | head -1)"
    ;;
  *"final code-review triage editor"*) target="$run_dir/FINAL.md" ;;
esac

if [ -n "$target" ] && [ -s "$target" ] && [ -f "$target.complete" ]; then
  printf 'Recovered completed stage: %s\n' "$target" >&2
  exit 0
fi
[ -z "$target" ] || rm -f "$target.complete"

provider_pid=""
forward_provider_signal() {
  signal="$1"
  [ -z "$provider_pid" ] || kill -"$signal" "$provider_pid" 2>/dev/null || true
}
trap 'forward_provider_signal TERM' TERM
trap 'forward_provider_signal INT' INT
trap 'forward_provider_signal HUP' HUP

"$real" "$@" &
provider_pid=$!
wait "$provider_pid"
status=$?
provider_pid=""
trap - TERM INT HUP
if [ "$status" -eq 0 ] && [ -n "$target" ] && [ -s "$target" ]; then
  # Extractor completion is only durable when every declared finding exists.
  if [ "$target" = "$run_dir/findings/count.txt" ]; then
    count="$(tr -dc '0-9' <"$target" 2>/dev/null || true)"
    case "$count" in *[!0-9]*|'') count=-1;; esac
    if [ "$count" -ge 0 ] 2>/dev/null; then
      n=1
      complete=1
      while [ "$n" -le "$count" ]; do
        [ -s "$run_dir/findings/finding-$n.md" ] || complete=0
        n=$((n + 1))
      done
      [ "$complete" -eq 1 ] || exit "$status"
    fi
  fi
  marker="$target.complete.tmp.$$"
  printf 'complete\n' >"$marker"
  mv "$marker" "$target.complete"
fi
exit "$status"
EOF_PROVIDER
chmod +x "$SHIM_DIR/provider-shim"
[ -z "$REAL_CODEX" ] || ln -sf provider-shim "$SHIM_DIR/codex"
[ -z "$REAL_CLAUDE" ] || ln -sf provider-shim "$SHIM_DIR/claude"

finish_state() {
  status=$1
  trap - EXIT INT TERM HUP
  if [ "$status" -eq 0 ]; then
    printf '%s\n' completed >"$RUN_DIR/status"
    printf '%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >"$RUN_DIR/completed-at"
  else
    printf '%s\n' interrupted >"$RUN_DIR/status"
  fi
  rm -rf "$RUN_DIR/.lock" "$RUN_DIR/.shims"
}

ENGINE_PID=""
forward_signal() {
  signal="$1"
  if [ -n "$ENGINE_PID" ]; then kill -"$signal" "$ENGINE_PID" 2>/dev/null || true; fi
}
trap 'forward_signal TERM' TERM
trap 'forward_signal INT' INT
trap 'forward_signal HUP' HUP
trap 'status=$?; finish_state "$status"' EXIT

export DEEP_REVIEW_ACTIVE_RUN_DIR="$RUN_DIR"
export DEEP_REVIEW_REAL_MKTEMP="$REAL_MKTEMP"
export DEEP_REVIEW_REAL_CODEX="$REAL_CODEX"
export DEEP_REVIEW_REAL_CLAUDE="$REAL_CLAUDE"
export PATH="$SHIM_DIR:$PATH"

# The engine's --keep-results becomes persistent here because its mktemp target is the
# durable run directory selected above.
bash "$ENGINE" --max-concurrent "$SAFE_MAX" --keep-results "${ENGINE_ARGS[@]}" &
ENGINE_PID=$!
set +e
wait "$ENGINE_PID"
status=$?
set -e
ENGINE_PID=""

if [ "$status" -eq 0 ]; then
  finish_state 0
  trap - EXIT
  printf 'Saved review artifacts: %s\n' "$RUN_DIR" >&2

  # Keep storage bounded without deleting interrupted recovery candidates.
  keep="${DEEP_REVIEW_KEEP_COMPLETED_RUNS:-20}"
  case "$keep" in *[!0-9]*|'') keep=20;; esac
  if [ "$keep" -gt 0 ]; then
    completed=0
    entries="$(find "$RUNS_DIR" -type d -name 'run-*' -prune -print 2>/dev/null | sort -r || true)"
    old_ifs="$IFS"
    IFS='
'
    for run in $entries; do
      [ -d "$run" ] || continue
      [ "$(cat "$run/status" 2>/dev/null || true)" = completed ] || continue
      completed=$((completed + 1))
      if [ "$completed" -gt "$keep" ] && [ "$run" != "$RUN_DIR" ]; then rm -rf "$run"; fi
    done
    IFS="$old_ifs"
  fi
  exit 0
fi

finish_state "$status"
trap - EXIT
printf 'Review interrupted; resumable artifacts: %s\n' "$RUN_DIR" >&2
exit "$status"
