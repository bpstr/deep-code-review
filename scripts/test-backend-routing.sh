#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "$ROOT/skills/deep-review/scripts/backend-stack-detection.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/backend-routing.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/repo"
cd "$TMP/repo"
ROOT_DIR="$(pwd -P)"
count=0
check() {
  local name="$1" paths="$2" expected="$3" actual
  CHANGED_FILES="$paths"
  actual="$(detect_backend_specialists | sort -u | tr '\n' ' ' | sed 's/ $//')"
  if [ "$actual" != "$expected" ]; then
    printf 'FAIL %s\nexpected: %s\nactual:   %s\n' "$name" "$expected" "$actual" >&2
    exit 1
  fi
  count=$((count + 1))
}
put() { mkdir -p "$(dirname "$1")"; printf '%s\n' "$2" >"$1"; }
put plain/src/main.java 'class Main {}'
check plain-java plain/src/main.java java-reviewer
put plain/build.gradle.kts 'plugins { java }'
check gradle-kotlin-dsl plain/build.gradle.kts ''
put android/build.gradle.kts 'plugins { id("com.android.application") }'
put android/Main.kt 'class Main'
check android-not-server android/Main.kt ''
put web/composer.json '{"require":{"laravel/framework":"^12.0"}}'
put web/app/Task.php '<?php class Task {}'
check laravel-php web/app/Task.php 'laravel-reviewer php-reviewer'
put web/resources/views/task.blade.php '<p>{{ $task->name }}</p>'
check laravel-template web/resources/views/task.blade.php 'laravel-reviewer php-reviewer'
put web/deploy.yml 'queue: redis'
check laravel-config web/deploy.yml 'laravel-reviewer php-reviewer'
put web/packages/plain/composer.json '{"require":{"php":"^8.2"}}'
put web/packages/plain/src/Value.php '<?php class Value {}'
check nested-php-boundary web/packages/plain/src/Value.php php-reviewer
put component/composer.json '{"require":{"illuminate/support":"^12.0","symfony/console":"^7.0"}}'
put component/lib.php '<?php'
check component-not-application component/lib.php php-reviewer
put cms/composer.json '{"require":{"drupal/core-recommended":"^10.3"}}'
put cms/web/modules/custom/demo/demo.module '<?php'
check drupal-module cms/web/modules/custom/demo/demo.module 'drupal-reviewer php-reviewer'
for ext in install inc theme profile; do
  put "cms/web/modules/custom/demo/demo.$ext" '<?php'
  check "drupal-$ext" "cms/web/modules/custom/demo/demo.$ext" 'drupal-reviewer php-reviewer'
done
put standalone/demo.info.yml 'name: Demo
core_version_requirement: ^10 || ^11
type: module'
put standalone/demo.routing.yml 'demo: {}'
check standalone-drupal-config standalone/demo.routing.yml 'drupal-reviewer php-reviewer'
put legacy/demo.info 'name = Demo
core = "7.x"'
put legacy/demo.module '<?php'
check drupal-seven legacy/demo.module 'drupal-reviewer php-reviewer'
put python-app/pyproject.toml '[project]
dependencies = ["Django>=5.2,<6"]'
put python-app/app/views.py 'pass'
check nested-django python-app/app/views.py 'django-reviewer python-reviewer'
put python-app/templates/page.html '<p>{{ title }}</p>'
check django-template python-app/templates/page.html 'django-reviewer python-reviewer'
put python-app/libs/plain/pyproject.toml '[project]
dependencies = []'
put python-app/libs/plain/src/tool.py 'pass'
check nested-python-boundary python-app/libs/plain/src/tool.py python-reviewer
put unrelated/tool.py 'pass'
check no-sibling-borrowing unrelated/tool.py python-reviewer
put direct.py 'from django.db import models'
check source-django direct.py 'django-reviewer python-reviewer'
put backend/pom.xml '<project><dependencies><dependency><groupId>org.springframework.boot</groupId></dependency></dependencies></project>'
put backend/src/Main.java 'class Main {}'
check spring-java backend/src/Main.java 'java-reviewer spring-reviewer'
put backend/src/main/resources/application.yml 'spring: {}'
check spring-config backend/src/main/resources/application.yml spring-reviewer
put backend/src/App.kt 'class App'
check spring-kotlin backend/src/App.kt 'kotlin-server-reviewer spring-reviewer'
put catalog/build.gradle.kts 'dependencies { implementation(libs.spring.boot) }'
put catalog/gradle/libs.versions.toml 'spring-boot = { module = "org.springframework.boot:spring-boot-starter-web", version = "3.4.0" }'
put catalog/src/App.kt 'class App'
check spring-catalog catalog/src/App.kt 'kotlin-server-reviewer spring-reviewer'
put standalone-java/Foo.java 'import org.springframework.stereotype.Service;'
check spring-import standalone-java/Foo.java 'java-reviewer spring-reviewer'
put 'space app/composer.json' '{"require":{"laravel/framework":"^12.0"}}'
put 'space app/src/My Task.php' '<?php'
check paths-with-spaces 'space app/src/My Task.php' 'laravel-reviewer php-reviewer'
check directory-scope 'space app' 'laravel-reviewer php-reviewer'
check absolute-directory "$ROOT_DIR/space app" 'laravel-reviewer php-reviewer'
check deleted-source web/app/Removed.php 'laravel-reviewer php-reviewer'
put web/README.md 'Laravel project'
check readme-only web/README.md ''
put web/vendor/package/lib.php '<?php'
check vendor-only web/vendor/package/lib.php ''
check explicit-mixed "web/app/Task.php
backend/src/Main.java" 'java-reviewer laravel-reviewer php-reviewer spring-reviewer'
# No command substitution or setup.py code is executed during manifest inspection.
put hostile/setup.py 'import os; os.system("touch EXECUTED") # django'
put hostile/views.py 'pass'
check data-only hostile/views.py 'django-reviewer python-reviewer'
test ! -e EXECUTED
printf 'backend routing passed (%s cases; no model calls)\n' "$count"
