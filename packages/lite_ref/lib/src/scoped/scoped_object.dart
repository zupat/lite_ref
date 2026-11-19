part of 'scoped.dart';

/// Objects whose factories are currently running.
final _creatingRefs = <_PendingScopedObject<dynamic>>[];

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

/// The lifecycle of a completed [ScopedObject].
///
/// The single impossible state of two booleans is gone: a ref is either live,
/// waiting for its dependents to release it, or disposed.
enum _Lifecycle { live, awaitingDependentRelease, disposed }

/// A node that can acquire dependencies while it is being built or alive.
///
/// A [ScopedObject] is both a dependent and a potential dependency.
/// A [_PendingScopedObject] is only ever a dependent: it is not in any cache
/// until its factory succeeds.
sealed class _Dependent {
  final _dependencies = <ScopedObject<dynamic>>{};

  /// Ref IDs whose lookups passed through scopes during creation.
  final _lookupRegistrations = <_RefScopeElement, Set<Object>>{};

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

      if (dependency._lifecycle == _Lifecycle.awaitingDependentRelease) {
        _disposeSafely(dependency);
      } else if (dependency.autoDispose && dependency._watchCount < 1) {
        dependency._owner._scheduleDisposal(dependency);
      }
    }
  }
}

/// A [ScopedObject] is a reference that holds an instance of [T].
///
/// If [autoDispose] is `true`, the instance is disposed when all widgets that
/// have access to it are unmounted. This only controls zero-listener cleanup;
/// scope-owned values are disposed on scope unmount and override replacement
/// regardless.
class ScopedObject<T> extends _Dependent {
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

  ScopedObject._({
    required Object id,
    required T instance,
    required _RefScopeElement owner,
    required _Ownership<T> ownership,
  })  : _id = id,
        _instance = instance,
        _owner = owner,
        _ownership = ownership;

  final T _instance;

  final Object _id;

  late final _RefScopeElement _owner;

  final _Ownership<T> _ownership;

  /// Whether the instance should be disposed when all the widgets that have
  /// access to the instance are unmounted.
  bool get autoDispose => _ownership.autoDispose;

  final _dependents = <_Dependent>{};

  int _watchCount = 0;

  _Lifecycle _lifecycle = _Lifecycle.live;

  void _dispose() {
    if (_lifecycle == _Lifecycle.disposed) return;

    // An evicted dependency must remain usable by its dependents' disposers.
    // The last dependent to release it completes the pending disposal.
    if (_dependents.isNotEmpty) {
      _lifecycle = _Lifecycle.awaitingDependentRelease;
      return;
    }

    _lifecycle = _Lifecycle.disposed;

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
}

/// A [ScopedObject] whose factory has not returned yet.
final class _PendingScopedObject<T> extends _Dependent {
  _PendingScopedObject({
    required this.id,
    required this.owner,
    required this.ownership,
  });

  final Object id;

  final _RefScopeElement owner;

  final _Ownership<T> ownership;

  /// Turns this in-progress creation into a cached object.
  ///
  /// A pending object is only ever a dependent, never a dependency: it is not
  /// in any scope cache, so moving its back-pointers is one-directional.
  ScopedObject<T> complete(T instance) {
    final object = ScopedObject<T>._(
      id: id,
      instance: instance,
      owner: owner,
      ownership: ownership,
    );

    for (final dependency in _dependencies) {
      assert(
        dependency._dependents.contains(this),
        'A pending object must only be a dependent.',
      );
      dependency._dependents
        ..remove(this)
        ..add(object);
      object._dependencies.add(dependency);
    }
    _dependencies.clear();

    for (final entry in _lookupRegistrations.entries) {
      for (final id in entry.value) {
        final dependents = entry.key._lookupDependents[id];
        assert(
          dependents != null && dependents.contains(this),
          'A pending object must be registered as a lookup dependent.',
        );
        dependents
          ?..remove(this)
          ..add(object);
      }
      object._lookupRegistrations[entry.key] = Set<Object>.of(entry.value);
    }
    _lookupRegistrations.clear();

    return object;
  }

  /// Releases everything the failed factory acquired.
  void abandon() {
    _releaseDependencies();
  }
}

ScopedObject<T> _createScopedObject<T>(
  _RefScopeElement owner, {
  required Object id,
  required T Function() create,
  required _Ownership<T> ownership,
}) {
  final pending = _PendingScopedObject<T>(
    id: id,
    owner: owner,
    ownership: ownership,
  );

  _creatingRefs.add(pending);

  try {
    // Only a completed entry enters the cache, including one whose value is
    // legitimately `null`.
    return pending.complete(create());
  } catch (_) {
    // Dependencies acquired before a factory failed still retain their refs.
    pending.abandon();
    rethrow;
  } finally {
    _creatingRefs.remove(pending);
  }
}
