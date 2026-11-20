/// Orders [roots] and their transitive dependents so dependents come before
/// the dependencies they hold.
///
/// This is a pure graph traversal. It lives in its own internal library so it
/// can be tested without a widget tree; it is not exported by the package.
List<T> evictionOrder<T>(
  Iterable<T> roots,
  Iterable<T> Function(T node) dependentsOf,
) {
  final evicted = <T>[];
  final visited = Set<T>.identity();

  void collect(T node) {
    if (!visited.add(node)) return;
    for (final dependent in dependentsOf(node)) {
      collect(dependent);
    }
    evicted.add(node);
  }

  for (final root in roots) {
    collect(root);
  }

  return evicted;
}

/// Whether cache [key] belongs to the ref [id].
///
/// Cache keys are `id` for a scoped ref and `(id, family)` for a family ref.
/// The family argument may be `null`.
bool keyBelongsTo(Object key, Object id) {
  if (key == id) return true;
  return key is (Object, Object?) && key.$1 == id;
}

/// The result of deciding what an override change (or parent move)
/// invalidates.
///
/// Pure data: [toEvict] is ordered dependents-first, and [affectedScopes] is
/// `{owner} ∪ {ownerOf(node) for node in toEvict}`. The element applies it
/// without recomputing intent.
class EvictionPlan<TNode, TScope> {
  /// Creates a plan with the ordered nodes to evict and the owners to notify.
  const EvictionPlan({
    required this.toEvict,
    required this.affectedScopes,
  });

  /// Nodes to evict, dependents before their dependencies.
  final List<TNode> toEvict;

  /// Owners to notify: `{owner} ∪ owners(toEvict)`.
  final Set<TScope> affectedScopes;
}

/// Plans the eviction of [roots] and their transitive dependents.
EvictionPlan<TNode, TScope> planEviction<TNode, TScope>({
  required TScope owner,
  required Iterable<TNode> roots,
  required Iterable<TNode> Function(TNode node) dependentsOf,
  required TScope Function(TNode node) ownerOf,
}) {
  final toEvict = evictionOrder<TNode>(roots, dependentsOf);
  return EvictionPlan<TNode, TScope>(
    toEvict: toEvict,
    affectedScopes: <TScope>{
      owner,
      for (final node in toEvict) ownerOf(node),
    },
  );
}

/// Plans the eviction caused by an override change in one scope.
///
/// [keyMatches] matches a node against a bare ref id; [lookupDependentsOf]
/// returns the dependents registered for one id, and [allLookupDependents]
/// every registered dependent.
EvictionPlan<TNode, TScope> planOverrideChange<TNode, TScope>({
  required TScope owner,
  required Iterable<TNode> cached,
  required bool Function(TNode node, Object id) keyMatches,
  required Set<Object> changedIds,
  required Set<Object> overrideIds,
  required bool evictNonOverrides,
  required bool onlyOverridesChanged,
  required Iterable<TNode> Function(Object id) lookupDependentsOf,
  required Iterable<TNode> allLookupDependents,
  required Iterable<TNode> Function(TNode node) dependentsOf,
  required TScope Function(TNode node) ownerOf,
}) {
  final roots = <TNode>[
    for (final node in cached)
      if (changedIds.any((id) => keyMatches(node, id)) ||
          (evictNonOverrides && !overrideIds.any((id) => keyMatches(node, id))))
        node,
  ];

  // A changed lookup path also invalidates dependents even when the previous
  // dependency was cached in an ancestor rather than in this scope.
  for (final id in changedIds) {
    roots.addAll(lookupDependentsOf(id));
  }
  if (onlyOverridesChanged) {
    roots.addAll(allLookupDependents);
  }

  return planEviction<TNode, TScope>(
    owner: owner,
    roots: roots,
    dependentsOf: dependentsOf,
    ownerOf: ownerOf,
  );
}
