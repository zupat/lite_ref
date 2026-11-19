part of 'scoped.dart';

final _creatingRefs = <ScopedObject<dynamic>>[];

/// A [ScopedObject] is a reference that holds an instance of [T].
///
/// If [autoDispose] is `true`, the instance is disposed when all widgets that
/// have access to it are unmounted. This only controls zero-listener cleanup;
/// scope-owned values are disposed on scope unmount and override replacement
/// regardless.
class ScopedObject<T> {
  /// Creates a new [ScopedObject] with an [id] and an [instance].
  ScopedObject({
    required Object id,
    required T instance,
    DisposeFn<T>? dispose,
    this.autoDispose = true,
    bool owned = true,
  })  : _id = id,
        _onDispose = dispose,
        _instance = instance,
        _owned = owned;

  ScopedObject._creating({
    required Object id,
    DisposeFn<T>? dispose,
    this.autoDispose = true,
    bool owned = true,
  })  : _id = id,
        _onDispose = dispose,
        _owned = owned;

  late final T _instance;

  final Object _id;

  late final _RefScopeElement _owner;

  /// Whether the instance should be disposed when all the widgets that have
  /// access to the instance are unmounted.
  final bool autoDispose;

  final bool _owned;

  final DisposeFn<T>? _onDispose;

  final _dependencies = <ScopedObject<dynamic>>{};

  final _dependents = <ScopedObject<dynamic>>{};

  /// Ref IDs whose lookups passed through other scopes during creation.
  final _lookupRegistrations = <_RefScopeElement, Set<Object>>{};

  int _watchCount = 0;

  bool _disposed = false;

  bool _disposePending = false;

  void _dispose() {
    if (_disposed) return;

    // An evicted dependency must remain usable by its dependents' disposers.
    // The last dependent to release it completes the pending disposal.
    if (_dependents.isNotEmpty) {
      _disposePending = true;
      return;
    }

    _disposePending = false;
    _disposed = true;

    try {
      if (!_owned) return;

      // An explicit disposer also receives successfully created null values.
      _onDispose?.call(_instance);
      if (_onDispose == null) {
        if (_instance case final Disposable d) {
          d.dispose();
        } else if (_instance case final ChangeNotifier c) {
          // covers ChangeNotifier and ValueNotifier
          c.dispose();
        }
      }
    } finally {
      _releaseDependencies();
    }
  }

  void _releaseDependencies() {
    for (final entry in _lookupRegistrations.entries) {
      for (final id in entry.value) {
        final dependents = entry.key._lookupDependents[id];
        dependents?.remove(this);
        if (dependents?.isEmpty ?? false) {
          entry.key._lookupDependents.remove(id);
        }
      }
    }
    _lookupRegistrations.clear();

    if (_dependencies.isEmpty) return;

    final dependencies = List<ScopedObject<dynamic>>.of(_dependencies);
    _dependencies.clear();

    for (final dependency in dependencies) {
      dependency._dependents.remove(this);
      dependency._watchCount--;

      if (dependency._disposePending) {
        _disposeSafely(dependency);
      } else if (dependency.autoDispose && dependency._watchCount < 1) {
        dependency._owner._scheduleDisposal(dependency);
      }
    }
  }
}

ScopedObject<T> _createScopedObject<T>(
  _RefScopeElement owner, {
  required Object id,
  required T Function() create,
  DisposeFn<T>? dispose,
  bool autoDispose = true,
  bool owned = true,
}) {
  final refObject = ScopedObject<T>._creating(
    id: id,
    dispose: dispose,
    autoDispose: autoDispose,
    owned: owned,
  ).._owner = owner;

  _creatingRefs.add(refObject);

  try {
    refObject._instance = create();
    return refObject;
  } catch (_) {
    // Dependencies acquired before a factory failed still retain their refs.
    refObject._releaseDependencies();
    rethrow;
  } finally {
    _creatingRefs.remove(refObject);
  }
}
