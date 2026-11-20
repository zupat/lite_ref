part of 'scoped.dart';

/// A [ScopedRef] is a reference that needs a context to access the instance.
@immutable
class ScopedRef<T> implements IScopedRef<T> {
  /// Creates a new [ScopedRef] which always return a new instance.
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
  ScopedRef(
    CtxCreateFn<T> create, {
    DisposeFn<T>? dispose,
    bool autoDispose = true,
  })  : _create = create,
        _id = Object(),
        _ownership =
            autoDispose ? _LastListener<T>(dispose) : _Retained<T>(dispose);

  const ScopedRef._(
    CtxCreateFn<T> create,
    Object id, {
    required _Ownership<T> ownership,
  })  : _create = create,
        _id = id,
        _ownership = ownership;

  final Object _id;

  /// Whether a scope-owned instance is disposed when it loses its last
  /// listener.
  ///
  /// This does not control ownership: `autoDispose: false` values are still
  /// disposed when the scope unmounts or their override is replaced. Use
  /// [overrideWithValue] for values owned by the caller.
  @override
  bool get autoDispose => _ownership.autoDispose;

  final _Ownership<T> _ownership;

  final CtxCreateFn<T> _create;

  ScopedObject<T> _createRefObject(_RefScopeElement owner) {
    return _createScopedObject<T>(
      owner,
      id: _id,
      create: () => _create(owner),
      ownership: _ownership,
    );
  }

  /// Returns `true` if this [ScopedRef] is initialized
  /// in the current [LiteRefScope].
  bool exists(BuildContext context) {
    assert(
      context is Element,
      'This must be called with the context of a Widget.',
    );

    final element = LiteRefScope._of(context, this);

    return element._cache.containsKey(_cacheKey);
  }

  Object get _cacheKey => _id;

  /// Returns the instance of [T] in the current scope.
  ///
  /// If [listen] is `false`, the instance will not be disposed when the widget
  /// is unmounted.
  ///
  /// ```dart
  /// class SettingsPage extends StatelessWidget {
  ///   const SettingsPage({super.key});
  ///
  ///   @override
  ///   Widget build(BuildContext context) {
  ///     final settingsService = settingsServiceRef.of(context);
  ///     return Text(settingsService.getThemeMode());
  ///   }
  /// }
  /// ```
  T of(BuildContext context, {bool listen = true}) {
    assert(
      context is Element,
      'This must be called with the context of a Widget.',
    );

    return _resolveScoped<T>(
      context: context,
      ref: this,
      lookupId: _id,
      cacheKey: _cacheKey,
      listen: listen,
      create: (element, effective) {
        return (effective as ScopedRef<T>)._createRefObject(element);
      },
    );
  }

  /// Returns the instance of [T] in the current scope without disposing it
  /// when the widget is unmounted. This should be used in callbacks like
  /// `onPressed` or `onTap`.
  ///
  /// Alias for `of(context, listen: false)`.
  T read(BuildContext context) {
    return of(context, listen: false);
  }

  /// Equivalent to calling the [of(context)] getter.
  T call(BuildContext context) => of(context);

  /// Returns a new ScopedRef with a different [create] function.
  /// When used with a [LiteRefScope] overrides, any child widget that accesses
  /// the instance will use the new [create] function.
  ///
  /// Set [autoDispose] to `false` to keep the instance alive when it has no
  /// listeners. The scope still disposes it when the scope unmounts or the
  /// override is replaced, so use [overrideWithValue] for an externally owned
  /// value. Callers migrating from
  /// `overrideWith((_) => value, autoDispose: false)` should switch to
  /// `overrideWithValue(value)` when the caller owns that value.
  ///
  /// The [create] context is the owning [LiteRefScope]'s context, so inherited
  /// lookups do not see widgets between that scope and the requesting widget.
  ///
  ///```dart
  ///LiteRefScope(
  ///    overrides: [
  ///       settingsServiceRef.overrideWith((ctx) => MockSettingsService()),
  ///    ]
  ///    child: MyApp(),
  ///    ),
  ///```
  ScopedRef<T> overrideWith(CtxCreateFn<T> create, {bool autoDispose = true}) {
    final dispose = _disposerOf(_ownership);
    return ScopedRef._(
      create,
      _id,
      ownership:
          autoDispose ? _LastListener<T>(dispose) : _Retained<T>(dispose),
    );
  }

  /// Overrides this ref with an externally owned [value].
  ///
  /// The scope never disposes [value], including when the scope unmounts or
  /// this override is replaced. The value remains cached until then because
  /// externally owned values use `autoDispose: false`.
  ScopedRef<T> overrideWithValue(T value) {
    return ScopedRef._(
      (_) => value,
      _id,
      ownership: _CallerOwned<T>(),
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (runtimeType != other.runtimeType) return false;
    if (other is ScopedRef<T>) return _id == other._id;
    return false;
  }

  @override
  int get hashCode => _id.hashCode;
}
