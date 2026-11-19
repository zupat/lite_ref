part of 'scoped.dart';

/// The refs invalidated by an override change in one scope.
///
/// This is a pure decision: it only reads cache keys, override ids, and lookup
/// registrations. Notification and disposal effects live in the element.
List<ScopedObject<dynamic>> _rootsForOverrideChange({
  required Iterable<ScopedObject<dynamic>> cached,
  required Set<Object> changedIds,
  required Set<Object> overrideIds,
  required bool evictNonOverrides,
  required Map<Object, Set<_Dependent>> lookupDependents,
  required bool onlyOverridesChanged,
}) {
  final roots = cached.where((ref) {
    if (changedIds.any((id) => _keyBelongsTo(ref._id, id))) return true;
    return evictNonOverrides &&
        !overrideIds.any((id) => _keyBelongsTo(ref._id, id));
  }).toList();

  // A changed lookup path also invalidates dependents even when the previous
  // dependency was cached in an ancestor rather than in this scope.
  for (final id in changedIds) {
    final dependents = lookupDependents[id];
    if (dependents != null) {
      roots.addAll(dependents.whereType<ScopedObject<dynamic>>());
    }
  }
  if (onlyOverridesChanged) {
    roots.addAll(
      lookupDependents.values
          .expand((refs) => refs)
          .whereType<ScopedObject<dynamic>>(),
    );
  }

  return roots;
}

/// [roots] and their dependents, ordered so dependents come before the
/// dependencies they hold.
///
/// Pending objects are not included: they exist only while a factory runs, and
/// invalidation cannot run during a build.
List<ScopedObject<dynamic>> _evictionOrder(
  Iterable<ScopedObject<dynamic>> roots,
) {
  return evictionOrder<ScopedObject<dynamic>>(
    roots,
    (ref) => ref._dependents.whereType<ScopedObject<dynamic>>(),
  );
}

/// IDs of the refs whose resolved override changed.
///
/// Overrides are compared by identity: two overrides for the same ref are
/// equal (`==`) by design, so only a new instance means a new override.
Set<Object> _changedOverrideIds(
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

Object _idOf(IScopedRef<dynamic> ref) => switch (ref) {
      ScopedRef() => ref._id,
      ScopedFamilyRef() => ref._id,
    };

/// Cache keys are `_id` for a [ScopedRef] and `(_id, family)` for a
/// [ScopedFamilyRef]. The family argument may be `null`.
bool _keyBelongsTo(Object key, Object id) {
  if (key == id) return true;
  return key is (Object, Object?) && key.$1 == id;
}
