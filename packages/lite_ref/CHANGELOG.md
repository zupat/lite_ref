## 1.0.0

First stable release. The public API of `lite_ref` is now considered stable for
the 1.x line. This release includes scoped-ref lifecycle and ownership fixes,
plus one breaking ownership change and one behavior change described below.

-   [Fix] Scoped refs created inside another ref now resolve from the owning
    scope, retain their dependencies, and release them only after dependent
    disposers run. Replacing a dependency also rebuilds its dependents.
    Lookup paths are revalidated when overrides or `onlyOverrides` change and
    when a keyed scope moves to a new parent.
-   [Fix] Chained dependency disposal now completes in the same post-frame
    cleanup, including dependencies owned by another scope, failed factories
    release acquired dependencies, stale family and
    non-overridden entries are evicted when `onlyOverrides` is enabled, and
    throwing or nullable disposers no longer interrupt or skip cleanup.
-   [Feat] Added `overrideWithValue` for externally owned values that must never
    be disposed by a scope.
-   [Breaking] `autoDispose: false` now only disables zero-listener disposal.
    Scope-owned values are still disposed on override replacement and scope
    unmount. Migrate externally owned values from
    `overrideWith((_) => value, autoDispose: false)` to
    `overrideWithValue(value)`.

    Before, `autoDispose: false` also meant "the scope never disposes this":

    ```dart
    LiteRefScope(
      overrides: {
        databaseRef.overrideWith((_) => sharedDatabase, autoDispose: false),
      },
      child: const App(),
    );
    ```

    Now the scope still owns that value and closes it on unmount or replacement.
    When the caller owns it, say so explicitly:

    ```dart
    LiteRefScope(
      overrides: {databaseRef.overrideWithValue(sharedDatabase)},
      child: const App(),
    );
    // The scope never disposes sharedDatabase; close it yourself.
    ```

    Keep `autoDispose: false` for a value the scope owns but should retain after
    its last listener leaves.

-   [Behavior] Factories now receive the owning `LiteRefScope` context rather
    than the requesting widget's context, which also affects inherited lookups
    such as `Theme.of`.

    A factory is built once for the scope, so it cannot see inherited widgets
    that sit *below* that scope:

    ```dart
    final brightnessRef = Ref.scoped((ctx) => Theme.of(ctx).brightness);

    LiteRefScope(
      child: Theme(
        data: ThemeData(brightness: Brightness.dark),
        child: Builder(
          builder: (context) {
            // Resolves above LiteRefScope, not the dark Theme below it.
            return Text('${brightnessRef(context)}');
          },
        ),
      ),
    );
    ```

    Put inherited dependencies the factory needs above the scope instead:

    ```dart
    final brightnessRef = Ref.scoped((ctx) => Theme.of(ctx).brightness);

    Theme(
      data: ThemeData(brightness: Brightness.dark),
      child: LiteRefScope(
        child: Builder(
          builder: (context) => Text('${brightnessRef(context)}'), // dark
        ),
      ),
    );
    ```

-   [Deps] Requires `lite_ref_core` `^1.0.0`.

## 0.8.4

Patch release that points the package at its new repository location. There are
no code or public API changes.

-   [Docs] Updated the repository, banner, and coverage links to the new
    `zupat/lite_ref` GitHub location.

## 0.8.3

Patch release that picks up the `lite_ref_core` 0.1.2 concurrency fixes for
`AsyncSingletonRef`. There are no public API changes.

-   [Fix] Updated `lite_ref_core` to `^0.1.2`, which fixes concurrent retries
    creating multiple singletons, a concurrent `instance` read running the
    replacement factory twice during `overrideWith`, and an override during
    initial creation leaving the original instance cached.

## 0.8.2

Patch release with lifecycle fixes for `LiteRefScope`. There are no public API
changes.

-   [Fix] Fixed a leak where a widget moved to another `LiteRefScope` with a
    `GlobalKey` kept its old auto-dispose bindings, and therefore its old
    instance, alive until the previous scope unmounted.
-   [Fix] Fixed stale instances when a scope's overrides change in place.
    Replacing an override now recreates the instance for that ref and notifies
    mounted consumers, including consumers of `autoDispose: false` refs and
    family refs whose argument is `null`.
-   [Fix] Fixed `onlyOverrides` scopes resolving refs from a stale parent after
    being moved with a `GlobalKey`, and not re-resolving when `onlyOverrides`
    is toggled.
-   [Fix] An override now follows its own `autoDispose` flag instead of the
    original ref's, so it can enable or disable auto-disposal independently.
-   [Behavior] Mounted consumers now switch to the new instance when a scope's
    overrides or `onlyOverrides` change, instead of keeping the instance they
    first resolved. Instances that are no longer in use are disposed once they
    have no consumers. This can happen earlier than before, so code that keeps
    a reference to a scoped instance in a callback or a long-lived object must
    not use it after the scope changes.

## 0.8.1

-   [Fix] Fixed bug with disposal of widget state.

## 0.8.0

-   [Fix] Fixed bug with hot-reloading
-   [Feat] Add `Ref.scopedFamily` which takes a argument to create a unique instance for each key.

    -   Create a `ScopedFamilyRef`.

        ```dart
        final postControllerRef = Ref.scopedFamily((ctx, String key) {
        return PostController(key)..fetch();
        });
        ```

    -   Access the instance in the current scope:

        This can be done in a widget by using `postController.of(context, key)` or `postController(context, key)`.

        ```dart
        class PostsPage extends StatelessWidget {
        const PostsPage({required this.keys, super.key});

        final List<String> keys;

        @override
        Widget build(BuildContext context) {
            return ListView.builder(
            itemBuilder: (context, index) {
                final post = postControllerRef.of(context, keys[index]);
                return Text(post?.title ?? 'Loading...');
            },
            );
        }
        }
        ```

## 0.7.0

-   [Fix] Fixed bug where refs were disposed when the child is temporarily deactivated.
-   [Breaking] The `overrides` property of `LiteRefScope` is now a Set of `ScopedRef`s instead of a List of `ScopedRef`s.

    ### Before

    ```dart
    LiteRefScope(
    overrides: [
        settingsServiceRef.overrideWith((ctx) => MockSettingsService()),
    ]
    child: MyApp(),
    )
    ```

    ### After:

    ```dart
    LiteRefScope(
    overrides: {
        settingsServiceRef.overrideWith((ctx) => MockSettingsService()),
    }
    child: MyApp(),
    )
    ```

## 0.6.3

-   [Refactor] minor refactor

## 0.6.2

-   [Feat] Add `onlyOverrides` to `LiteRefScope` which will only provide overridden instances to children.

## 0.6.1

-   [Feat] Add `ScopedRef.exists(context)` method to check if a ScopedRef is initialized in the current LiteRefScope.

## 0.6.0

-   Update flutter dependency constraint

## 0.5.2

-   [Refactor] Add core package as a dependency.

## 0.5.1

-   [Fix] Remove `dispose` function when overriding with `autoDispose` set to `false`.

## 0.5.0

-   [Feat] Add auto-disposal for `ChangeNotifiers` and any class that implements `Disposable`. These classes will be disposed when all the widgets that have access to the instance are unmounted. If providing a existing and you don't want the instance to be disposed set `autoDispose` to `false`.

    In the example below, the `CounterController` will be disposed when the `CounterView` is unmounted.

    ```dart
    class CounterController extends ChangeNotifier {
    var _count = 0;
    int get count => _count;

    void increment() {
        _count++;
        notifyListeners();
    }

    void decrement() {
        _count--;
        notifyListeners();
    }
    }

    final countControllerRef = Ref.scoped((ctx) => CounterController());

    class CounterView extends StatelessWidget {
    const CounterView({super.key});

    @override
    Widget build(BuildContext context) {
        final controller = countControllerRef.of(context);
        return ListenableBuilder(
        listenable: controller,
        builder: (context, snapshot) {
            return Text('${controller.count}');
        },
        );
    }
    }
    ```

## 0.4.1

-   [Docs] Add documentation comments and examples

## 0.4.0

-   [Breaking] This now a flutter package
-   Add `ScopedRef` which is a ref that needs a context to access its instance
-   Add `LiteRefScope` which coupled with`ScopedRef` is an alternative to `Provider` for classes that don't rebuild widgets.

    -   Wrap your app or a subtree with a `LiteRefScope`:

        ```dart
        runApp(
        LiteRefScope(
            child: MyApp(),
        ),
        );
        ```

    -   Create a `ScopedRef`.

        ```dart
        final settingsServiceRef = Ref.scoped((ctx) => SettingsService());
        ```

    -   Access the instance in the current scope:

        This can be done in a widget by using `settingsServiceRef.of(context)` or `settingsServiceRef(context)`.

        ```dart
        class SettingsPage extends StatelessWidget {
        const SettingsPage({super.key});

        @override
        Widget build(BuildContext context) {
            final settingsService = settingsServiceRef.of(context);
            return Text(settingsService.getThemeMode());
        }
        }
        ```

    -   Override it for a subtree:

        You can override the instance for a subtree by using `overrideWith`. This is useful for testing.
        In the example below, all calls to `settingsServiceRef.of(context)` will return `MockSettingsService`.

        ```dart
        LiteRefScope(
            overrides: [
                settingsServiceRef.overrideWith((ctx) => MockSettingsService()),
            ]
            child: MyApp(),
            ),
        ```

## 0.3.0

-   Make the factory function non-nullable (improves performance and maintainability)

## 0.2.1

-   Internal performance improvements
-   fix minor bug where async singleton would not be replace when overridden

## 0.2.0

-   separate singleton and transient instantiation use: `Ref.singleton`, `Ref.transient`, `Ref.asyncSingleton` and `Ref.asyncTransient`
-   add `assertInstance` getter for synchronous access to a AsyncSingletonRef

## 0.1.0

-   prevent race condition when fetching async singleton
-   add `assertInstance` getter for synchronous access to a LiteAsyncRef
-   add `.freeze()` method which disables overriding

## 0.0.2

-   Update readme

## 0.0.1

-   Initial release
