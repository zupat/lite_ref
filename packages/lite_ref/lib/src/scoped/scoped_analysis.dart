part of 'scoped.dart';

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
