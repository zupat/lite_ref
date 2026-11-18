part of 'async.dart';

/// A [AsyncSingletonRef] is a reference with an asynchronous factory/creation
/// function that always return the same instance.
class AsyncSingletonRef<T> extends AsyncTransientRef<T> {
  /// {@macro ref}
  AsyncSingletonRef(super.create);

  T? _instance;
  var _success = false;
  Completer<void>? _lock;
  var _generation = 0;

  /// Returns `true` if the instance has been created.
  bool get hasInstance => _success;

  /// Returns instance if it has been created.
  /// Otherwise, it throws a [StateError].
  T get assertInstance {
    if (hasInstance) return _instance as T;

    throw StateError(
      'The instance has not been created yet. '
      'You must call `instance` first and await it.',
    );
  }

  /// Returns a the singleton instance of [T].
  @override
  Future<T> get instance => _getInstance();

  Future<T> _getInstance() async {
    while (true) {
      // Only return the instance if it was successfully created.
      if (_success) return _instance as T;

      // If an instance is being created, wait for that attempt to settle and
      // re-evaluate. Re-checking on every iteration makes sure that several
      // waiters of a failed creation never start overlapping retries.
      final lock = _lock;
      if (lock != null) {
        await lock.future;
        continue;
      }

      // Take ownership of the initialization lock. There is no `await`
      // between the check above and this assignment, so at most one caller
      // can become the creator of an attempt.
      final myLock = _lock = Completer<void>();
      final myGeneration = _generation;
      final create = _create;

      try {
        final created = await create();

        // An override that ran while `create` was in flight supersedes this
        // result, so it must not become the cached instance.
        if (_generation == myGeneration) {
          _instance = created;
          _success = true;
          return created;
        }
      } catch (_) {
        // The creator reports the failure to its own caller; waiters simply
        // retry on their next iteration. A superseded failure is ignored.
        if (_generation == myGeneration) rethrow;
      } finally {
        myLock.complete();
        if (identical(_lock, myLock)) _lock = null;
      }

      // Either the attempt failed or it was superseded: loop and retry.
    }
  }

  /// Sets the function used to create instances.
  /// Throws a [StateError] if `this` has been frozen.
  @override
  @visibleForTesting
  Future<void> overrideWith(AsyncFactory<T> create) async {
    _assertNotFrozen();

    // A rebuild is only needed when there is a cached instance to replace or
    // a creation in flight whose result would otherwise be cached.
    final needsRebuild = _success || _lock != null;

    _create = create;
    _generation++;
    _success = false;

    if (needsRebuild) {
      // Going through the lock prevents a concurrent `instance` read from
      // running the replacement factory a second time. Bumping the generation
      // discards any result the previous factory was about to cache.
      await _getInstance();
    }
  }
}
