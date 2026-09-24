# Backend framework review research

Research date: 2026-09-24. Scope: the Drupal, Laravel, Django/DRF and Spring gaps identified in the repository audit, plus adjacent Symfony/Doctrine considerations. Sources below are primary framework documentation. Versioned references are research baselines, not mandatory upgrade targets. Review against the application's declared and resolved versions.

## Findings translated into reviewer rules

| Area | High-value failure classes | Essential counterexample |
| --- | --- | --- |
| Drupal | Cross-user/stale render cache, access-result metadata loss, content-query access choice, entity/field access, unsafe schema updates, configuration import/schema behavior | Inherited cache metadata is valid; authorized maintenance may use accessCheck(FALSE); Drupal 7 needs legacy semantics |
| Laravel | Tenant binding/authorization gaps, observer-bypassing bulk writes, pre-commit queue races, duplicate side effects, cached configuration mismatch, Octane stale request state | Connection-wide after_commit removes the need for a per-job call; safe allowlists make unguarded models non-exploitable; process env remains accessible |
| Django/DRF | List-result authorization gaps, query amplification, lifecycle changes from bulk operations, broken atomic blocks, commit callback testing, historical migrations, sync/async boundaries | Global permissions may protect a view; nested atomic is supported; only/defer and exists can add work rather than improve it |
| Spring | Proxy bypass, incorrect rollback/propagation assumptions, singleton state leaks, query/session behavior, effective filter-chain authorization, framework tests that bypass the mechanism | Spring 6 class proxies can advise protected/package-visible transactional methods; field injection/OSIV/readOnly omission alone are not failures |
| Symfony/Doctrine | Retry-safe Messenger effects, shared-service reset, entity-manager recovery after rollback | A service need not be non-shared if its state is correctly scoped/reset; retries are not necessarily bugs |

The shared framework contract requires applicability, effective configuration, a reachable operation, violated invariant, counterevidence and a validation path. Architecture improvements remain eligible as P2 when the maintenance consequence is evidenced. It rejects checklist-style claims based only on absent annotations, syntax or preferred layers.

## Drupal source map

- [Render cacheability](https://www.drupal.org/docs/drupal-apis/render-api/cacheability-of-render-arrays): variation, invalidation, lifetime and metadata propagation. Entity view builders can already supply dependencies; inspect the result instead of grepping for #cache.
- [Explicit content entity query access](https://www.drupal.org/node/3201242): deprecation in 9.2 and exception behavior in 10; separate the requirement to choose from the correctness of the chosen access policy.
- [Configuration schema](https://www.drupal.org/docs/drupal-apis/configuration-api/configuration-schemametadata): type casting, translation, import/export and schema-sensitive tests.
- [hook_update_N API](https://api.drupal.org/api/drupal/core%21lib%21Drupal%21Core%21Extension%21module.api.php/function/hook_update_N/11.x): updates execute against evolving schema; normal entity CRUD is unsafe in this phase. Do not modernize historical migrations using current entity assumptions.

## Laravel source map

- [Authorization](https://laravel.com/docs/13.x/authorization): inspect gates/policies and effective boundaries rather than requiring a particular class layout.
- [Sanctum](https://laravel.com/docs/13.x/sanctum): first-party SPA authentication can be session/cookie based, unlike personal bearer-token authentication.
- [Eloquent](https://laravel.com/docs/13.x/eloquent): bounded traversal, mass assignment boundaries, model events and bulk operations.
- [Queues](https://laravel.com/docs/13.x/queues): dispatch relative to transactions, connection/job configuration, retry and worker timeout behavior. Delivery guarantees must be distinguished from business-effect idempotency.
- [Configuration](https://laravel.com/docs/13.x/configuration): config caching stops loading .env; actual process environment values can still be available to env().
- [Octane](https://laravel.com/docs/13.x/octane): boot-once workers and stale request/container/config references. Findings require a long-lived execution mode.

## Django/DRF source map

- [Database optimization](https://docs.djangoproject.com/en/5.2/topics/db/optimization/): profile first, reason about queryset reuse and related fetches, and preserve lifecycle semantics when considering bulk writes.
- [Transactions](https://docs.djangoproject.com/en/5.2/topics/db/transactions/): supported nested savepoints, broken-transaction recovery, on_commit and transaction-wrapped test behavior.
- [Migrations](https://docs.djangoproject.com/en/5.2/topics/migrations/): historical model state and backend/deployment constraints.
- [Async support](https://docs.djangoproject.com/en/6.0/topics/async/): native async transaction limitations and sync boundaries. Recheck when reviewing a later version.
- [Django 4.0 release notes](https://docs.djangoproject.com/en/4.0/releases/4.0/): SECURE_BROWSER_XSS_FILTER was removed; never recommend reintroducing it to modern settings.
- [DRF permissions](https://www.django-rest-framework.org/api-guide/permissions/): default policies, object checks, list queryset restrictions and creation behavior are separate concerns.

## Spring source map

- [Transactional annotations](https://docs.spring.io/spring-framework/reference/data-access/transaction/declarative/annotations.html): proxy type/method visibility, external invocation, version-sensitive defaults and configuration.
- [Rollback rules](https://docs.spring.io/spring-framework/reference/data-access/transaction/declarative/rolling-back.html): unchecked versus checked exceptions, configured rules and already-failed Future handling.
- [Proxying](https://docs.spring.io/spring-framework/reference/core/aop/proxying.html): self-invocation and subclass/interface constraints; account for weaving and Kotlin compiler plugins.
- [Request authorization](https://docs.spring.io/spring-security/reference/servlet/authorization/authorize-http-requests.html): effective filter/matcher ordering and policy instead of annotation counting.
- [Test transaction management](https://docs.spring.io/spring-framework/reference/testing/testcontext-framework/tx.html): tests must exercise the boundary being claimed; test transactions and absent flushes can hide production behavior.

## Adjacent Symfony/Doctrine research

- [Messenger](https://symfony.com/doc/current/messenger.html): retries/redelivery, durable idempotency and long-lived worker service state. The existing PHP reviewer covers the baseline; component dependencies alone must not activate full-application assumptions.
- [Doctrine transactions and concurrency](https://www.doctrine-project.org/projects/doctrine-orm/en/current/reference/transactions-and-concurrency.html): unit-of-work boundaries, rollback/entity-manager state and concurrency controls.

## Implementation and validation policy

Expose dedicated Drupal, Laravel and Spring selectors alongside the existing Django selector. Keep generic language selection and the historical core/exact-full compatibility modes. Route only from scoped file/manifest evidence, including framework configuration and legacy Drupal extensions; inspect ancestor manifests for nested applications without borrowing sibling applications' dependencies. Do not execute project code during detection.

Tests should cover selectors, positive and negative routing, nested projects, configuration-only changes, legacy Drupal, framework versions and counterexamples. Cheap tests validate routing and knowledge contracts; opt-in model fixtures measure behavior. Passing static tests is not evidence of model precision/recall, and small fixtures are not substitutes for representative application evaluations.
