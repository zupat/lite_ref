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
}
