part of 'scoped.dart';

final _creatingRefs = <ScopedObject<dynamic>>[];

/// Who is responsible for disposing a scoped value.
///
/// Only the two scope-owned variants carry disposal behavior, so a
/// caller-owned value is structurally incapable of being disposed by a scope.
sealed class _Ownership<T> {
  const _Ownership();

  /// Whether the value is disposed when it loses its last listener.
  bool get autoDispose;
}

/// The caller owns the value. The scope only releases its dependencies.
final class _CallerOwned<T> extends _Ownership<T> {
  const _CallerOwned({this.autoDispose = false});

  @override
  final bool autoDispose;
}

/// The scope owns the value.
sealed class _ScopeOwned<T> extends _Ownership<T> {
  const _ScopeOwned(this.dispose);

  final DisposeFn<T>? dispose;
}

/// Scope-owned and retained until the scope unmounts or the override is
/// replaced.
final class _Retained<T> extends _ScopeOwned<T> {
  const _Retained(super.dispose);

  @override
  bool get autoDispose => false;
}

/// Scope-owned and disposed when the last listener goes away, in addition to
/// the retained lifetime events.
final class _LastListener<T> extends _ScopeOwned<T> {
  const _LastListener(super.dispose);

  @override
  bool get autoDispose => true;
}

DisposeFn<T>? _disposerOf<T>(_Ownership<T> ownership) {
  return switch (ownership) {
    _ScopeOwned<T>(:final dispose) => dispose,
    _CallerOwned<T>() => null,
  };
}

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
    bool autoDispose = true,
    bool owned = true,
  })  : _id = id,
        _instance = instance,
        _ownership = owned
            ? (autoDispose
                ? _LastListener<T>(dispose)
                : _Retained<T>(dispose))
            : _CallerOwned<T>(autoDispose: autoDispose);

  ScopedObject._creating({
    required Object id,
    required _Ownership<T> ownership,
  })  : _id = id,
        _ownership = ownership;

  late final T _instance;

  final Object _id;

  late final _RefScopeElement _owner;

  final _Ownership<T> _ownership;

  /// Whether the instance should be disposed when all the widgets that have
  /// access to the instance are unmounted.
  bool get autoDispose => _ownership.autoDispose;

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
      if (_ownership case _ScopeOwned<T>(:final dispose)) {
        // An explicit disposer also receives successfully created null values.
        dispose?.call(_instance);
        if (dispose == null) {
          if (_instance case final Disposable d) {
            d.dispose();
          } else if (_instance case final ChangeNotifier c) {
            // covers ChangeNotifier and ValueNotifier
            c.dispose();
          }
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
  required _Ownership<T> ownership,
}) {
  final refObject = ScopedObject<T>._creating(
    id: id,
    ownership: ownership,
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
