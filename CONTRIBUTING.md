# Contributing to Lite Ref

Thanks for contributing. This guide covers setup, testing, style, and the pull
request flow. For how the scoped-ref implementation actually works, read
[`ARCHITECTURE.md`](ARCHITECTURE.md) first — it is the fastest way to get
oriented before touching code.

## Repository layout

- `packages/lite_ref` — the Flutter package: `LiteRefScope`, `ScopedRef`,
  `ScopedFamilyRef`, and the `Ref` factories.
- `packages/lite_ref_core` — the dependency-free core: `SingletonRef`,
  `TransientRef`, `AsyncSingletonRef`, `AsyncTransientRef`, and the base `Ref`
  they share.
- `examples/` — example apps, also used for manual verification.

## Prerequisites

- A recent Flutter SDK (the package targets Dart `>=3.0.0` and Flutter
  `>=3.17.0`). CI runs against the version pinned in the workflow.

## Setup

```bash
./run.sh deps
```

This runs `flutter pub get` for `packages/lite_ref`, `packages/lite_ref_core`,
and the examples.

## Testing

```bash
./run.sh test core      # lite_ref_core
./run.sh test flutter   # lite_ref (scoped refs)
./run.sh test all       # both
```

`test flutter` runs `flutter test --coverage --timeout 5s` inside
`packages/lite_ref`. Coverage is tracked and expected to stay complete; the
suite uses `// coverage:ignore` pragmas for lines that are unreachable by
design, so add those deliberately rather than letting CI discover them.

Run analysis too:

```bash
cd packages/lite_ref && flutter analyze
```

## Style

- `very_good_analysis` `5.1.0` lints the code — keep `flutter analyze` clean.
- Line length is 80 columns (`ignore_for_file: lines_longer_than_80_chars` is
  only used where doc-comment URLs force it).
- The scoped-ref core is deliberately split into *pure* decision functions and
  *impure* Flutter effects. When adding logic, prefer a pure function with a
  plain return value over one that mutates the widget tree, and keep it in the
  file that owns the concept (see the file map in
  [`ARCHITECTURE.md`](ARCHITECTURE.md)).

## Making a change

1. Open an issue or describe the change in the PR. There is no public API to
   add here without a good reason — the public surface of `ScopedRef`,
   `ScopedFamilyRef`, `IScopedRef`, `ScopedObject`, `LiteRefScope`, and `Ref`
   is intentionally small and stable.
2. If you change behavior, add or update a test in
   `packages/lite_ref/test/src/scoped/ref_test.dart`. For a bug, write the
   failing test first. Edge cases that have bitten this code before: failed
   factories, throwing disposers, cross-scope overrides, `onlyOverrides`
   resolution, and same-frame `GlobalKey` rebinding — see the
   `scoped lifecycle regressions` group.
3. If you refactor internals, keep `test/public_api_test.dart` green. It
   imports only the public entry point, so it fails the moment the
   implementation leans on library-private access a real consumer cannot use.
4. Run `./run.sh test all` and `flutter analyze` before pushing.

## Pull requests

- Keep commits small and reviewable; the recent functional refactor was merged
  as one commit per concern for exactly this reason.
- Fill out the PR template and link the issue it closes.
- CI runs `./run.sh test all` plus analysis. Do not merge with failing checks.
