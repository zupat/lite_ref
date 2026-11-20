import 'package:flutter_test/flutter_test.dart';
import 'package:lite_ref/src/scoped/eviction.dart';

void main() {
  test('orders dependents before their dependencies', () {
    final root = Object();
    final middle = Object();
    final leaf = Object();

    final dependents = <Object, List<Object>>{
      root: [middle],
      middle: [leaf],
    };

    final order = evictionOrder<Object>(
      [root],
      (node) => dependents[node] ?? const [],
    );

    expect(order, [leaf, middle, root]);
  });

  test('visits shared dependents once', () {
    final root = Object();
    final first = Object();
    final second = Object();
    final shared = Object();

    final dependents = <Object, List<Object>>{
      root: [first, second],
      first: [shared],
      second: [shared],
    };

    final order = evictionOrder<Object>(
      [root],
      (node) => dependents[node] ?? const [],
    );

    expect(order, [shared, first, second, root]);
    expect(order.toSet(), {shared, first, second, root});
  });

  test('terminates on cycles', () {
    final first = Object();
    final second = Object();

    final dependents = <Object, List<Object>>{
      first: [second],
      second: [first],
    };

    final order = evictionOrder<Object>(
      [first],
      (node) => dependents[node] ?? const [],
    );

    expect(order, [second, first]);
  });

  group('keyBelongsTo', () {
    test('matches a bare id and family keys', () {
      final id = Object();
      final family = Object();

      expect(keyBelongsTo(id, id), isTrue);
      expect(keyBelongsTo((id, family), id), isTrue);
      expect(keyBelongsTo((id, null), id), isTrue);
    });

    test('rejects non-matching keys', () {
      final id = Object();
      final family = Object();

      expect(keyBelongsTo(Object(), id), isFalse);
      expect(keyBelongsTo((Object(), family), id), isFalse);
    });
  });

  group('planOverrideChange', () {
    test('evicts cached nodes whose keys match a changed id', () {
      final id = Object();
      final family = Object();
      final single = Object();
      final familyNode = Object();
      final other = Object();
      final owner = Object();

      final keys = <Object, Object>{
        single: id,
        familyNode: (id, family),
        other: Object(),
      };

      final plan = planOverrideChange<Object, Object>(
        owner: owner,
        cached: [single, familyNode, other],
        keyMatches: (node, changed) => keyBelongsTo(keys[node]!, changed),
        changedIds: {id},
        overrideIds: const <Object>{},
        evictNonOverrides: false,
        onlyOverridesChanged: false,
        lookupDependentsOf: (changed) => const <Object>[],
        allLookupDependents: const <Object>[],
        dependentsOf: (node) => const <Object>[],
        ownerOf: (node) => owner,
      );

      expect(plan.toEvict, [single, familyNode]);
      expect(plan.affectedScopes, {owner});
    });

    test('evicts non-overridden nodes when switching to onlyOverrides', () {
      final overriddenId = Object();
      final otherId = Object();
      final overridden = Object();
      final other = Object();
      final owner = Object();

      final keys = <Object, Object>{
        overridden: overriddenId,
        other: otherId,
      };

      final plan = planOverrideChange<Object, Object>(
        owner: owner,
        cached: [overridden, other],
        keyMatches: (node, id) => keyBelongsTo(keys[node]!, id),
        changedIds: const <Object>{},
        overrideIds: {overriddenId},
        evictNonOverrides: true,
        onlyOverridesChanged: false,
        lookupDependentsOf: (id) => const <Object>[],
        allLookupDependents: const <Object>[],
        dependentsOf: (node) => const <Object>[],
        ownerOf: (node) => owner,
      );

      expect(plan.toEvict, [other]);
    });

    test('adds lookup dependents of changed ids', () {
      final id = Object();
      final dependent = Object();
      final owner = Object();
      final dependentOwner = Object();

      final plan = planOverrideChange<Object, Object>(
        owner: owner,
        cached: const <Object>[],
        keyMatches: (node, changed) => false,
        changedIds: {id},
        overrideIds: const <Object>{},
        evictNonOverrides: false,
        onlyOverridesChanged: false,
        lookupDependentsOf: (changed) =>
            changed == id ? [dependent] : const <Object>[],
        allLookupDependents: const <Object>[],
        dependentsOf: (node) => const <Object>[],
        ownerOf: (node) => dependentOwner,
      );

      expect(plan.toEvict, [dependent]);
      expect(plan.affectedScopes, {owner, dependentOwner});
    });

    test('adds every lookup dependent when onlyOverrides toggles', () {
      final first = Object();
      final second = Object();
      final owner = Object();

      final plan = planOverrideChange<Object, Object>(
        owner: owner,
        cached: const <Object>[],
        keyMatches: (node, id) => false,
        changedIds: const <Object>{},
        overrideIds: const <Object>{},
        evictNonOverrides: false,
        onlyOverridesChanged: true,
        lookupDependentsOf: (id) => const <Object>[],
        allLookupDependents: [first, second],
        dependentsOf: (node) => const <Object>[],
        ownerOf: (node) => owner,
      );

      expect(plan.toEvict, [first, second]);
    });
  });

  group('planEviction', () {
    test('orders dependents first and collects every owner', () {
      final root = Object();
      final dependent = Object();
      final owner = Object();
      final dependentOwner = Object();

      final plan = planEviction<Object, Object>(
        owner: owner,
        roots: [root],
        dependentsOf: (node) =>
            identical(node, root) ? [dependent] : const <Object>[],
        ownerOf: (node) => identical(node, dependent) ? dependentOwner : owner,
      );

      expect(plan.toEvict, [dependent, root]);
      expect(plan.affectedScopes, {owner, dependentOwner});
    });

    test('includes the owner even when nothing is evicted', () {
      final owner = Object();

      final plan = planEviction<Object, Object>(
        owner: owner,
        roots: const <Object>[],
        dependentsOf: (node) => const <Object>[],
        ownerOf: (node) => Object(),
      );

      expect(plan.toEvict, isEmpty);
      expect(plan.affectedScopes, {owner});
    });
  });
}
