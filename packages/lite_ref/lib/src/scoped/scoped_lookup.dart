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
  final creating = _creatingRefs.isEmpty ? null : _creatingRefs.last;

  final existing = element._cache[cacheKey];

  void bindIfNeeded(ScopedObject<dynamic> object) {
    if (!listen) return;

    // A lookup made from inside a factory records a dependency on the
    // factory's object instead of binding the consuming element.
    if (creating != null) {
      element._addObjectDependency(creating, object);
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

  final effective = element.scope.overrides?.lookup(ref) ?? ref;
  final object = create(element, effective);
  bindIfNeeded(object);
  element._cache[object._id] = object;
  return object._instance;
}
