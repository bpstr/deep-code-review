# Backend framework reviews

Framework findings apply the [shared evidence contract](framework-review.md). These are model reviewer instructions, not a claim of exhaustive static-analysis coverage.

| Selector | Framework ownership |
| --- | --- |
| `drupal` / `drupal-reviewer` | Render cache variation/invalidation, access metadata, entities/routes/forms, configuration, update hooks, services/plugins and repeated behaviors |
| `laravel` / `laravel-reviewer` | Policies/tenant boundaries, Eloquent lifecycle/queries, commit-aware queues, idempotency, configuration caching and long-lived workers |
| `django` / `django-reviewer` | ORM/queryset behavior, Django/DRF permissions, transactions, historical migrations, async boundaries and effective settings |
| `spring` / `spring-boot` / `spring-reviewer` | Spring Framework/Boot/Security, proxies, rollback/propagation, JPA/session boundaries, bean lifecycle and Servlet/reactive execution |

Language reviewers remain separate. Examples:

```bash
bash "$SKILL_DIR/scripts/deep-review.sh" --changes php drupal
bash "$SKILL_DIR/scripts/deep-review.sh" --changes php laravel
bash "$SKILL_DIR/scripts/deep-review.sh" --changes python django
bash "$SKILL_DIR/scripts/deep-review.sh" --changes java spring
bash "$SKILL_DIR/scripts/deep-review.sh" --changes kotlin-server spring
bash "$SKILL_DIR/scripts/deep-review.sh" full
```

`full`/`smart` automatically add relevant specialists. `core` and exact `--no-auto-specialists full` retain their old sets and model-call shape. Explicit framework reviewers still receive one shared stack profile. Dedicated language and framework findings are deduplicated by root cause, not by suppressing different defects at the same line.

## Detection

The backend detector reads scoped files and nearby manifests without evaluating project code, installing packages or starting applications. PHP includes `.module`, `.install`, `.inc`, `.theme` and `.profile`. Drupal extension metadata works without a root Composer manifest, including legacy Drupal 7 metadata. Templates, framework configuration and relevant assets can select a framework even without source-language changes.

Nearest Composer/Python/build manifests define lookup boundaries so a nested independent package does not inherit an unrelated parent application's framework. Sibling applications are not scanned to infer another application's stack. Maven/Gradle Spring declarations, a colocated Gradle version catalog or direct Spring imports can select Spring. `.java` selects Java; `.kt` selects the server Kotlin reviewer only with Spring/Ktor evidence. `build.gradle.kts` alone is not Kotlin application evidence.

Directory scopes inspect files under that directory, pruning common dependency/build directories and avoiding symlink traversal. Detection is intentionally lexical and conservative, not a dependency resolver: inherited Maven parents, remote BOMs, custom Gradle catalogs/convention plugins and dynamically assembled requirements can require an explicit selector. Use `full spring`, for example, when a known framework is not detectable from local signals. The shared profiler establishes actual versions and configuration; it does not silently execute a build to resolve unknowns.

## Calibration

The reviewers inspect effective defaults, outer transactions, inherited authorization, generated/cache metadata and alternative implementations before emitting a finding. Missing annotations, repositories, Redis, field injection alternatives or current syntax do not independently justify a failure.

High-value counterexamples include Drupal metadata already attached by another renderer, authorized accessCheck(FALSE), Laravel connection-wide after_commit, DRF global permissions, nested atomic blocks, Spring 6 protected-method class proxies and configured checked-exception rollback. Versioned references are research baselines, not demands to upgrade the application.

The source repository contains `FRAMEWORK-REVIEW-RESEARCH.md`, `scripts/test-backend-routing.sh`, `scripts/test-framework-review.sh` and positive/negative entries in `reviewer-fixtures/manifest.tsv`. Routing/static/mock tests consume no model calls. Model fixtures remain explicitly opt-in; their regex oracle is a calibration aid, not a precision/recall benchmark.
