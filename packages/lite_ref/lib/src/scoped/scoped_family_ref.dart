part of 'scoped.dart';

/// A [ScopedFamilyRef] is a reference that needs a context to access instances.
@immutable
class ScopedFamilyRef<T, F> implements IScopedRef<T> {
  /// Creates a new [ScopedFamilyRef] which always return new instances.
  ///
  /// By default, a scope-owned instance is disposed when its last listening
  /// widget is unmounted. Set [autoDispose] to `false` to keep it cached with
  /// zero listeners; the scope still disposes it on unmount or override
  /// replacement. Use [overrideWithValue] for an externally owned instance.
  ///
  /// A [dispose] function does not have to be provided if [T] implements
  /// [Disposable].
  ///
  /// The [create] context is the owning [LiteRefScope]'s context. Refs and
  /// inherited lookups such as `Theme.of` resolve there, not in a descendant
  /// consumer, so they do not see inherited widgets below the owning scope.
  ScopedFamilyRef(
    CtxFamilyCreateFn<T, F> create, {
    DisposeFn<T>? dispose,
    this.autoDispose = true,
  })  : _create = create,
        _onDispose = dispose,
        _owned = true,
        _id = Object();

  const ScopedFamilyRef._(
    CtxFamilyCreateFn<T, F> create,
    Object id, {
    required this.autoDispose,
    DisposeFn<T>? dispose,
    bool owned = true,
  })  : _create = create,
        _id = id,
        _onDispose = dispose,
        _owned = owned;

  final Object _id;

  /// Whether a scope-owned instance is disposed when it loses its last
  /// listener.
  ///
  /// This does not control ownership: `autoDispose: false` values are still
  /// disposed when the scope unmounts or their override is replaced. Use
  /// [overrideWithValue] for values owned by the caller.
  @override
  final bool autoDispose;

  final DisposeFn<T>? _onDispose;

  final bool _owned;

  final CtxFamilyCreateFn<T, F> _create;

  ScopedObject<T> _createRefObject(_RefScopeElement owner, F family) {
    return _createScopedObject<T>(
      owner,
      id: (_id, family),
      dispose: _onDispose,
      create: () => _create(owner, family),
      autoDispose: autoDispose,
      owned: _owned,
    );
  }

  /// Returns `true` if this [ScopedFamilyRef] with that [family] is initialized
  /// in the current [LiteRefScope].
  bool exists(BuildContext context, F family) {
    assert(
      context is Element,
      'This must be called with the context of a Widget.',
    );

    final element = LiteRefScope._of(context, this);

    return element._cache.containsKey((_id, family));
  }

  /// Returns the instance of [T] in the current scope for that family.
  ///
  /// If [listen] is `false`, the instance will not be disposed when the widget
  /// is unmounted.
  ///
  /// Every family key read by a listening widget remains bound until that
  /// widget unmounts, including keys read by earlier builds. To release old
  /// instances when [family] changes, put this lookup in a keyed child widget
  /// whose key contains the family value.
  ///
  /// ```dart
  /// class ProductWidget extends StatelessWidget {
  ///   const SettingsPage({required this.id, super.key});
  ///
  ///   final int id;
  ///
  ///   @override
  ///   Widget build(BuildContext context) {
  ///     final productController = productControllerRef.of(context, id);
  ///     return Text(productController.getName());
  ///   }
  /// }
  /// ```

  T of(BuildContext context, F family, {bool listen = true}) {
    assert(
      context is Element,
      'This must be called with the context of a Widget.',
    );

    final traversedScopes = <_RefScopeElement>[];
    final element = LiteRefScope._of(context, this, traversed: traversedScopes);

    final existing = element._cache[(_id, family)];

    void bindIfNeeded(ScopedObject<dynamic> ref) {
      if (!listen) return;

      final creating = _creatingRefs.isEmpty ? null : _creatingRefs.last;
      if (creating != null) {
        element._addObjectDependency(creating, ref);
        for (final traversed in traversedScopes) {
          traversed._addLookupDependency(creating, _id);
        }
        return;
      }

      // Scopes that were traversed but did not serve the ref must notify
      // this consumer when their overrides change (e.g. an `onlyOverrides`
      // scope that gains an override for this ref).
      for (final traversed in traversedScopes) {
        traversed._addDependent(context as Element);
      }

      element._bind(context as Element, ref);
    }

    if (existing != null) {
      bindIfNeeded(existing);
      return existing._instance as T;
    }

    final refOverride = element.scope.overrides?.lookup(this);

    if (refOverride != null) {
      final refObject =
          (refOverride as ScopedFamilyRef)._createRefObject(element, family);
      element._cache[refObject._id] = refObject;
      bindIfNeeded(refObject);
      return refObject._instance as T;
    }

    final refObject = _createRefObject(element, family);

    bindIfNeeded(refObject);

    element._cache[refObject._id] = refObject;

    return refObject._instance;
  }

  /// Returns the instance of [T] in the current scope without disposing it
  /// when the widget is unmounted. This should be used in callbacks like
  /// `onPressed` or `onTap`.
  ///
  /// Alias for `of(context, family, listen: false)`.
  T read(BuildContext context, F family) {
    return of(context, family, listen: false);
  }

  /// Equivalent to calling the [of(context, family)] getter.
  T call(BuildContext context, F family) => of(context, family);

  /// Returns a new ScopedFamilyRef with a different [create] function.
  /// When used with a [LiteRefScope] overrides, any child widget that accesses
  /// the instance will use the new [create] function.
  ///
  /// Set [autoDispose] to `false` to keep instances alive when they have no
  /// listeners. The scope still disposes them when the scope unmounts or the
  /// override is replaced, so use [overrideWithValue] for an externally owned
  /// value. Callers migrating from
  /// `overrideWith((_, __) => value, autoDispose: false)` should switch to
  /// `overrideWithValue(value)` when the caller owns that value.
  ///
  /// The [create] context is the owning [LiteRefScope]'s context, so inherited
  /// lookups do not see widgets between that scope and the requesting widget.
  ///
  ///```dart
  ///LiteRefScope(
  ///    overrides: [
  ///       productServiceRef.overrideWith((ctx, _) => MockProductService()),
  ///    ]
  ///    child: MyApp(),
  ///    ),
  ///```
  ScopedFamilyRef<T, F> overrideWith(
    CtxFamilyCreateFn<T, F> create, {
    bool autoDispose = true,
  }) {
    return ScopedFamilyRef._(
      create,
      _id,
      dispose: _onDispose,
      autoDispose: autoDispose,
    );
  }

  /// Overrides this ref with an externally owned [value] for every family.
  ///
  /// The scope never disposes [value], including when the scope unmounts or
  /// this override is replaced. The value remains cached until then because
  /// externally owned values use `autoDispose: false`.
  ScopedFamilyRef<T, F> overrideWithValue(T value) {
    return ScopedFamilyRef._(
      (_, __) => value,
      _id,
      autoDispose: false,
      owned: false,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (runtimeType != other.runtimeType) return false;
    if (other is ScopedFamilyRef<T, F>) return _id == other._id;
    return false;
  }

  @override
  int get hashCode => _id.hashCode;
}
