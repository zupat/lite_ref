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
