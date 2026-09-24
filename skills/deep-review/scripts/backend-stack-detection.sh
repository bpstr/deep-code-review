#!/usr/bin/env bash
# Sourced by the engine. Bash 3.2; inspect data only, never execute project code.

backend_scope_files() {
  local path resolved
  while IFS= read -r path; do
    [ -n "$path" ] || continue
    case "$path" in
      "$ROOT_DIR") path=. ;;
      "$ROOT_DIR"/*) path="${path#"$ROOT_DIR"/}" ;;
      /*|../*|*/../*|*/..) continue ;;
    esac
    path="${path#./}"
    case "/$path/" in */vendor/*|*/node_modules/*|*/.git/*|*/.venv/*|*/venv/*) continue ;; esac
    if [ -d "$path" ]; then
      resolved="$(cd "$path" && pwd -P)" || continue
      case "$resolved" in "$ROOT_DIR"|"$ROOT_DIR"/*) ;; *) continue ;; esac
      find "./$path" -type d \( -name .git -o -name vendor -o -name node_modules -o -name .venv -o -name venv -o -name __pycache__ -o -name target -o -name build \) -prune -o -type f -print
    else
      # Deleted scoped paths retain their ancestor manifest context.
      printf '%s\n' "$path"
    fi
  done <<EOF_SCOPE
$CHANGED_FILES
EOF_SCOPE
}

backend_data_has() {
  local pattern="$1" file
  shift
  for file in "$@"; do
    [ -f "$file" ] && [ ! -L "$file" ] || continue
    grep -Eiq -- "$pattern" "$file" && return 0
  done
  return 1
}

backend_context_signals() {
  local dir="$1" composer_seen=0 python_seen=0 jvm_seen=0 file found
  while :; do
    if [ "$composer_seen" -eq 0 ] && [ -f "$dir/composer.json" ]; then
      composer_seen=1
      printf '%s\n' php
      if backend_data_has '"(drupal/core(-recommended|-dev)?|drupal/drupal)"|"type"[[:space:]]*:[[:space:]]*"drupal-(module|theme|profile)"' "$dir/composer.json"; then printf '%s\n' drupal; fi
      if backend_data_has '"laravel/framework"[[:space:]]*:' "$dir/composer.json"; then printf '%s\n' laravel; fi
    fi
    # Extension metadata works for standalone modern and Drupal 7 modules.
    for file in "$dir"/*.info.yml "$dir"/*.info; do
      if backend_data_has "^[[:space:]]*core_version_requirement[[:space:]]*:|^[[:space:]]*core[[:space:]]*=[[:space:]]*['\"]?7\\.x" "$file"; then printf '%s\n' drupal; fi
    done
    if [ "$python_seen" -eq 0 ]; then
      found=0
      for file in "$dir"/pyproject.toml "$dir"/setup.cfg "$dir"/setup.py "$dir"/Pipfile "$dir"/requirements*.txt "$dir"/requirements/*.txt; do
        [ -f "$file" ] && [ ! -L "$file" ] || continue
        found=1
        if backend_data_has '(^|[^[:alnum:]_-])django([^[:alnum:]_-]|$)' "$file"; then printf '%s\n' django; fi
      done
      if [ "$found" -eq 1 ]; then python_seen=1; printf '%s\n' python; fi
    fi
    if [ "$jvm_seen" -eq 0 ]; then
      found=0
      for file in "$dir"/pom.xml "$dir"/build.gradle "$dir"/build.gradle.kts; do
        [ -f "$file" ] && [ ! -L "$file" ] || continue
        found=1
        if backend_data_has 'org\.springframework|spring-boot' "$file" "$dir/gradle/libs.versions.toml"; then printf '%s\n' spring; fi
        if backend_data_has 'io\.ktor' "$file" "$dir/gradle/libs.versions.toml"; then printf '%s\n' ktor; fi
      done
      [ "$found" -eq 0 ] || jvm_seen=1
    fi
    [ "$dir" != . ] || break
    dir="$(dirname "$dir")"
  done
}

detect_backend_specialists() {
  local path dir resolved signals cached_values=("") cached_keys=("") index key found
  local php_scope python_scope jvm_scope
  while IFS= read -r path; do
    [ -n "$path" ] || continue
    php_scope=0; python_scope=0; jvm_scope=0
    case "$path" in
      *.php|*.module|*.install|*.inc|*.theme|*.profile|composer.json|*/composer.json|composer.lock|*/composer.lock) printf '%s\n' php-reviewer; php_scope=1 ;;
      *.py|pyproject.toml|*/pyproject.toml|requirements*.txt|*/requirements*.txt) printf '%s\n' python-reviewer; python_scope=1 ;;
      *.java) printf '%s\n' java-reviewer; jvm_scope=1 ;;
      *.kt|*.kts|*/pom.xml|pom.xml|*/build.gradle|build.gradle|*/build.gradle.kts|build.gradle.kts|*/libs.versions.toml) jvm_scope=1 ;;
    esac
    case "$path" in *.twig|*.js|*.css|*.yml|*.yaml|*.info|*.json|*.lock|*/artisan|artisan) php_scope=1 ;; esac
    case "$path" in *.html|*.txt|*.toml|*.cfg|*.lock|*/Pipfile|Pipfile|*.yml|*.yaml) python_scope=1 ;; esac
    case "$path" in *.xml|*.properties|*.yml|*.yaml) jvm_scope=1 ;; esac
    [ "$php_scope$python_scope$jvm_scope" != 000 ] || continue
    dir="$(dirname "$path")"
    # Never inspect a symlinked directory outside the repository.
    if [ -d "$dir" ]; then
      resolved="$(cd "$dir" && pwd -P)" || continue
      case "$resolved" in "$ROOT_DIR") dir=. ;; "$ROOT_DIR"/*) dir="${resolved#"$ROOT_DIR"/}" ;; *) continue ;; esac
    fi
    found=0; index=0; signals=
    for key in "${cached_keys[@]}"; do
      if [ "$key" = "$dir" ]; then signals="${cached_values[$index]}"; found=1; break; fi
      index=$((index + 1))
    done
    if [ "$found" -eq 0 ]; then
      signals="$(backend_context_signals "$dir")"
      cached_keys+=("$dir"); cached_values+=("$signals")
    fi
    if [ "$php_scope" -eq 1 ]; then
      case "$signals" in *php*|*drupal*|*laravel*) printf '%s\n' php-reviewer ;; esac
      case "$signals" in *drupal*) printf '%s\n' drupal-reviewer ;; esac
      case "$signals" in *laravel*) printf '%s\n' laravel-reviewer ;; esac
    fi
    if [ "$python_scope" -eq 1 ]; then
      case "$signals" in *python*) printf '%s\n' python-reviewer ;; esac
      case "$signals" in *django*) printf '%s\n' django-reviewer ;; esac
    fi
    if [ "$jvm_scope" -eq 1 ]; then
      case "$signals" in *spring*) printf '%s\n' spring-reviewer ;; esac
      case "$path:$signals" in *.kt:*spring*|*.kt:*ktor*) printf '%s\n' kotlin-server-reviewer ;; esac
    fi
    # Explicit imports can identify standalone sources without manifests.
    case "$path" in
      *.py) if backend_data_has '^[[:space:]]*(from|import)[[:space:]]+django([.[:space:]]|$)' "$path"; then printf '%s\n' django-reviewer; fi ;;
      *.java|*.kt) if backend_data_has '^[[:space:]]*import[[:space:]]+org\.springframework\.' "$path"; then printf '%s\n' spring-reviewer; case "$path" in *.kt) printf '%s\n' kotlin-server-reviewer ;; esac; fi ;;
    esac
  done <<EOF_FILES
$(backend_scope_files)
EOF_FILES
}
