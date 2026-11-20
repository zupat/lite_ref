## 1.0.0

First stable release. The public API of `lite_ref_core` is now considered
stable for the 1.x line. There are no code changes since 0.1.3; this release
marks the package as stable alongside `lite_ref` 1.0.0.

## 0.1.3

Patch release that points the package at its new repository location. There are
no code or public API changes.

-   [Docs] Updated the repository, banner, and coverage links to the new
    `zupat/lite_ref` GitHub location.

## 0.1.2

Patch release with concurrency fixes for `AsyncSingletonRef`. There are no public API
changes.

-   [Fix] Fixed concurrent retries creating multiple singletons when several callers
    waited on a failed initialization. Retries now re-check the lock, so only one
    re-initialization runs and all callers receive the same instance (instead of
    overwriting each other's lock and potentially hitting a null-check error).
-   [Fix] Fixed a concurrent `instance` read running the replacement factory twice
    during `overrideWith`. The override now holds the initialization lock.
-   [Fix] Fixed an override issued while the initial factory was still running leaving
    the original instance cached. The in-flight result is now discarded so the
    replacement factory's instance is the one that gets cached.

## 0.1.1

-   Update readme

## 0.1.0

-   Initial release
