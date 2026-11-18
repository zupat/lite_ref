part of 'scoped.dart';

typedef _Cache = Map<Object, ScopedObject<dynamic>>;

/// The scope that currently holds each listening element's auto-dispose
/// binding, keyed by element and by the binding's ref key
/// ([ScopedObject._id], i.e. `_id` or `(_id, family)`).
///
/// When a ref starts resolving to another scope (an `onlyOverrides` scope
/// gaining an override), the stale binding is released through this index so
/// the abandoned instance can be disposed while its consumer stays mounted.
final _consumerBindings = <Element, Map<Object, _RefScopeElement>>{};

/// Dependency injection of [ScopedRef]s.
class LiteRefScope extends InheritedWidget {
  /// Create a new [LiteRefScope]
  /// If [onlyOverrides] is true, only overridden
  /// ScopedRefs will be provided to children.
  ///
  /// If [onlyOverrides] is true, only overridden
  /// ScopedRefs will be provided to children.
  const LiteRefScope({
    required super.child,
    super.key,
    this.overrides,
    this.onlyOverrides = false,
  });

  /// List of ScopedRefs to override.
  final Set<IScopedRef<dynamic>>? overrides;

  /// If true, only overridden ScopedRefs will be provided to children.
  final bool onlyOverrides;

  // coverage:ignore-start
  @override
  bool updateShouldNotify(covariant InheritedWidget oldWidget) => false;
  // coverage:ignore-end

  @override
  InheritedElement createElement() => _RefScopeElement(this);

  static _RefScopeElement _of(
    BuildContext context,
    IScopedRef<dynamic> ref, {
    List<_RefScopeElement>? traversed,
  }) {
    final element =
        context.getElementForInheritedWidgetOfExactType<LiteRefScope>();

    assert(
      element != null,
      '''
  You must wrap your app with a `LiteRefScope`.

  runApp(
    LiteRefScope(
      child: MyApp(),
    ),
  );
  ''',
    );

    final refScopeElement = element! as _RefScopeElement;

    // if the element's widget is onlyOverride, we need to check if the ref
    // is in the overrides list, if not, we need to visit all ancestors
    // until we find an element with the ref or one that is not onlyOverride
    if (refScopeElement.scope.onlyOverrides) {
      traversed?.add(refScopeElement);

      if (refScopeElement.scope.overrides?.contains(ref) ?? false) {
        return refScopeElement;
      }

      var parentElement = refScopeElement._parentScope;

      while (parentElement != null) {
        if (!parentElement.scope.onlyOverrides) break;

        traversed?.add(parentElement);

        if (parentElement.scope.overrides?.contains(ref) ?? false) {
          break;
        }

        parentElement = parentElement._parentScope;
      }

      if (parentElement == null) {
        throw Exception(
          'Could not find a LiteRefScope with "${ref.runtimeType}" '
          'or one that is not marked as onlyOverride. '
          'Please note that "onlyOverride" must be false '
          'for the root LiteRefScope',
        );
      }

      return parentElement;
    }

    return refScopeElement;
  }
}

class _RefScopeElement extends InheritedElement {
  _RefScopeElement(LiteRefScope super.widget);

  /// The closest ancestor scope, looked up lazily so that a scope moved
  /// with a [GlobalKey] always resolves against its new parent.
  _RefScopeElement? get _parentScope {
    _RefScopeElement? parent;

    visitAncestorElements((ancestor) {
      if (ancestor is _RefScopeElement) {
        parent = ancestor;
        return false;
      }
      return true;
    });

    return parent;
  }

  LiteRefScope get scope => widget as LiteRefScope;

  late final _cache = _Cache();

  late final _autoDisposeBindings = <Element, Set<ScopedObject<dynamic>>>{};

  /// Every element that listens to a ref through this scope.
  ///
  /// Kept separately from [_autoDisposeBindings] because consumers of refs
  /// with `autoDispose: false` still need to be notified when the
  /// overrides change.
  late final _listeningElements = <Element>{};

  late final _oldRefs = <ScopedObject<dynamic>>[];

  /// Refs whose last consumer may have gone away this frame.
  late final _pendingDisposals = <ScopedObject<dynamic>>[];

  /// Refs evicted from the cache because an override changed.
  late final _evictedRefs = <ScopedObject<dynamic>>[];

  bool _disposalScheduled = false;

  void _addDependent(Element element) {
    if (_listeningElements.add(element)) {
      // make this child widget depend on this element
      // so we get notified when it is deactivated
      element.dependOnInheritedElement(this);
    }
  }

  void _addAutoDisposeBinding(Element element, ScopedObject<dynamic> ref) {
    _addDependent(element);

    final existing = _autoDisposeBindings[element];

    if (existing != null) {
      final added = existing.add(ref);
      if (added) ref._watchCount++;
    } else {
      ref._watchCount++;
      _autoDisposeBindings[element] = {ref};
    }
  }

  /// Binds [dependent] to [ref], which resolved to this scope.
  ///
  /// If the same ref key was previously bound in another scope, that binding
  /// is released first so the abandoned instance can be disposed even though
  /// the dependent stays mounted.
  void _bind(Element dependent, ScopedObject<dynamic> ref) {
    _addDependent(dependent);

    final key = ref._id;
    final bindings = _consumerBindings[dependent];
    final previous = bindings?[key];

    if (previous != null && !identical(previous, this)) {
      previous._releaseBinding(dependent, key);
    }

    if (ref.autoDispose) {
      if (bindings == null) {
        _consumerBindings[dependent] = {key: this};
      } else {
        bindings[key] = this;
      }

      _addAutoDisposeBinding(dependent, ref);
    } else {
      bindings?.remove(key);
    }
  }

  /// Releases the binding of [dependent] for [key] held by this scope.
  void _releaseBinding(Element dependent, Object key) {
    final refs = _autoDisposeBindings[dependent];
    if (refs == null) return;

    ScopedObject<dynamic>? released;

    refs.removeWhere((ref) {
      if (ref._id != key) return false;
      released = ref;
      return true;
    });

    if (refs.isEmpty) {
      _autoDisposeBindings.remove(dependent);
    }

    final ref = released;
    if (ref == null || !ref.autoDispose) return;

    ref._watchCount--;
    if (ref._watchCount < 1) {
      _scheduleDisposal(ref);
    }
  }

  void _scheduleDisposal(ScopedObject<dynamic> ref) {
    if (!_pendingDisposals.any((e) => identical(e, ref))) {
      _pendingDisposals.add(ref);
    }

    _scheduleDisposalFlush();
  }

  void _scheduleDisposalFlush() {
    if (_disposalScheduled) return;
    _disposalScheduled = true;

    SchedulerBinding.instance.addPostFrameCallback((_) {
      _disposalScheduled = false;

      // If this scope went away, unmount already disposed everything.
      if (!mounted) return;

      for (final ref in _pendingDisposals) {
        // It may have been re-bound during the same frame, e.g. when a
        // widget is moved with a GlobalKey.
        if (ref._watchCount > 0) continue;
        if (!identical(_cache[ref._id], ref)) continue;
        _cache.remove(ref._id);
        ref._dispose();
      }
      _pendingDisposals.clear();

      // Evicted refs are no longer reachable through this scope, so they
      // must be disposed even if some consumer still holds a stale value.
      for (final ref in _evictedRefs) {
        ref._dispose();
      }
      _evictedRefs.clear();
    });
  }

  @override
  void deactivate() {
    // if this widget gets replaced by another LiteRefScope
    // (eg: hot-reload when it or one of its ancestors has a UniqueKey).
    // We need to store a copy of all Refs in our cache so we don't dispose
    // refs being used by its replacement.
    _oldRefs.addAll(_cache.values.map((e) => e._copy()));
    super.deactivate();
  }

// coverage:ignore-start
  @override
  void activate() {
    super.activate();
    _oldRefs.clear();
  }
// coverage:ignore-end

  @override
  void updated(covariant InheritedWidget oldWidget) {
    _handleLookupChanged(oldWidget as LiteRefScope);
    super.updated(oldWidget);
  }

  void _handleLookupChanged(LiteRefScope oldWidget) {
    final changedIds =
        _changedOverrideIds(oldWidget.overrides, scope.overrides);
    final onlyOverridesChanged = oldWidget.onlyOverrides != scope.onlyOverrides;

    // Toggling `onlyOverrides` changes where refs resolve even when the
    // override set is untouched.
    if (changedIds.isEmpty && !onlyOverridesChanged) return;

    final evicted = <ScopedObject<dynamic>>[];

    _cache.removeWhere((key, ref) {
      if (!changedIds.any((id) => _keyBelongsTo(key, id))) return false;
      evicted.add(ref);
      return true;
    });

    for (final ref in evicted) {
      for (final refs in _autoDisposeBindings.values) {
        refs.remove(ref);
      }
      _evictedRefs.add(ref);
    }

    if (evicted.isNotEmpty) {
      _scheduleDisposalFlush();
    }

    // Rebuild every listener so it can resolve the replacement before the
    // evicted instances are disposed. Consumers of refs with
    // `autoDispose: false` are included, and listeners are notified even when
    // nothing was evicted: gaining an override, or toggling `onlyOverrides`,
    // changes which scope serves the ref.
    for (final dependent in List<Element>.of(_listeningElements)) {
      notifyDependent(oldWidget, dependent);
    }
  }

  /// Ids of the refs whose resolved override changed.
  ///
  /// Overrides are compared by identity: two overrides for the same ref are
  /// equal (`==`) by design, so only a new instance means a new override.
  static Set<Object> _changedOverrideIds(
    Set<IScopedRef<dynamic>>? oldOverrides,
    Set<IScopedRef<dynamic>>? newOverrides,
  ) {
    final oldById = <Object, IScopedRef<dynamic>>{
      for (final ref in oldOverrides ?? const <IScopedRef<dynamic>>{})
        _idOf(ref): ref,
    };
    final newById = <Object, IScopedRef<dynamic>>{
      for (final ref in newOverrides ?? const <IScopedRef<dynamic>>{})
        _idOf(ref): ref,
    };

    final changed = <Object>{};

    for (final entry in newById.entries) {
      final previous = oldById[entry.key];
      if (previous == null || !identical(previous, entry.value)) {
        changed.add(entry.key);
      }
    }

    for (final id in oldById.keys) {
      if (!newById.containsKey(id)) changed.add(id);
    }

    return changed;
  }

  static Object _idOf(IScopedRef<dynamic> ref) => switch (ref) {
        ScopedRef() => ref._id,
        ScopedFamilyRef() => ref._id,
      };

  /// Cache keys are `_id` for a [ScopedRef] and `(_id, family)` for a
  /// [ScopedFamilyRef]. The family argument may be `null`.
  static bool _keyBelongsTo(Object key, Object id) {
    if (key == id) return true;
    return key is (Object, Object?) && key.$1 == id;
  }

  @override
  void removeDependent(Element dependent) {
    // Bindings are released eagerly (instead of only when the dependent is
    // unmounted) because a widget moved with a GlobalKey stays mounted:
    // it would otherwise keep its bindings in the old scope forever.
    final refs = _autoDisposeBindings.remove(dependent);
    _listeningElements.remove(dependent);
    _consumerBindings.remove(dependent);

    if (refs != null) {
      for (final ref in refs) {
        if (!ref.autoDispose) continue;

        ref._watchCount--;
        if (ref._watchCount < 1) {
          _scheduleDisposal(ref);
        }
      }
    }

    super.removeDependent(dependent);
  }

  @override
  void unmount() {
    // this shouldn't be necessary but it's harmless
    // we should be able to just use _oldRefs.
    final toBeDisposed = _oldRefs.isEmpty ? _cache.values : _oldRefs;

    for (final ref in toBeDisposed) {
      ref._dispose();
    }

    // Only reachable when the scope unmounts in the same frame in which an
    // override change evicted these refs, before the post-frame flush runs.
    // coverage:ignore-start
    for (final ref in _evictedRefs) {
      ref._dispose();
    }
    // coverage:ignore-end

    _cache.clear();
    _oldRefs.clear();
    _evictedRefs.clear();
    _pendingDisposals.clear();
    _autoDisposeBindings.clear();
    _listeningElements.clear();
    super.unmount();
  }
}
