#!/usr/bin/env bash
# Shared target resolution for the durable runner and direct engine entry point.
# Bash 3.2 compatible. Sourcing this file has no filesystem side effects.

# Resolve an existing file/directory before any working-directory change. Directory
# symlinks use the physical target; files keep their basename in the physical parent.
deep_review_absolute_target() {
  local target="$1" parent
  [ -e "$target" ] || { echo "Review target does not exist: $target" >&2; return 2; }
  if [ -d "$target" ]; then
    (cd -- "$target" && pwd -P)
  elif [ -f "$target" ]; then
    parent="$(cd -- "$(dirname -- "$target")" && pwd -P)" || return 2
    printf '%s/%s\n' "${parent%/}" "$(basename -- "$target")"
  else
    echo "Review target must be a file or directory: $target" >&2
    return 2
  fi
}

# Outputs ROOT_DIR, REVIEW_SCOPE_PATH (root-relative), REVIEW_SCOPE_MODE and
# REVIEW_IS_GIT. An explicit target, not the caller's repository, owns the review.
deep_review_resolve_scope() {
  local target="${1:-}" mode="$2" explicit="$3" anchor root
  REVIEW_SCOPE_PATH=""
  if [ -n "$target" ]; then
    target="$(deep_review_absolute_target "$target")" || return 2
    if [ -d "$target" ]; then anchor="$target"; else anchor="$(dirname -- "$target")"; fi
  else
    anchor="$(pwd -P)"
  fi

  # Inherited Git environment (for example from a hook) must not redirect an
  # explicitly selected filesystem target to the caller's repository/index.
  unset GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR GIT_INDEX_FILE GIT_PREFIX
  if root="$(git -C "$anchor" rev-parse --show-toplevel 2>/dev/null)"; then
    ROOT_DIR="$(cd -- "$root" && pwd -P)" || return 2
    REVIEW_IS_GIT=1
  else
    ROOT_DIR="$anchor"
    REVIEW_IS_GIT=0
  fi

  if [ -n "$target" ]; then
    if [ "$target" = "$ROOT_DIR" ]; then REVIEW_SCOPE_PATH=.
    else REVIEW_SCOPE_PATH="${target#"${ROOT_DIR%/}/"}"
    fi
  fi
  REVIEW_SCOPE_MODE="$mode"
  if [ "$REVIEW_IS_GIT" -eq 0 ] && [ "$mode" != path ]; then
    if [ "$explicit" -eq 1 ]; then
      echo "Branch/changes review requires a Git working tree at the target: $anchor" >&2
      return 2
    fi
    REVIEW_SCOPE_MODE=path
    REVIEW_SCOPE_PATH=.
  fi
  case "/$REVIEW_SCOPE_PATH/" in
    */.deep-review/*)
      echo "Generated .deep-review reports are excluded from review targets." >&2
      return 2
      ;;
  esac
}

# User-specified storage paths stay relative to the invocation directory, never
# to a target selected later. They need not exist yet.
deep_review_absolute_output() {
  case "$1" in
    /*) printf '%s\n' "$1" ;;
    *) printf '%s/%s\n' "${2%/}" "$1" ;;
  esac
}

# Reserve the tool's generated report directories, even when accidentally tracked.
DEEP_REVIEW_GIT_EXCLUDE=':(glob,exclude)**/.deep-review/**'

# Non-Git recovery must depend on actual file contents, not just the target path.
# Do not follow directory symlinks; include their link text so retargeting changes
# the fingerprint. Sorting records makes the result independent of find order.
deep_review_hash_tree() (
  cd -- "$ROOT_DIR" || exit 1
  find "./$1" \( -type d \( -name .git -o -name .deep-review \) -prune \) -o \
    \( -type f -o -type l \) -print0 |
    while IFS= read -r -d '' file; do
      if [ -L "$file" ]; then
        checksum="$(readlink "$file" | cksum)" || exit 1
        printf 'link=%s:%s\n' "$file" "$checksum"
      fi
      if [ -f "$file" ]; then
        checksum="$(cksum <"$file")" || exit 1
        printf 'file=%s:%s\n' "$file" "$checksum"
      fi
    done | LC_ALL=C sort
)
