part of 'scoped.dart';

/// Resolves [ref] through the [LiteRefScope] found from [context].
///
/// [cacheKey] is `_id` for a [ScopedRef] and `(_id, family)` for a
/// [ScopedFamilyRef]. [lookupId] is always the bare ref id: dependency
/// tracking is keyed by ref identity, never by family.
///
/// [create] builds an object for the effective ref (the original ref or the
/// override that the serving scope provides).
T _resolveScoped<T>({
  required BuildContext context,
  required IScopedRef<T> ref,
  required Object lookupId,
  required Object cacheKey,
  required bool listen,
  required ScopedObject<T> Function(
    _RefScopeElement element,
    IScopedRef<dynamic> effective,
  ) create,
}) {
  final traversedScopes = <_RefScopeElement>[];
  final element = LiteRefScope._of(context, ref, traversed: traversedScopes);
  final creating = _creationContext();

  final existing = element._cache[cacheKey];

  void bindIfNeeded(ScopedObject<dynamic> object) {
    if (!listen) return;

    // A lookup made from inside a factory records a dependency on the
    // factory's object instead of binding the consuming element.
    if (creating != null) {
      element._addObjectDependency(creating, object);
      // _addObjectDependency says "I use this instance."
      // _addLookupDependency says "I didn't use an instance of yours, but I
      // resolved through you, so tell me (or evict me) if your overrides
      // change." It exists so a scope that gains/loses an override can
      // invalidate objects that were built against its ancestor.
      for (final traversed in traversedScopes) {
        traversed._addLookupDependency(creating, lookupId);
      }
      return;
    }

    // Scopes that were traversed but did not serve the ref must notify this
    // consumer when their overrides change (e.g. an `onlyOverrides` scope
    // that gains an override for this ref).
    for (final traversed in traversedScopes) {
      traversed._addDependent(context as Element);
    }

    element._bind(context as Element, object);
  }

  if (existing != null) {
    bindIfNeeded(existing);
    return existing._instance as T;
  }

  if (element._creatingKeys.contains(cacheKey)) {
    throw StateError(
      'Circular or re-entrant dependency detected while creating '
      '${ref.runtimeType}.',
    );
  }

  // Register element dependencies before invoking the factory so an invalid
  // listening lookup (e.g. from State.initState) fails before creating an
  // orphaned object and acquiring dependencies.
  if (listen && creating == null) {
    final consumer = context as Element;
    for (final traversed in traversedScopes) {
      traversed._addDependent(consumer);
    }
    element._addDependent(consumer);
  }

  final effective = element.scope.overrides?.lookup(ref) ?? ref;
  element._creatingKeys.add(cacheKey);
  final ScopedObject<T> object;
  try {
    object = create(element, effective);
  } finally {
    element._creatingKeys.remove(cacheKey);
  }
  bindIfNeeded(object);
  element._cache[object._id] = object;
  return object._instance;
}

/// The factory currently running on this synchronous call stack, if any.
///
/// A factory may resolve dependencies through any [BuildContext] it captured,
/// not only the `ctx` parameter, so the creation context follows the call
/// stack instead of a particular scope element.
_PendingScopedObject<dynamic>? _creationContext() {
  final creating = Zone.current[_creatingZoneKey];
  if (creating is _PendingScopedObject<dynamic> && creating._active) {
    return creating;
  }
  return null;
}
