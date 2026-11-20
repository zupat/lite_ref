import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lite_ref/lite_ref.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  test('overriden instance should be equal to main', () {
    final countRef = Ref.scoped((ctx) => 1);
    final countRefClone = countRef.overrideWith((ctx) => 2);

    expect(countRef, countRefClone);

    final hashSet = <Object>{}..add(countRef);

    expect(hashSet.contains(countRefClone), true);
  });

  test('ScopedObject exposes its configured lifetime', () {
    final cached = ScopedObject<int>(id: Object(), instance: 1);
    final retained = ScopedObject<int>(
      id: Object(),
      instance: 2,
      autoDispose: false,
    );

    expect(cached.autoDispose, isTrue);
    expect(retained.autoDispose, isFalse);
  });

  testWidgets('should cache values', (tester) async {
    var ran = 0;
    final countRef = Ref.scoped((ctx) => ++ran);

    await tester.pumpWidget(
      MaterialApp(
        home: LiteRefScope(
          child: Builder(
            builder: (context) {
              final val = countRef(context);
              final val2 = countRef(context);
              expect(val, 1);
              expect(val2, 1);
              return Text('$val $val2');
            },
          ),
        ),
      ),
    );

    expect(ran, 1);

    final txt = find.text('1 1');

    expect(txt, findsOneWidget);
  });

  testWidgets(
    'should throw when there is no root LiteRefScope',
    (tester) async {
      final countRef = Ref.scoped((ctx) => 1);

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              // This should trigger the error
              expect(() => countRef(context), throwsA(isA<AssertionError>()));
              return const SizedBox.shrink();
            },
          ),
        ),
      );
    },
  );

  testWidgets('overriden instance should have different value', (tester) async {
    final countRef = Ref.scoped((ctx) => 1);
    var val = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: LiteRefScope(
          child: Builder(
            builder: (context) {
              val = countRef(context);
              expect(val, 1);
              return LiteRefScope(
                overrides: {
                  countRef.overrideWith((ctx) => 2),
                },
                child: Column(
                  children: [
                    Text('$val'),
                    Builder(
                      builder: (context) {
                        val = countRef(context);
                        expect(val, 2);
                        return Text('$val');
                      },
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );

    expect(find.text('1'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
  });

  testWidgets('should be able to use other refs', (tester) async {
    final ageRef = Ref.scoped((ctx) => 20);
    final nameRef = Ref.scoped((ctx) => 'John');

    final bioRef = Ref.scoped(
      (ctx) => '${nameRef(ctx)} is ${ageRef(ctx)} years old',
    );

    const correctText = 'John is 20 years old';

    await tester.pumpWidget(
      MaterialApp(
        home: LiteRefScope(
          child: Builder(
            builder: (context) {
              final val = bioRef(context);
              expect(val, correctText);
              return Text(val);
            },
          ),
        ),
      ),
    );

    expect(find.text(correctText), findsOneWidget);
  });

  testWidgets('should dispose ref when scope is unmounted', (tester) async {
    final disposed = <int>[];
    final countRef = Ref.scoped((ctx) => 1, dispose: disposed.add);

    await tester.pumpWidget(
      MaterialApp(
        home: LiteRefScope(
          child: Builder(
            builder: (context) {
              final val = countRef(context);
              expect(val, 1);
              return LiteRefScope(
                overrides: {
                  countRef.overrideWith((ctx) => 2),
                },
                child: Builder(
                  builder: (context) {
                    final val = countRef(context);
                    expect(val, 2);
                    return Text('$val');
                  },
                ),
              );
            },
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('2'), findsOneWidget);

    expect(disposed, isEmpty);

    await tester.pumpWidget(
      MaterialApp(
        home: LiteRefScope(
          child: Builder(
            builder: (context) {
              final val = countRef(context);
              expect(val, 1);
              return Text('$val');
            },
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('1'), findsOneWidget);
    expect(disposed, [2]); // overriden instance should be disposed

    await tester.pumpWidget(
      const MaterialApp(
        home: Text(''),
      ),
    );

    await tester.pumpAndSettle();

    expect(disposed, [2, 1]);
  });

  testWidgets(
      'should dispose ref when scope is unmounted when autodispose=false',
      (tester) async {
    final disposed = <int>[];
    final countRef = Ref.scoped(
      (ctx) => 1,
      dispose: disposed.add,
      autoDispose: false,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: LiteRefScope(
          child: Builder(
            builder: (context) {
              final val = countRef(context);
              expect(val, 1);
              return LiteRefScope(
                overrides: {
                  countRef.overrideWith((ctx) => 2),
                },
                child: Builder(
                  builder: (context) {
                    final val = countRef(context);
                    expect(val, 2);
                    return Text('$val');
                  },
                ),
              );
            },
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('2'), findsOneWidget);

    expect(disposed, isEmpty);

    await tester.pumpWidget(
      MaterialApp(
        home: LiteRefScope(
          child: Builder(
            builder: (context) {
              final val = countRef(context);
              expect(val, 1);
              return Text('$val');
            },
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('1'), findsOneWidget);
    expect(disposed, [2]); // overriden instance should be disposed

    await tester.pumpWidget(
      const MaterialApp(
        home: Text(''),
      ),
    );

    await tester.pumpAndSettle();

    expect(disposed, [2, 1]);
  });

  testWidgets('should dispose when only child is unmounted', (tester) async {
    final disposed = <int>[];
    final countRef = Ref.scoped((ctx) => 1, dispose: disposed.add);
    final show = ValueNotifier(true);

    await tester.pumpWidget(
      MaterialApp(
        home: LiteRefScope(
          child: ListenableBuilder(
            listenable: show,
            builder: (context, snapshot) {
              if (!show.value) return const Text('hidden');
              return Builder(
                builder: (context) {
                  final val = countRef(context);
                  expect(val, 1);
                  return Text('$val');
                },
              );
            },
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('1'), findsOneWidget);

    expect(disposed, isEmpty);

    show.value = false;

    await tester.pumpAndSettle();

    expect(find.text('hidden'), findsOneWidget);

    expect(disposed, [1]);
  });

  testWidgets('should dispose when all children are unmounted', (tester) async {
    final disposed = <int>[];
    final countRef = Ref.scoped((ctx) => 1, dispose: disposed.add);
    final amount = ValueNotifier(3);

    await tester.pumpWidget(
      MaterialApp(
        home: LiteRefScope(
          child: ListenableBuilder(
            listenable: amount,
            builder: (context, snapshot) {
              return Column(
                children: [
                  const SizedBox.shrink(),
                  for (var i = 0; i < amount.value; i++)
                    Builder(
                      builder: (context) {
                        final val = countRef(context);
                        expect(val, 1);
                        return Text('$val');
                      },
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('1'), findsExactly(amount.value));

    expect(disposed, isEmpty);

    amount.value = 2;

    await tester.pumpAndSettle();

    expect(find.text('1'), findsExactly(amount.value));

    expect(disposed, isEmpty); // still has listeners

    amount.value = 0;

    await tester.pumpAndSettle();

    expect(find.text('1'), findsNothing);

    expect(disposed, [1]); // dispose when all children are unmounted
  });

  testWidgets(
    'should dispose Disposable when no dispose function is supplied',
    (tester) async {
      final resource = _Resource();
      final countRef = Ref.scoped((ctx) => resource);
      final show = ValueNotifier(true);

      await tester.pumpWidget(
        MaterialApp(
          home: LiteRefScope(
            child: ListenableBuilder(
              listenable: show,
              builder: (context, snapshot) {
                if (!show.value) return const Text('hidden');
                return Builder(
                  builder: (context) {
                    final val = countRef(context);
                    return Text('${val.disposed}');
                  },
                );
              },
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('false'), findsOneWidget);

      expect(resource.disposed, false);

      show.value = false;

      await tester.pumpAndSettle();

      expect(find.text('hidden'), findsOneWidget);

      expect(resource.disposed, true);
    },
  );

  testWidgets(
    'should dispose ValueNotifier when no dispose function is supplied',
    (tester) async {
      final vn = ValueNotifier(1);
      final countRef = Ref.scoped((ctx) => vn);
      final show = ValueNotifier(true);

      await tester.pumpWidget(
        MaterialApp(
          home: LiteRefScope(
            child: ListenableBuilder(
              listenable: show,
              builder: (context, snapshot) {
                if (!show.value) return const Text('hidden');
                return Builder(
                  builder: (context) {
                    final val = countRef(context);
                    return Text('${val.value}');
                  },
                );
              },
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('1'), findsOneWidget);

      vn.addListener(() {}); // not disposed. ie: should not throw

      show.value = false;

      await tester.pumpAndSettle();

      expect(find.text('hidden'), findsOneWidget);

      // should throw when disposed
      expect(() => vn.addListener(() {}), throwsFlutterError);
    },
  );

  testWidgets(
    'should dispose correct instance when overriden',
    (tester) async {
      final resource = _Resource();
      final resource2 = _Resource();
      final countRef = Ref.scoped((ctx) => resource);
      final countRef2 = countRef.overrideWith((_) => resource2);
      final show = ValueNotifier(true);

      await tester.pumpWidget(
        MaterialApp(
          home: LiteRefScope(
            child: ListenableBuilder(
              listenable: show,
              builder: (context, snapshot) {
                return LiteRefScope(
                  overrides: {countRef2},
                  child: !show.value
                      ? const Text('hidden')
                      : Column(
                          children: [
                            Builder(
                              builder: (context) {
                                final val = countRef(context);
                                return Text('${val.disposed}');
                              },
                            ),
                            Builder(
                              builder: (context) {
                                final val = countRef(context);
                                return Text('${val.disposed}');
                              },
                            ),
                          ],
                        ),
                );
              },
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('false'), findsExactly(2));

      expect(resource.disposed, false);
      expect(resource2.disposed, false);

      show.value = false;

      await tester.pumpAndSettle();

      expect(find.text('hidden'), findsOneWidget);

      expect(resource.disposed, false);
      expect(resource2.disposed, true);
    },
  );

  testWidgets(
    'should get correct value when GlobalKey changes '
    'causes it to move its position in the tree',
    (tester) async {
      final current = ValueNotifier(1);
      final countRef = Ref.scoped((ctx) => 0);

      final child = Builder(
        key: GlobalKey(),
        builder: (context) {
          final val = countRef.of(context);
          return Text('got: $val');
        },
      );

      await tester.pumpWidget(
        MaterialApp(
          home: LiteRefScope(
            child: Column(
              children: [
                ListenableBuilder(
                  listenable: current,
                  builder: (context, snapshot) {
                    if (current.value != 1) {
                      return const SizedBox.shrink();
                    }
                    return LiteRefScope(
                      overrides: {
                        countRef.overrideWith((_) => 1),
                      },
                      child: Builder(
                        builder: (context) => child,
                      ),
                    );
                  },
                ),
                ListenableBuilder(
                  listenable: current,
                  builder: (context, snapshot) {
                    if (current.value != 2) {
                      return const SizedBox.shrink();
                    }
                    return LiteRefScope(
                      overrides: {
                        countRef.overrideWith((_) => 2),
                      },
                      child: Builder(
                        builder: (context) => child,
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      );

      expect(find.text('got: 1'), findsOneWidget);
      current.value = 2;
      await tester.pumpAndSettle();
      expect(find.text('got: 2'), findsOneWidget);
    },
  );

  testWidgets(
    'should return true if the ScopedRef is '
    'initialized in the current LiteRefScope',
    (tester) async {
      final countRef = Ref.scoped((ctx) => 1);

      await tester.pumpWidget(
        MaterialApp(
          home: LiteRefScope(
            child: Builder(
              builder: (context) {
                final initialized = countRef.exists(context);
                expect(initialized, false);

                final val = countRef.of(context);
                expect(val, 1);

                final initialized2 = countRef.exists(context);
                expect(initialized2, true);

                return LiteRefScope(
                  overrides: {
                    countRef.overrideWith((ctx) => 2),
                  },
                  child: Builder(
                    builder: (context) {
                      final initialized = countRef.exists(context);
                      expect(initialized, false);

                      final val = countRef.of(context);
                      expect(val, 2);

                      final initialized2 = countRef.exists(context);
                      expect(initialized2, true);

                      return Text('$val');
                    },
                  ),
                );
              },
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('2'), findsOneWidget);
    },
  );

  testWidgets(
    'should dispose when all children are unmounted and it is read in parent',
    (tester) async {
      final disposed = <int>[];
      final countRef = Ref.scoped((ctx) => 1, dispose: disposed.add);
      final amount = ValueNotifier(3);

      await tester.pumpWidget(
        MaterialApp(
          home: LiteRefScope(
            child: Column(
              children: [
                Builder(
                  builder: (context) {
                    return Text('read ${countRef.read(context)}');
                  },
                ),
                ListenableBuilder(
                  listenable: amount,
                  builder: (context, snapshot) {
                    return Column(
                      children: [
                        const SizedBox.shrink(),
                        for (var i = 0; i < amount.value; i++)
                          Builder(
                            builder: (context) {
                              final val = countRef(context);
                              expect(val, 1);
                              return Text('$val');
                            },
                          ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('1'), findsExactly(amount.value));
      expect(find.text('read 1'), findsOneWidget);

      expect(disposed, isEmpty);

      amount.value = 2;

      await tester.pumpAndSettle();

      expect(find.text('1'), findsExactly(amount.value));

      expect(disposed, isEmpty); // still has listeners

      amount.value = 0;

      await tester.pumpAndSettle();

      expect(find.text('1'), findsNothing);

      expect(disposed, [1]); // dispose when all children are unmounted
      expect(find.text('read 1'), findsOneWidget);
    },
  );

  testWidgets(
    'should NOT dispose when scope is unmounted and only access was a "read"',
    (tester) async {
      final disposed = <int>[];
      final countRef = Ref.scoped((ctx) => 1, dispose: disposed.add);
      final show = ValueNotifier(true);
      await tester.pumpWidget(
        MaterialApp(
          home: LiteRefScope(
            child: ValueListenableBuilder(
              valueListenable: show,
              builder: (__, value, _) {
                if (!value) return const SizedBox.shrink();
                return Builder(
                  builder: (context) {
                    final val = countRef.read(context);
                    expect(val, 1);
                    return Text('$val');
                  },
                );
              },
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('1'), findsOneWidget);
      expect(disposed, isEmpty); // overriden instance should be disposed

      show.value = false;

      await tester.pumpAndSettle();

      expect(disposed, isEmpty);
    },
  );

  testWidgets(
    'should throw when the scope is marked as onlyOverrides',
    (tester) async {
      final countRef = Ref.scoped((ctx) => 1);

      await tester.pumpWidget(
        MaterialApp(
          home: LiteRefScope(
            onlyOverrides: true,
            child: Builder(
              builder: (context) {
                late final val = countRef(context);
                expect(() => val, throwsException);
                return const Text('1');
              },
            ),
          ),
        ),
      );

      expect(find.text('1'), findsOneWidget);
    },
  );

  testWidgets('should fetch from the closest scope', (tester) async {
    final resourceRef = Ref.scoped((ctx) => _Resource());

    await tester.pumpWidget(
      MaterialApp(
        home: LiteRefScope(
          child: Builder(
            builder: (context) {
              final val = resourceRef(context);
              expect(val.disposed, false);
              val.disposed = true;
              return LiteRefScope(
                onlyOverrides: true,
                overrides: {resourceRef.overrideWith((ctx) => _Resource())},
                child: Builder(
                  builder: (context) {
                    final val2 = resourceRef(context);
                    expect(val2.disposed, false);
                    return Text('${val2.disposed}');
                  },
                ),
              );
            },
          ),
        ),
      ),
    );

    expect(find.text('false'), findsOneWidget);
  });

  testWidgets('should fetch from the closest scope/2 depth', (tester) async {
    final resourceRef = Ref.scoped((ctx) => _Resource());

    await tester.pumpWidget(
      MaterialApp(
        home: LiteRefScope(
          child: Builder(
            builder: (context) {
              final val = resourceRef(context);
              expect(val.disposed, false);
              val.disposed = true;
              return LiteRefScope(
                onlyOverrides: true,
                overrides: {resourceRef.overrideWith((ctx) => _Resource())},
                child: Builder(
                  builder: (context) {
                    return LiteRefScope(
                      onlyOverrides: true,
                      child: Builder(
                        builder: (context) {
                          final val2 = resourceRef(context);
                          expect(val2.disposed, false);
                          return Text('${val2.disposed}');
                        },
                      ),
                    );
                  },
                ),
              );
            },
          ),
        ),
      ),
    );

    expect(find.text('false'), findsOneWidget);
  });

  testWidgets('should fetch from the closest scope/3 depth', (tester) async {
    final resourceRef = Ref.scoped((ctx) => _Resource());

    await tester.pumpWidget(
      MaterialApp(
        home: LiteRefScope(
          child: Builder(
            builder: (context) {
              final val = resourceRef(context);
              expect(val.disposed, false);
              val.disposed = true;
              return LiteRefScope(
                onlyOverrides: true,
                overrides: {resourceRef.overrideWith((ctx) => _Resource())},
                child: Builder(
                  builder: (context) {
                    return LiteRefScope(
                      onlyOverrides: true,
                      child: Builder(
                        builder: (context) {
                          return LiteRefScope(
                            onlyOverrides: true,
                            child: Builder(
                              builder: (context) {
                                final val2 = resourceRef(context);
                                expect(val2.disposed, false);
                                return Text('${val2.disposed}');
                              },
                            ),
                          );
                        },
                      ),
                    );
                  },
                ),
              );
            },
          ),
        ),
      ),
    );

    expect(find.text('false'), findsOneWidget);
  });

  testWidgets(
    'should fetch from the parent scope when the '
    'closest scope is marked as onlyOverrides',
    (tester) async {
      final resourceRef = Ref.scoped((ctx) => _Resource());

      await tester.pumpWidget(
        MaterialApp(
          home: LiteRefScope(
            child: Builder(
              builder: (context) {
                final val = resourceRef(context);
                expect(val.disposed, false);
                val.disposed = true;
                return LiteRefScope(
                  onlyOverrides: true,
                  child: Builder(
                    builder: (context) {
                      final val = resourceRef(context);
                      expect(val.disposed, true);
                      return Text('${val.disposed}');
                    },
                  ),
                );
              },
            ),
          ),
        ),
      );

      expect(find.text('true'), findsOneWidget);
    },
  );

  testWidgets('should dispose correct ref when scope has UniqueKey',
      (tester) async {
    final disposed = <int>[];
    final countRef = Ref.scoped(
      (ctx) => 1,
      dispose: disposed.add,
    );

    final inc = ValueNotifier(1);

    await tester.pumpWidget(
      MaterialApp(
        home: LiteRefScope(
          child: ListenableBuilder(
            listenable: inc,
            builder: (context, _) {
              return Container(
                key: UniqueKey(),
                child: LiteRefScope(
                  overrides: {
                    countRef.overrideWith((ctx) => 1 + inc.value),
                  },
                  child: Builder(
                    builder: (context) {
                      final val = countRef(context);
                      return Text('$val');
                    },
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('2'), findsOneWidget);

    expect(disposed, isEmpty);

    inc.value = 2;

    await tester.pumpAndSettle();

    expect(find.text('3'), findsOneWidget);

    expect(disposed, [2]);

    inc.value = 3;

    await tester.pumpAndSettle();

    expect(find.text('4'), findsOneWidget);

    expect(disposed, [2, 3]);
  });

  testWidgets(
    'should release the bindings of a widget moved out of a scope '
    'with a GlobalKey',
    (tester) async {
      final disposed = <int>[];
      final current = ValueNotifier(1);
      final countRef = Ref.scoped((ctx) => 0, dispose: disposed.add);
      final child = Builder(
        key: GlobalKey(),
        builder: (context) => Text('got: ${countRef(context)}'),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: LiteRefScope(
            child: ListenableBuilder(
              listenable: current,
              builder: (context, _) {
                return Column(
                  children: [
                    LiteRefScope(
                      overrides: {
                        countRef.overrideWith((_) => 1),
                      },
                      child: current.value == 1
                          ? Builder(builder: (context) => child)
                          : const SizedBox.shrink(),
                    ),
                    if (current.value == 2)
                      Builder(builder: (context) => child),
                  ],
                );
              },
            ),
          ),
        ),
      );

      expect(find.text('got: 1'), findsOneWidget);
      expect(disposed, isEmpty);

      current.value = 2;
      await tester.pumpAndSettle();

      expect(find.text('got: 0'), findsOneWidget);
      // The inner scope is still mounted but lost its last consumer.
      expect(disposed, [1]);
    },
  );

  testWidgets('should recreate the instance when an override changes',
      (tester) async {
    final disposed = <int>[];
    final current = ValueNotifier(0);
    final countRef = Ref.scoped((ctx) => -1, dispose: disposed.add);

    await tester.pumpWidget(
      MaterialApp(
        home: LiteRefScope(
          child: ListenableBuilder(
            listenable: current,
            builder: (context, _) {
              return LiteRefScope(
                overrides: {
                  countRef.overrideWith((_) => current.value),
                },
                child: Builder(
                  builder: (context) => Text('${countRef(context)}'),
                ),
              );
            },
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('0'), findsOneWidget);
    expect(disposed, isEmpty);

    current.value = 1;
    await tester.pumpAndSettle();

    expect(find.text('1'), findsOneWidget);
    expect(disposed, [0]);
  });

  testWidgets(
    'should notify consumers of autoDispose=false refs '
    'when the override changes',
    (tester) async {
      final current = ValueNotifier('a');
      final nameRef = Ref.scoped((ctx) => 'none', autoDispose: false);

      await tester.pumpWidget(
        MaterialApp(
          home: LiteRefScope(
            child: ListenableBuilder(
              listenable: current,
              builder: (context, _) {
                return LiteRefScope(
                  overrides: {
                    nameRef.overrideWith((_) => current.value),
                  },
                  child: Builder(
                    builder: (context) => Text(nameRef(context)),
                  ),
                );
              },
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('a'), findsOneWidget);

      current.value = 'b';
      await tester.pumpAndSettle();

      expect(find.text('b'), findsOneWidget);
    },
  );

  testWidgets(
    'should auto-dispose an override that enables autoDispose',
    (tester) async {
      final disposed = <int>[];
      final show = ValueNotifier(true);
      final countRef = Ref.scoped(
        (ctx) => 0,
        dispose: disposed.add,
        autoDispose: false,
      );
      final override = countRef.overrideWith((_) => 1);

      await tester.pumpWidget(
        MaterialApp(
          home: LiteRefScope(
            child: Builder(
              builder: (context) {
                return LiteRefScope(
                  overrides: {override},
                  child: ListenableBuilder(
                    listenable: show,
                    builder: (context, _) => show.value
                        ? Builder(
                            builder: (context) => Text('${countRef(context)}'),
                          )
                        : const Text('hidden'),
                  ),
                );
              },
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('1'), findsOneWidget);
      expect(disposed, isEmpty);

      show.value = false;
      await tester.pumpAndSettle();

      expect(find.text('hidden'), findsOneWidget);
      expect(disposed, [1]);
    },
  );

  testWidgets(
    'should not auto-dispose an override that disables autoDispose',
    (tester) async {
      final disposed = <int>[];
      final show = ValueNotifier(true);
      final countRef = Ref.scoped((ctx) => 0, dispose: disposed.add);
      final override = countRef.overrideWith((_) => 1, autoDispose: false);

      await tester.pumpWidget(
        MaterialApp(
          home: LiteRefScope(
            child: Builder(
              builder: (context) {
                return LiteRefScope(
                  overrides: {override},
                  child: ListenableBuilder(
                    listenable: show,
                    builder: (context, _) => show.value
                        ? Builder(
                            builder: (context) => Text('${countRef(context)}'),
                          )
                        : const Text('hidden'),
                  ),
                );
              },
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('1'), findsOneWidget);

      show.value = false;
      await tester.pumpAndSettle();

      expect(find.text('hidden'), findsOneWidget);
      expect(disposed, isEmpty);
    },
  );

  testWidgets(
    'should resolve from the new parent when a scope is moved '
    'with a GlobalKey',
    (tester) async {
      final current = ValueNotifier(1);
      final countRef = Ref.scoped((ctx) => 0);

      final movedScope = LiteRefScope(
        key: GlobalKey(),
        onlyOverrides: true,
        child: Builder(
          builder: (context) => Text('got: ${countRef(context)}'),
        ),
      );

      Widget slot(int value) {
        return LiteRefScope(
          overrides: {
            countRef.overrideWith((_) => value),
          },
          child: movedScope,
        );
      }

      await tester.pumpWidget(
        MaterialApp(
          home: LiteRefScope(
            child: ListenableBuilder(
              listenable: current,
              builder: (context, _) {
                return Column(
                  children: [
                    if (current.value == 1)
                      slot(1)
                    else
                      const SizedBox.shrink(),
                    if (current.value == 2) slot(2),
                  ],
                );
              },
            ),
          ),
        ),
      );

      expect(find.text('got: 1'), findsOneWidget);

      current.value = 2;
      await tester.pumpAndSettle();

      expect(find.text('got: 2'), findsOneWidget);
    },
  );

  testWidgets(
    'should notify consumers when an onlyOverrides scope gains an override',
    (tester) async {
      final current = ValueNotifier(0);
      final countRef = Ref.scoped((ctx) => 0);

      // Kept as a constant instance so it only rebuilds when notified.
      final consumer = Builder(
        builder: (context) => Text('got: ${countRef(context)}'),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: LiteRefScope(
            overrides: {
              countRef.overrideWith((_) => 1),
            },
            child: ListenableBuilder(
              listenable: current,
              builder: (context, _) {
                return LiteRefScope(
                  onlyOverrides: true,
                  overrides: current.value == 0
                      ? null
                      : {countRef.overrideWith((_) => 2)},
                  child: consumer,
                );
              },
            ),
          ),
        ),
      );

      expect(find.text('got: 1'), findsOneWidget);

      current.value = 1;
      await tester.pumpAndSettle();

      expect(find.text('got: 2'), findsOneWidget);
    },
  );

  testWidgets(
    'should recreate a family instance with a null family '
    'when the override changes',
    (tester) async {
      final disposed = <int>[];
      final current = ValueNotifier(0);
      final countRef = Ref.scopedFamily<int, String?>(
        (ctx, family) => -1,
        dispose: disposed.add,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: LiteRefScope(
            child: ListenableBuilder(
              listenable: current,
              builder: (context, _) {
                return LiteRefScope(
                  overrides: {
                    countRef.overrideWith((_, family) => current.value),
                  },
                  child: Builder(
                    builder: (context) => Text('${countRef(context, null)}'),
                  ),
                );
              },
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('0'), findsOneWidget);

      current.value = 1;
      await tester.pumpAndSettle();

      expect(find.text('1'), findsOneWidget);
      expect(disposed, [0]);
    },
  );

  testWidgets(
    'should dispose the old instance when a mounted consumer switches '
    'to an override added to an onlyOverrides scope',
    (tester) async {
      final disposed = <int>[];
      final current = ValueNotifier(0);
      final countRef = Ref.scoped((ctx) => -1, dispose: disposed.add);

      // Kept as a constant instance so it only rebuilds when notified and
      // stays mounted across the override change.
      final consumer = Builder(
        builder: (context) => Text('got: ${countRef(context)}'),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: LiteRefScope(
            overrides: {
              countRef.overrideWith((_) => 1),
            },
            child: ListenableBuilder(
              listenable: current,
              builder: (context, _) {
                return LiteRefScope(
                  onlyOverrides: true,
                  overrides: current.value == 0
                      ? null
                      : {countRef.overrideWith((_) => 2)},
                  child: consumer,
                );
              },
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('got: 1'), findsOneWidget);
      expect(disposed, isEmpty);

      current.value = 1;
      await tester.pumpAndSettle();

      expect(find.text('got: 2'), findsOneWidget);
      // The consumer never unmounted, yet its old instance is gone.
      expect(disposed, [1]);

      // Disposing the remaining instance on unmount must not repeat [1].
      await tester.pumpWidget(const MaterialApp(home: Text('')));
      await tester.pumpAndSettle();

      expect(disposed, [1, 2]);
    },
  );

  testWidgets('should re-resolve when onlyOverrides is toggled',
      (tester) async {
    final disposed = <int>[];
    final current = ValueNotifier(false);
    final countRef = Ref.scoped((ctx) => 0, dispose: disposed.add);

    // Kept as a constant instance so it only rebuilds when notified.
    final consumer = Builder(
      builder: (context) => Text('got: ${countRef(context)}'),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: LiteRefScope(
          overrides: {
            countRef.overrideWith((_) => 1),
          },
          child: ListenableBuilder(
            listenable: current,
            builder: (context, _) {
              return LiteRefScope(
                onlyOverrides: current.value,
                child: consumer,
              );
            },
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('got: 0'), findsOneWidget);
    expect(disposed, isEmpty);

    current.value = true;
    await tester.pumpAndSettle();

    // The inner scope no longer serves the ref, so the consumer must fall
    // back to the parent override even though the overrides set is unchanged.
    expect(find.text('got: 1'), findsOneWidget);
    expect(disposed, [0]);
  });

  testWidgets(
    'should release the binding when an override disables autoDispose',
    (tester) async {
      final disposed = <int>[];
      final current = ValueNotifier(0);
      final countRef = Ref.scoped((ctx) => 0, dispose: disposed.add);

      // Kept as a constant instance so it only rebuilds when notified.
      final consumer = Builder(
        builder: (context) => Text('got: ${countRef(context)}'),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: LiteRefScope(
            child: ListenableBuilder(
              listenable: current,
              builder: (context, _) {
                return LiteRefScope(
                  onlyOverrides: true,
                  overrides: current.value == 0
                      ? null
                      : {
                          countRef.overrideWith(
                            (_) => 1,
                            autoDispose: false,
                          ),
                        },
                  child: consumer,
                );
              },
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('got: 0'), findsOneWidget);
      expect(disposed, isEmpty);

      current.value = 1;
      await tester.pumpAndSettle();

      expect(find.text('got: 1'), findsOneWidget);
      // The old auto-dispose binding is released even though the replacement
      // opts out of auto-disposal.
      expect(disposed, [0]);

      // Disabling auto-disposal only keeps it alive with zero listeners. The
      // scope still owns the override and disposes it on unmount.
      await tester.pumpWidget(const MaterialApp(home: Text('')));
      await tester.pumpAndSettle();

      expect(disposed, [0, 1]);
    },
  );

  group('scoped lifecycle regressions', () {
    testWidgets(
      'dependencies use the owning scope and outlive the first consumer',
      (tester) async {
        final rootResource = _Resource();
        final childResource = _Resource();
        final resourceRef = Ref.scoped((_) => rootResource);
        final dependentRef = Ref.scoped(
          (ctx) => _Dependent(resourceRef(ctx)),
        );
        final showChild = ValueNotifier(true);
        late _Dependent firstRequest;
        late _Dependent siblingRequest;

        await tester.pumpWidget(
          MaterialApp(
            home: LiteRefScope(
              child: Column(
                children: [
                  ListenableBuilder(
                    listenable: showChild,
                    builder: (context, _) {
                      if (!showChild.value) return const SizedBox.shrink();
                      return LiteRefScope(
                        onlyOverrides: true,
                        overrides: {
                          resourceRef.overrideWithValue(childResource),
                        },
                        child: Builder(
                          builder: (context) {
                            firstRequest = dependentRef(context);
                            return const Text('child');
                          },
                        ),
                      );
                    },
                  ),
                  Builder(
                    builder: (context) {
                      siblingRequest = dependentRef(context);
                      return const Text('sibling');
                    },
                  ),
                ],
              ),
            ),
          ),
        );

        expect(identical(firstRequest, siblingRequest), isTrue);
        expect(identical(siblingRequest.resource, rootResource), isTrue);
        expect(identical(siblingRequest.resource, childResource), isFalse);

        showChild.value = false;
        await tester.pumpAndSettle();

        expect(rootResource.disposed, isFalse);
        expect(identical(siblingRequest.resource, rootResource), isTrue);

        await tester.pumpWidget(const MaterialApp(home: Text('')));
        await tester.pumpAndSettle();

        expect(rootResource.disposed, isTrue);
      },
    );

    testWidgets(
      'create receives the owning scope context for inherited lookups',
      (tester) async {
        late Brightness factoryBrightness;
        final brightnessRef = Ref.scoped((ctx) {
          return factoryBrightness = Theme.of(ctx).brightness;
        });

        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(brightness: Brightness.light),
            home: LiteRefScope(
              child: Theme(
                data: ThemeData(brightness: Brightness.dark),
                child: Builder(
                  builder: (context) => Text('${brightnessRef(context)}'),
                ),
              ),
            ),
          ),
        );

        expect(factoryBrightness, Brightness.light);
        expect(find.text('Brightness.light'), findsOneWidget);
      },
    );

    testWidgets(
      'replacing a dependency rebuilds dependents before disposing them',
      (tester) async {
        final current = ValueNotifier(0);
        final first = _Resource();
        final second = _Resource();
        final disposedDependents = <_Resource>[];
        final resourceRef = Ref.scoped<_Resource>(
          (_) => throw StateError('An override is required'),
        );
        final dependentRef = Ref.scopedFamily<_Dependent, int>(
          (ctx, _) => _Dependent(resourceRef(ctx)),
          dispose: (dependent) {
            expect(dependent.resource.disposed, isFalse);
            disposedDependents.add(dependent.resource);
          },
        );
        late _Dependent visibleDependent;

        await tester.pumpWidget(
          MaterialApp(
            home: ListenableBuilder(
              listenable: current,
              builder: (context, _) {
                return LiteRefScope(
                  overrides: {
                    resourceRef.overrideWith(
                      (_) => current.value == 0 ? first : second,
                    ),
                  },
                  child: Builder(
                    builder: (context) {
                      visibleDependent = dependentRef(context, 42);
                      return Text('${identityHashCode(visibleDependent)}');
                    },
                  ),
                );
              },
            ),
          ),
        );

        final initialDependent = visibleDependent;
        expect(identical(initialDependent.resource, first), isTrue);

        current.value = 1;
        await tester.pumpAndSettle();

        expect(identical(visibleDependent, initialDependent), isFalse);
        expect(identical(visibleDependent.resource, second), isTrue);
        expect(disposedDependents, [first]);
        expect(first.disposed, isTrue);
        expect(second.disposed, isFalse);
      },
    );

    testWidgets(
      'a throwing factory releases dependencies it already acquired',
      (tester) async {
        final resource = _Resource();
        final resourceRef = Ref.scoped((_) => resource);
        final throwingRef = Ref.scoped<int>((ctx) {
          resourceRef(ctx);
          throw StateError('factory failed');
        });

        await tester.pumpWidget(
          MaterialApp(
            home: LiteRefScope(
              child: Builder(
                builder: (context) {
                  expect(() => throwingRef(context), throwsStateError);
                  return const SizedBox.shrink();
                },
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(resource.disposed, isTrue);
      },
    );

    testWidgets(
      'autoDispose false values are disposed when their scope unmounts',
      (tester) async {
        final resource = _Resource();
        final notifier = ValueNotifier(0);
        final resourceRef = Ref.scoped(
          (_) => resource,
          autoDispose: false,
        );
        final notifierRef = Ref.scoped(
          (_) => notifier,
          autoDispose: false,
        );

        await tester.pumpWidget(
          MaterialApp(
            home: LiteRefScope(
              child: Builder(
                builder: (context) {
                  resourceRef(context);
                  notifierRef(context);
                  return const SizedBox.shrink();
                },
              ),
            ),
          ),
        );

        await tester.pumpWidget(const MaterialApp(home: Text('')));
        await tester.pumpAndSettle();

        expect(resource.disposed, isTrue);
        expect(() => notifier.addListener(() {}), throwsFlutterError);
      },
    );

    testWidgets(
      'autoDispose false overrides are disposed when replaced',
      (tester) async {
        final current = ValueNotifier(0);
        final first = _Resource();
        final second = _Resource();
        final resourceRef = Ref.scoped<_Resource>(
          (_) => throw StateError('An override is required'),
        );

        await tester.pumpWidget(
          MaterialApp(
            home: ListenableBuilder(
              listenable: current,
              builder: (context, _) {
                return LiteRefScope(
                  overrides: {
                    resourceRef.overrideWith(
                      (_) => current.value == 0 ? first : second,
                      autoDispose: false,
                    ),
                  },
                  child: Builder(
                    builder: (context) {
                      resourceRef(context);
                      return const SizedBox.shrink();
                    },
                  ),
                );
              },
            ),
          ),
        );

        current.value = 1;
        await tester.pumpAndSettle();

        expect(first.disposed, isTrue);
        expect(second.disposed, isFalse);

        await tester.pumpWidget(const MaterialApp(home: Text('')));
        await tester.pumpAndSettle();

        expect(second.disposed, isTrue);
      },
    );

    testWidgets(
      'overrideWithValue leaves disposal to the external owner',
      (tester) async {
        final current = ValueNotifier(0);
        final first = _Resource();
        final second = _Resource();
        final familyResource = _Resource();
        final resourceRef = Ref.scoped<_Resource>(
          (_) => throw StateError('An override is required'),
        );
        final familyRef = Ref.scopedFamily<_Resource, int>(
          (_, __) => throw StateError('An override is required'),
        );

        await tester.pumpWidget(
          MaterialApp(
            home: ListenableBuilder(
              listenable: current,
              builder: (context, _) {
                return LiteRefScope(
                  overrides: {
                    resourceRef.overrideWithValue(
                      current.value == 0 ? first : second,
                    ),
                    familyRef.overrideWithValue(familyResource),
                  },
                  child: Builder(
                    builder: (context) {
                      resourceRef(context);
                      familyRef(context, 1);
                      return const SizedBox.shrink();
                    },
                  ),
                );
              },
            ),
          ),
        );

        current.value = 1;
        await tester.pumpAndSettle();
        await tester.pumpWidget(const MaterialApp(home: Text('')));
        await tester.pumpAndSettle();

        expect(first.disposed, isFalse);
        expect(second.disposed, isFalse);
        expect(familyResource.disposed, isFalse);

        first.dispose();
        second.dispose();
        familyResource.dispose();
      },
    );

    testWidgets(
      'onlyOverrides evicts local values without recreating overrides',
      (tester) async {
        final current = ValueNotifier(false);
        final disposed = <int>[];
        var localCreations = 0;
        var overrideCreations = 0;
        final localRef = Ref.scoped(
          (_) => ++localCreations,
          dispose: disposed.add,
        );
        final retainedRef = Ref.scoped((_) => 0);
        final retainedOverride = retainedRef.overrideWith(
          (_) => ++overrideCreations,
        );
        final consumer = Builder(
          builder: (context) {
            return Text('${localRef(context)}:${retainedRef(context)}');
          },
        );

        await tester.pumpWidget(
          MaterialApp(
            home: LiteRefScope(
              overrides: {localRef.overrideWithValue(-1)},
              child: ListenableBuilder(
                listenable: current,
                builder: (context, _) {
                  return LiteRefScope(
                    onlyOverrides: current.value,
                    overrides: {retainedOverride},
                    child: consumer,
                  );
                },
              ),
            ),
          ),
        );

        expect(find.text('1:1'), findsOneWidget);
        expect(localCreations, 1);
        expect(overrideCreations, 1);

        current.value = true;
        await tester.pumpAndSettle();

        expect(find.text('-1:1'), findsOneWidget);
        expect(disposed, [1]);
        expect(overrideCreations, 1);

        current.value = false;
        await tester.pumpAndSettle();

        expect(find.text('2:1'), findsOneWidget);
        expect(localCreations, 2);
        expect(overrideCreations, 1);
      },
    );

    testWidgets(
      'onlyOverrides evicts every non-overridden family key',
      (tester) async {
        final current = ValueNotifier(false);
        final disposed = <int>[];
        final creations = <int, int>{};
        final familyRef = Ref.scopedFamily<int, int>(
          (_, family) {
            final creation = creations.update(
              family,
              (value) => value + 1,
              ifAbsent: () => 1,
            );
            return family * 10 + creation;
          },
          dispose: disposed.add,
        );
        final consumer = Builder(
          builder: (context) {
            return Column(
              children: [
                Text('${familyRef(context, 1)}'),
                Text('${familyRef(context, 2)}'),
              ],
            );
          },
        );

        await tester.pumpWidget(
          MaterialApp(
            home: LiteRefScope(
              overrides: {
                familyRef.overrideWith((_, family) => -family),
              },
              child: ListenableBuilder(
                listenable: current,
                builder: (context, _) {
                  return LiteRefScope(
                    onlyOverrides: current.value,
                    child: consumer,
                  );
                },
              ),
            ),
          ),
        );

        expect(find.text('11'), findsOneWidget);
        expect(find.text('21'), findsOneWidget);

        current.value = true;
        await tester.pumpAndSettle();

        expect(find.text('-1'), findsOneWidget);
        expect(find.text('-2'), findsOneWidget);
        expect(disposed, [11, 21]);

        current.value = false;
        await tester.pumpAndSettle();

        expect(find.text('12'), findsOneWidget);
        expect(find.text('22'), findsOneWidget);
        expect(creations, {1: 2, 2: 2});
      },
    );

    testWidgets(
      'one throwing disposer does not abort the post-frame flush',
      (tester) async {
        final previousOnError = FlutterError.onError;
        final errors = <FlutterErrorDetails>[];
        FlutterError.onError = errors.add;
        addTearDown(() => FlutterError.onError = previousOnError);
        final show = ValueNotifier(true);
        final disposed = <int>[];
        final firstRef = Ref.scoped(
          (_) => 1,
          dispose: (value) {
            disposed.add(value);
            throw StateError('first dispose failed');
          },
        );
        final secondRef = Ref.scoped(
          (_) => 2,
          dispose: disposed.add,
        );

        await tester.pumpWidget(
          MaterialApp(
            home: LiteRefScope(
              child: ListenableBuilder(
                listenable: show,
                builder: (context, _) {
                  if (!show.value) return const SizedBox.shrink();
                  return Builder(
                    builder: (context) {
                      firstRef(context);
                      secondRef(context);
                      return const SizedBox.shrink();
                    },
                  );
                },
              ),
            ),
          ),
        );

        show.value = false;
        await tester.pumpAndSettle();

        expect(disposed, [1, 2]);
        expect(errors, hasLength(1));
        expect(errors.single.exception, isStateError);
      },
    );

    testWidgets(
      'one throwing disposer does not abort scope unmount',
      (tester) async {
        final previousOnError = FlutterError.onError;
        final errors = <FlutterErrorDetails>[];
        FlutterError.onError = errors.add;
        addTearDown(() => FlutterError.onError = previousOnError);
        final disposed = <int>[];
        final firstRef = Ref.scoped(
          (_) => 1,
          dispose: (value) {
            disposed.add(value);
            throw StateError('first dispose failed');
          },
        );
        final secondRef = Ref.scoped(
          (_) => 2,
          dispose: disposed.add,
        );

        await tester.pumpWidget(
          MaterialApp(
            home: LiteRefScope(
              child: Builder(
                builder: (context) {
                  firstRef(context);
                  secondRef(context);
                  return const SizedBox.shrink();
                },
              ),
            ),
          ),
        );

        await tester.pumpWidget(const MaterialApp(home: Text('')));
        await tester.pumpAndSettle();
        await tester.pumpWidget(const SizedBox.shrink());

        expect(disposed, [1, 2]);
        expect(errors, hasLength(1));
        expect(errors.single.exception, isStateError);
      },
    );

    testWidgets(
      'dependencies released during a flush are disposed in the same cleanup',
      (tester) async {
        final dependency = _Resource();
        final dependencyRef = Ref.scoped((_) => dependency);
        final dependentRef = Ref.scoped(
          (ctx) => _Dependent(dependencyRef(ctx)),
        );
        final show = ValueNotifier(true);

        await tester.pumpWidget(
          MaterialApp(
            home: LiteRefScope(
              child: ListenableBuilder(
                listenable: show,
                builder: (context, _) {
                  if (!show.value) return const Text('hidden');
                  return Builder(
                    builder: (context) {
                      dependentRef(context);
                      return const Text('visible');
                    },
                  );
                },
              ),
            ),
          ),
        );

        show.value = false;
        await tester.pumpAndSettle();

        expect(dependency.disposed, isTrue);
        expect(find.text('hidden'), findsOneWidget);
      },
    );

    testWidgets(
      'a dependency released by another scope schedules its disposal frame',
      (tester) async {
        final dependency = _Resource();
        final dependencyRef = Ref.scopedFamily<_Resource, int>(
          (_, __) => dependency,
        );
        final dependentRef = Ref.scoped<_Dependent>(
          (_) => throw StateError('An override is required'),
        );
        final dependentOverride = dependentRef.overrideWith(
          (ctx) => _Dependent(dependencyRef(ctx, 1)),
        );

        Widget tree({required bool listen}) {
          return MaterialApp(
            home: LiteRefScope(
              child: LiteRefScope(
                onlyOverrides: true,
                overrides: {dependentOverride},
                child: listen
                    ? Builder(
                        builder: (context) {
                          dependentRef(context);
                          return const SizedBox.shrink();
                        },
                      )
                    : const SizedBox.shrink(),
              ),
            ),
          );
        }

        await tester.pumpWidget(tree(listen: true));
        await tester.pumpWidget(tree(listen: false));

        // The child scope releases the parent-owned dependency inside this
        // frame's post-frame callback. Its cleanup must schedule a new frame.
        expect(dependency.disposed, isFalse);
        expect(tester.binding.hasScheduledFrame, isTrue);

        await tester.pump();

        expect(dependency.disposed, isTrue);
      },
    );

    testWidgets(
      'adding an override invalidates dependents resolved through that scope',
      (tester) async {
        final current = ValueNotifier(false);
        final dependencyRef = Ref.scoped((_) => 0);
        final dependentRef = Ref.scoped<int>(
          (_) => throw StateError('An override is required'),
        );
        final dependentOverride = dependentRef.overrideWith(
          dependencyRef.call,
        );
        final consumer = Builder(
          builder: (context) => Text('${dependentRef(context)}'),
        );

        await tester.pumpWidget(
          MaterialApp(
            home: LiteRefScope(
              overrides: {dependencyRef.overrideWith((_) => 1)},
              child: ListenableBuilder(
                listenable: current,
                builder: (context, _) {
                  return LiteRefScope(
                    onlyOverrides: true,
                    overrides: {
                      dependentOverride,
                      if (current.value) dependencyRef.overrideWith((_) => 2),
                    },
                    child: consumer,
                  );
                },
              ),
            ),
          ),
        );

        expect(find.text('1'), findsOneWidget);

        current.value = true;
        await tester.pumpAndSettle();

        expect(find.text('2'), findsOneWidget);
      },
    );

    testWidgets(
      'disabling onlyOverrides invalidates parent-resolved dependents',
      (tester) async {
        final current = ValueNotifier(true);
        final dependencyRef = Ref.scoped((_) => 3);
        final dependentRef = Ref.scoped<int>(
          (_) => throw StateError('An override is required'),
        );
        final dependentOverride = dependentRef.overrideWith(
          dependencyRef.call,
        );
        final consumer = Builder(
          builder: (context) => Text('${dependentRef(context)}'),
        );

        await tester.pumpWidget(
          MaterialApp(
            home: LiteRefScope(
              overrides: {dependencyRef.overrideWith((_) => 1)},
              child: ListenableBuilder(
                listenable: current,
                builder: (context, _) {
                  return LiteRefScope(
                    onlyOverrides: current.value,
                    overrides: {dependentOverride},
                    child: consumer,
                  );
                },
              ),
            ),
          ),
        );

        expect(find.text('1'), findsOneWidget);

        current.value = false;
        await tester.pumpAndSettle();

        expect(find.text('3'), findsOneWidget);
      },
    );

    testWidgets(
      'moving a keyed scope rebuilds dependencies from its new parent',
      (tester) async {
        final current = ValueNotifier(1);
        final first = _Resource();
        final second = _Resource();
        final resourceRef = Ref.scoped<_Resource>(
          (_) => throw StateError('A parent override is required'),
        );
        final dependentRef = Ref.scoped<_Dependent>(
          (_) => throw StateError('An override is required'),
        );
        final dependentOverride = dependentRef.overrideWith(
          (ctx) => _Dependent(resourceRef(ctx)),
          autoDispose: true,
        );
        final movedScope = LiteRefScope(
          key: GlobalKey(),
          onlyOverrides: true,
          overrides: {dependentOverride},
          child: Builder(
            builder: (context) {
              final dependent = dependentRef(context);
              return Text('${identityHashCode(dependent.resource)}');
            },
          ),
        );

        Widget slot(_Resource resource) {
          return LiteRefScope(
            overrides: {resourceRef.overrideWith((_) => resource)},
            child: movedScope,
          );
        }

        await tester.pumpWidget(
          MaterialApp(
            home: LiteRefScope(
              child: ListenableBuilder(
                listenable: current,
                builder: (context, _) {
                  return Column(
                    children: [
                      const SizedBox.shrink(),
                      if (current.value == 1) slot(first),
                      const SizedBox.shrink(),
                      if (current.value == 2) slot(second),
                    ],
                  );
                },
              ),
            ),
          ),
        );

        final initialValue = identityHashCode(first);
        expect(find.text('$initialValue'), findsOneWidget);

        current.value = 2;
        await tester.pumpAndSettle();

        expect(find.text('${identityHashCode(second)}'), findsOneWidget);
        expect(first.disposed, isTrue);
        expect(second.disposed, isFalse);
      },
    );

    testWidgets(
      'explicit disposers receive null exactly once',
      (tester) async {
        final disposed = <int?>[];
        final nullableRef = Ref.scoped<int?>(
          (_) => null,
          dispose: disposed.add,
        );
        final show = ValueNotifier(true);

        await tester.pumpWidget(
          MaterialApp(
            home: LiteRefScope(
              child: ListenableBuilder(
                listenable: show,
                builder: (context, _) {
                  if (!show.value) return const SizedBox.shrink();
                  return Builder(
                    builder: (context) {
                      nullableRef(context);
                      return const SizedBox.shrink();
                    },
                  );
                },
              ),
            ),
          ),
        );

        show.value = false;
        await tester.pumpAndSettle();
        await tester.pumpWidget(const MaterialApp(home: Text('')));
        await tester.pumpAndSettle();

        expect(disposed, [null]);
      },
    );

    testWidgets(
      'unmount keeps a dependency alive until its dependent is disposed',
      (tester) async {
        final dependency = _Resource();
        final disposalOrder = <String>[];

        final dependencyRef = Ref.scoped((_) => dependency);
        final dependentRef = Ref.scoped(
          (ctx) => _Dependent(dependencyRef(ctx)),
          dispose: (dependent) {
            disposalOrder.add('dependent');
            expect(dependent.resource.disposed, isFalse);
          },
        );

        await tester.pumpWidget(
          MaterialApp(
            home: LiteRefScope(
              child: Builder(
                builder: (context) {
                  dependentRef(context);
                  return const SizedBox.shrink();
                },
              ),
            ),
          ),
        );

        expect(disposalOrder, isEmpty);
        expect(dependency.disposed, isFalse);

        await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
        await tester.pumpAndSettle();

        expect(disposalOrder, ['dependent']);
        expect(dependency.disposed, isTrue);
      },
    );

    testWidgets(
      'a dependency evicted from a parent scope outlives its child-scope '
      'dependent',
      (tester) async {
        final first = _Resource();
        final second = _Resource();
        final current = ValueNotifier(0);
        final disposalOrder = <String>[];

        final resourceRef = Ref.scoped<_Resource>(
          (_) => throw StateError('A parent override is required'),
        );
        final dependentRef = Ref.scoped<_Dependent>(
          (_) => throw StateError('An inner override is required'),
          dispose: (dependent) {
            disposalOrder.add('dependent');
            expect(dependent.resource.disposed, isFalse);
          },
        );
        final dependentOverride = dependentRef.overrideWith(
          (ctx) => _Dependent(resourceRef(ctx)),
        );

        await tester.pumpWidget(
          MaterialApp(
            home: ListenableBuilder(
              listenable: current,
              builder: (context, _) {
                return LiteRefScope(
                  overrides: {
                    resourceRef.overrideWith(
                      (_) => current.value == 0 ? first : second,
                    ),
                  },
                  child: LiteRefScope(
                    onlyOverrides: true,
                    overrides: {dependentOverride},
                    child: Builder(
                      builder: (context) {
                        dependentRef(context);
                        return const SizedBox.shrink();
                      },
                    ),
                  ),
                );
              },
            ),
          ),
        );

        expect(first.disposed, isFalse);

        current.value = 1;
        await tester.pumpAndSettle();

        expect(disposalOrder, ['dependent']);
        expect(first.disposed, isTrue);
        expect(second.disposed, isFalse);
      },
    );

    testWidgets(
      'a lookup after a factory completes binds the element, not the object',
      (tester) async {
        final dependency = _Resource();
        final gate = Completer<void>();
        var lookups = 0;
        late BuildContext captured;

        final dependencyRef = Ref.scoped((_) {
          lookups++;
          return dependency;
        });
        final holderRef = Ref.scoped<Object>((ctx) {
          captured = ctx;
          unawaited(
            Future<void>.microtask(() async {
              await gate.future;
              dependencyRef(captured);
            }),
          );
          return Object();
        });

        await tester.pumpWidget(
          MaterialApp(
            home: LiteRefScope(
              child: Builder(
                builder: (context) {
                  holderRef(context);
                  return const SizedBox.shrink();
                },
              ),
            ),
          ),
        );

        gate.complete();
        await tester.pump();
        await tester.pump();

        // The late lookup ran, so a stale creation zone would have registered
        // the finished object as a dependent of [dependency].
        expect(lookups, 1);
        expect(dependency.disposed, isFalse);

        await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
        await tester.pumpAndSettle();

        expect(dependency.disposed, isTrue);
      },
    );

    testWidgets(
      'a failed factory is retried instead of serving a cached entry',
      (tester) async {
        var calls = 0;
        final flakyRef = Ref.scoped<int>((_) {
          calls++;
          if (calls == 1) throw StateError('first attempt fails');
          return 42;
        });

        await tester.pumpWidget(
          MaterialApp(
            home: LiteRefScope(
              child: Builder(
                builder: (context) {
                  expect(() => flakyRef(context), throwsStateError);
                  expect(flakyRef(context), 42);
                  return const SizedBox.shrink();
                },
              ),
            ),
          ),
        );

        expect(calls, 2);
      },
    );
  });

  group('ScopedFamilyRef', () {
    testWidgets(
      'retains earlier keys until the consumer unmounts',
      (tester) async {
        final current = ValueNotifier(1);
        final show = ValueNotifier(true);
        final disposed = <int>[];
        final familyRef = Ref.scopedFamily<int, int>(
          (_, family) => family,
          dispose: disposed.add,
        );

        await tester.pumpWidget(
          MaterialApp(
            home: LiteRefScope(
              child: ListenableBuilder(
                listenable: show,
                builder: (context, _) {
                  if (!show.value) return const Text('hidden');
                  return ListenableBuilder(
                    listenable: current,
                    builder: (context, _) {
                      return Builder(
                        builder: (context) {
                          return Text('${familyRef(context, current.value)}');
                        },
                      );
                    },
                  );
                },
              ),
            ),
          ),
        );

        expect(find.text('1'), findsOneWidget);

        current.value = 2;
        await tester.pumpAndSettle();
        expect(find.text('2'), findsOneWidget);

        current.value = 3;
        await tester.pumpAndSettle();
        expect(find.text('3'), findsOneWidget);

        // Earlier keys remain retained while this consumer is mounted.
        expect(disposed, isEmpty);

        show.value = false;
        await tester.pumpAndSettle();

        expect(find.text('hidden'), findsOneWidget);
        expect(disposed, [1, 2, 3]);
      },
    );

    testWidgets(
      'should auto-dispose an override that enables autoDispose',
      (tester) async {
        final disposed = <int>[];
        final show = ValueNotifier(true);
        final countRef = Ref.scopedFamily(
          (ctx, int f) => 0,
          dispose: disposed.add,
          autoDispose: false,
        );
        final override = countRef.overrideWith((_, __) => 1);

        await tester.pumpWidget(
          MaterialApp(
            home: LiteRefScope(
              child: Builder(
                builder: (context) {
                  return LiteRefScope(
                    overrides: {override},
                    child: ListenableBuilder(
                      listenable: show,
                      builder: (context, _) => show.value
                          ? Builder(
                              builder: (context) =>
                                  Text('${countRef(context, 0)}'),
                            )
                          : const Text('hidden'),
                    ),
                  );
                },
              ),
            ),
          ),
        );

        await tester.pumpAndSettle();

        expect(find.text('1'), findsOneWidget);
        expect(disposed, isEmpty);

        show.value = false;
        await tester.pumpAndSettle();

        expect(find.text('hidden'), findsOneWidget);
        expect(disposed, [1]);
      },
    );

    test('overridden instance should be equal to main', () {
      final countRef = Ref.scopedFamily((ctx, int a) => 1);
      final countRefClone = countRef.overrideWith((ctx, int a) => 2);

      expect(countRef, countRefClone);

      final hashSet = <Object>{}..add(countRef);

      expect(hashSet.contains(countRefClone), true);
    });

    testWidgets('should cache values', (tester) async {
      var ran = 0;
      final countRef = Ref.scopedFamily((ctx, int a) => ++ran);

      await tester.pumpWidget(
        MaterialApp(
          home: LiteRefScope(
            child: Builder(
              builder: (context) {
                final val = countRef(context, 1);
                final val2 = countRef(context, 1);
                expect(val, 1);
                expect(val2, 1);
                return Text('$val $val2');
              },
            ),
          ),
        ),
      );

      expect(ran, 1);

      final txt = find.text('1 1');

      expect(txt, findsOneWidget);
    });

    testWidgets('family should return different values', (tester) async {
      final countRef = Ref.scopedFamily((ctx, int a) => 1 + a);

      await tester.pumpWidget(
        MaterialApp(
          home: LiteRefScope(
            child: Builder(
              builder: (context) {
                final val = countRef(context, 0);
                final val2 = countRef(context, 1);
                expect(val, 1);
                expect(val2, 2);
                return Text('$val $val2');
              },
            ),
          ),
        ),
      );

      final txt = find.text('1 2');

      expect(txt, findsOneWidget);
    });

    testWidgets(
      'should throw when there is no root LiteRefScope',
      (tester) async {
        final countRef = Ref.scopedFamily((ctx, String family) => 1);

        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) {
                // This should trigger the error
                expect(
                  () => countRef(context, 'one'),
                  throwsA(isA<AssertionError>()),
                );
                return const SizedBox.shrink();
              },
            ),
          ),
        );
      },
    );

    testWidgets('overridden instance should return different instances',
        (tester) async {
      final controllerRef = Ref.scopedFamily(
        (ctx, int family) => _Controller(id: family),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: LiteRefScope(
            child: Builder(
              builder: (context) {
                final controller = controllerRef(context, 42);
                expect(
                  controller,
                  isA<_Controller>()
                      .having((p0) => p0.id, 'id', 42)
                      .having((p0) => p0.value, 'value', 0),
                );
                return LiteRefScope(
                  overrides: {
                    controllerRef.overrideWith(
                      (ctx, int _) => _Controller(id: 0, value: 1),
                    ),
                  },
                  child: Column(
                    children: [
                      Text('${controller.value}'),
                      Builder(
                        builder: (context) {
                          final controller = controllerRef(context, 42);
                          expect(
                            controller,
                            isA<_Controller>()
                                .having((p0) => p0.id, 'id', 0)
                                .having((p0) => p0.value, 'value', 1),
                          );
                          return Text('${controller.value}');
                        },
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      );

      expect(find.text('0'), findsOneWidget);
      expect(find.text('1'), findsOneWidget);
    });

    testWidgets('should be able to use other refs', (tester) async {
      final statusValue = Ref.scoped((context) => 200);
      final controller = Ref.scopedFamily((context, int id) {
        final status = statusValue.of(context);
        return _Controller(id: id, value: status);
      });

      await tester.pumpWidget(
        MaterialApp(
          home: LiteRefScope(
            child: Builder(
              builder: (context) {
                final controller1 = controller(context, 1);
                expect(
                  controller1,
                  isA<_Controller>()
                      .having((p0) => p0.id, 'id', 1)
                      .having((p0) => p0.value, 'status', 200),
                );
                return Text(
                  'id: ${controller1.id}, status: ${controller1.value}',
                );
              },
            ),
          ),
        ),
      );

      expect(find.text('id: 1, status: 200'), findsOneWidget);
    });

    testWidgets('should dispose family when scope is unmounted',
        (tester) async {
      final disposed = <int>[];
      final countRef = Ref.scopedFamily(
        (ctx, int family) => 0 + family,
        dispose: disposed.add,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: LiteRefScope(
            child: Builder(
              builder: (context) {
                final val = countRef(context, 1);
                expect(val, 1);
                final val2 = countRef(context, 2);
                expect(val2, 2);
                return LiteRefScope(
                  overrides: {
                    countRef.overrideWith((ctx, f) => 3),
                  },
                  child: Builder(
                    builder: (context) {
                      final val = countRef(context, 1);
                      expect(val, 3);
                      return Text('$val $val2');
                    },
                  ),
                );
              },
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('3 2'), findsOneWidget);

      expect(disposed, isEmpty);

      await tester.pumpWidget(
        MaterialApp(
          home: LiteRefScope(
            child: Builder(
              builder: (context) {
                final val = countRef(context, 1);
                expect(val, 1);
                final val2 = countRef(context, 2);
                expect(val2, 2);
                return Text('$val $val2');
              },
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('1 2'), findsOneWidget);
      expect(disposed, [3]); // overridden instance should be disposed

      await tester.pumpWidget(
        const MaterialApp(
          home: LiteRefScope(child: Text('')),
        ),
      );

      await tester.pumpAndSettle();

      expect(disposed, [3, 1, 2]); // all instances should be disposed
    });

    testWidgets(
        'should dispose family when scope is unmounted when autodispose=false',
        (tester) async {
      final disposed = <int>[];
      final countRef = Ref.scopedFamily(
        (ctx, int f) => 0 + f,
        dispose: disposed.add,
        autoDispose: false,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: LiteRefScope(
            child: Builder(
              builder: (context) {
                final val = countRef(context, 1);
                expect(val, 1);
                final val2 = countRef(context, 2);
                expect(val2, 2);
                return LiteRefScope(
                  overrides: {
                    countRef.overrideWith((ctx, f) => 3),
                  },
                  child: Builder(
                    builder: (context) {
                      final val = countRef(context, 1);
                      expect(val, 3);
                      return Text('$val $val2');
                    },
                  ),
                );
              },
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('3 2'), findsOneWidget);
      expect(disposed, isEmpty);

      await tester.pumpWidget(
        MaterialApp(
          home: LiteRefScope(
            child: Builder(
              builder: (context) {
                final val = countRef(context, 1);
                expect(val, 1);
                final val2 = countRef(context, 2);
                expect(val2, 2);
                return Text('$val $val2');
              },
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('1 2'), findsOneWidget);
      expect(disposed, [3]); // overridden instance should be disposed

      await tester.pumpWidget(
        const MaterialApp(
          home: Text(''),
        ),
      );

      await tester.pumpAndSettle();

      expect(disposed, [3, 1, 2]);
    });

    testWidgets('should dispose family when only child is unmounted',
        (tester) async {
      final disposed = <int>[];
      final countRef = Ref.scopedFamily(
        (ctx, int f) => 0 + f,
        dispose: disposed.add,
      );
      final show = ValueNotifier(true);

      await tester.pumpWidget(
        MaterialApp(
          home: LiteRefScope(
            child: Builder(
              builder: (context) {
                final val0 = countRef(context, 0);
                return ListenableBuilder(
                  listenable: show,
                  builder: (context, snapshot) {
                    if (!show.value) {
                      return Column(
                        children: [
                          const Text('hidden'),
                          Text('$val0'),
                        ],
                      );
                    }
                    return Builder(
                      builder: (context) {
                        final val1 = countRef(context, 1);
                        expect(val1, 1);
                        return Text('$val0 $val1');
                      },
                    );
                  },
                );
              },
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('0 1'), findsOneWidget);

      expect(disposed, isEmpty);

      show.value = false;

      await tester.pumpAndSettle();

      expect(find.text('hidden'), findsOneWidget);
      expect(find.text('0'), findsOneWidget);

      expect(disposed, [1]);
    });

    testWidgets('should dispose family when all children are unmounted',
        (tester) async {
      final disposed = <int>[];
      final countRef = Ref.scopedFamily(
        (ctx, int f) => 0 + f,
        dispose: disposed.add,
      );
      final amount = ValueNotifier(3);

      await tester.pumpWidget(
        MaterialApp(
          home: LiteRefScope(
            child: ListenableBuilder(
              listenable: amount,
              builder: (context, snapshot) {
                final val0 = countRef(context, 0);
                return Column(
                  children: [
                    Text('$val0'),
                    for (var i = 0; i < amount.value; i++)
                      Builder(
                        builder: (context) {
                          final val1 = countRef(context, 1);
                          expect(val1, 1);
                          return Text('$val1');
                        },
                      ),
                  ],
                );
              },
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('0'), findsOneWidget);
      expect(find.text('1'), findsExactly(amount.value));

      expect(disposed, isEmpty);

      amount.value = 2;

      await tester.pumpAndSettle();

      expect(find.text('0'), findsOneWidget);
      expect(find.text('1'), findsExactly(amount.value));

      expect(disposed, isEmpty); // still has listeners

      amount.value = 0;

      await tester.pumpAndSettle();

      expect(find.text('0'), findsOneWidget);
      expect(find.text('1'), findsNothing);

      expect(disposed, [1]); // dispose when all children are unmounted
    });

    testWidgets(
      'should dispose a Disposable family when no dispose function is supplied',
      (tester) async {
        final resources = <int, _Resource>{};
        final countRef = Ref.scopedFamily((ctx, int f) {
          return resources.putIfAbsent(f, _Resource.new);
        });
        final show = ValueNotifier(true);

        await tester.pumpWidget(
          MaterialApp(
            home: LiteRefScope(
              child: ListenableBuilder(
                listenable: show,
                builder: (context, snapshot) {
                  final val0 = countRef(context, 0);
                  return Column(
                    children: [
                      Text('val0: ${val0.disposed}'),
                      if (!show.value)
                        const Text('hidden')
                      else
                        Builder(
                          builder: (context) {
                            final val1 = countRef(context, 1);
                            return Text('val1: ${val1.disposed}');
                          },
                        ),
                    ],
                  );
                },
              ),
            ),
          ),
        );

        await tester.pumpAndSettle();

        expect(find.text('val0: false'), findsOneWidget);
        expect(find.text('val1: false'), findsOneWidget);

        expect(
          resources[0],
          isA<_Resource>().having((p0) => p0.disposed, 'disposed', false),
        );
        expect(
          resources[1],
          isA<_Resource>().having((p0) => p0.disposed, 'disposed', false),
        );

        show.value = false;

        await tester.pumpAndSettle();

        expect(find.text('val0: false'), findsOneWidget);
        expect(find.text('hidden'), findsOneWidget);

        expect(
          resources[0],
          isA<_Resource>().having((p0) => p0.disposed, 'disposed', false),
        );
        expect(
          resources[1],
          isA<_Resource>().having((p0) => p0.disposed, 'disposed', true),
        );
      },
    );

    testWidgets(
      'should dispose ValueNotifier in a family scope '
      'when no dispose function is supplied',
      (tester) async {
        final vn = ValueNotifier(1);
        final countRef = Ref.scopedFamily((ctx, int _) => vn);
        final show = ValueNotifier(true);

        await tester.pumpWidget(
          MaterialApp(
            home: LiteRefScope(
              child: ListenableBuilder(
                listenable: show,
                builder: (context, snapshot) {
                  if (!show.value) return const Text('hidden');
                  return Builder(
                    builder: (context) {
                      final val = countRef(context, 0);
                      return Text('${val.value}');
                    },
                  );
                },
              ),
            ),
          ),
        );

        await tester.pumpAndSettle();

        expect(find.text('1'), findsOneWidget);

        vn.addListener(() {}); // not disposed. ie: should not throw

        show.value = false;

        await tester.pumpAndSettle();

        expect(find.text('hidden'), findsOneWidget);

        // should throw when disposed
        expect(() => vn.addListener(() {}), throwsFlutterError);
      },
    );

    testWidgets(
      'should dispose correct family instance when override',
      (tester) async {
        final resource = _Resource();
        final resource2 = _Resource();
        final countRef = Ref.scopedFamily((ctx, String _) => resource);
        final countRef2 = countRef.overrideWith((_, __) => resource2);
        final show = ValueNotifier(true);

        await tester.pumpWidget(
          MaterialApp(
            home: LiteRefScope(
              child: ListenableBuilder(
                listenable: show,
                builder: (context, snapshot) {
                  return LiteRefScope(
                    overrides: {countRef2},
                    child: !show.value
                        ? const Text('hidden')
                        : Column(
                            children: [
                              Builder(
                                builder: (context) {
                                  final val = countRef(context, '1');
                                  return Text('${val.disposed}');
                                },
                              ),
                              Builder(
                                builder: (context) {
                                  final val = countRef(context, '1');
                                  return Text('${val.disposed}');
                                },
                              ),
                            ],
                          ),
                  );
                },
              ),
            ),
          ),
        );

        await tester.pumpAndSettle();

        expect(find.text('false'), findsExactly(2));

        expect(resource.disposed, false);
        expect(resource2.disposed, false);

        show.value = false;

        await tester.pumpAndSettle();

        expect(find.text('hidden'), findsOneWidget);

        expect(resource.disposed, false);
        expect(resource2.disposed, true);
      },
    );

    testWidgets(
      'should get correct family value when GlobalKey changes '
      'causes it to move its position in the tree',
      (tester) async {
        final current = ValueNotifier(1);
        final countRef = Ref.scopedFamily((ctx, int _) => 0);

        final child = Builder(
          key: GlobalKey(),
          builder: (context) {
            final val = countRef.of(context, 0);
            return Text('got: $val');
          },
        );

        await tester.pumpWidget(
          MaterialApp(
            home: LiteRefScope(
              child: Column(
                children: [
                  ListenableBuilder(
                    listenable: current,
                    builder: (context, snapshot) {
                      if (current.value != 1) {
                        return const SizedBox.shrink();
                      }
                      return LiteRefScope(
                        overrides: {
                          countRef.overrideWith((_, __) => 1),
                        },
                        child: Builder(
                          builder: (context) => child,
                        ),
                      );
                    },
                  ),
                  ListenableBuilder(
                    listenable: current,
                    builder: (context, snapshot) {
                      if (current.value != 2) {
                        return const SizedBox.shrink();
                      }
                      return LiteRefScope(
                        overrides: {
                          countRef.overrideWith((_, __) => 2),
                        },
                        child: Builder(
                          builder: (context) => child,
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        );

        expect(find.text('got: 1'), findsOneWidget);
        current.value = 2;
        await tester.pumpAndSettle();
        expect(find.text('got: 2'), findsOneWidget);
      },
    );

    testWidgets(
      'should return true if the ScopedFamilyRef is '
      'initialized in the current LiteRefScope',
      (tester) async {
        final countRef = Ref.scopedFamily((ctx, int f) => 0 + f);

        await tester.pumpWidget(
          MaterialApp(
            home: LiteRefScope(
              child: Builder(
                builder: (context) {
                  final initialized1 = countRef.exists(context, 1);
                  final initialized2 = countRef.exists(context, 2);
                  expect(initialized1, false);
                  expect(initialized2, false);

                  final val = countRef.of(context, 1);
                  expect(val, 1);

                  final initialized1After = countRef.exists(context, 1);
                  final initialized2After = countRef.exists(context, 2);
                  expect(initialized1After, true);
                  expect(initialized2After, false);

                  return LiteRefScope(
                    overrides: {
                      countRef.overrideWith((ctx, f) => 10 + f),
                    },
                    child: Builder(
                      builder: (context) {
                        final initialized1 = countRef.exists(context, 1);
                        final initialized2 = countRef.exists(context, 2);
                        expect(initialized1, false);
                        expect(initialized2, false);

                        final val = countRef.of(context, 1);
                        expect(val, 11);

                        final initialized1After = countRef.exists(context, 1);
                        final initialized2After = countRef.exists(context, 2);
                        expect(initialized1After, true);
                        expect(initialized2After, false);

                        return Text('$val');
                      },
                    ),
                  );
                },
              ),
            ),
          ),
        );

        await tester.pumpAndSettle();

        expect(find.text('11'), findsOneWidget);
      },
    );

    testWidgets(
      'LiteRefScope should dispose when all children '
      'are unmounted and it is read in parent',
      (tester) async {
        final disposed = <int>[];
        final countRef = Ref.scopedFamily(
          (ctx, int f) => 0 + f,
          dispose: disposed.add,
        );
        final amount = ValueNotifier(3);

        await tester.pumpWidget(
          MaterialApp(
            home: LiteRefScope(
              child: Column(
                children: [
                  Builder(
                    builder: (context) {
                      return Text('read ${countRef.read(context, 1)}');
                    },
                  ),
                  ListenableBuilder(
                    listenable: amount,
                    builder: (context, snapshot) {
                      return Column(
                        children: [
                          const SizedBox.shrink(),
                          for (var i = 0; i < amount.value; i++)
                            Builder(
                              builder: (context) {
                                final val = countRef(context, 1);
                                expect(val, 1);
                                return Text('$val');
                              },
                            ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        );

        await tester.pumpAndSettle();

        expect(find.text('1'), findsExactly(amount.value));
        expect(find.text('read 1'), findsOneWidget);

        expect(disposed, isEmpty);

        amount.value = 2;

        await tester.pumpAndSettle();

        expect(find.text('1'), findsExactly(amount.value));

        expect(disposed, isEmpty); // still has listeners

        amount.value = 0;

        await tester.pumpAndSettle();

        expect(find.text('1'), findsNothing);

        expect(disposed, [1]); // dispose when all children are unmounted
        expect(find.text('read 1'), findsOneWidget);
      },
    );

    testWidgets(
      'LiteRefScope should NOT dispose when scope '
      'is unmounted and only access was a "read"',
      (tester) async {
        final disposed = <int>[];
        final countRef = Ref.scopedFamily(
          (ctx, int f) => 0 + f,
          dispose: disposed.add,
        );
        final show = ValueNotifier(true);
        await tester.pumpWidget(
          MaterialApp(
            home: LiteRefScope(
              child: ValueListenableBuilder(
                valueListenable: show,
                builder: (__, value, _) {
                  if (!value) return const SizedBox.shrink();
                  return Builder(
                    builder: (context) {
                      final val = countRef.read(context, 1);
                      expect(val, 1);
                      return Text('$val');
                    },
                  );
                },
              ),
            ),
          ),
        );

        await tester.pumpAndSettle();

        expect(find.text('1'), findsOneWidget);
        expect(disposed, isEmpty); // overridden instance should be disposed

        show.value = false;

        await tester.pumpAndSettle();

        expect(disposed, isEmpty);
      },
    );

    testWidgets(
      'LiteRefScope should throw when the scope is marked as onlyOverrides',
      (tester) async {
        final countRef = Ref.scopedFamily((ctx, int f) => 0 + f);

        await tester.pumpWidget(
          MaterialApp(
            home: LiteRefScope(
              onlyOverrides: true,
              child: Builder(
                builder: (context) {
                  late final val = countRef(context, 0);
                  expect(() => val, throwsException);
                  return const Text('1');
                },
              ),
            ),
          ),
        );

        expect(find.text('1'), findsOneWidget);
      },
    );

    testWidgets('LiteRefScope should fetch from the closest scope',
        (tester) async {
      final resourceRef = Ref.scopedFamily((ctx, int f) => _Resource());

      await tester.pumpWidget(
        MaterialApp(
          home: LiteRefScope(
            child: Builder(
              builder: (context) {
                final val = resourceRef(context, 0);
                expect(val.disposed, false);
                val.disposed = true;
                return LiteRefScope(
                  onlyOverrides: true,
                  overrides: {
                    resourceRef.overrideWith((ctx, int _) => _Resource()),
                  },
                  child: Builder(
                    builder: (context) {
                      final val2 = resourceRef(context, 0);
                      expect(val2.disposed, false);
                      return Text('${val2.disposed}');
                    },
                  ),
                );
              },
            ),
          ),
        ),
      );

      expect(find.text('false'), findsOneWidget);
    });

    testWidgets('LiteRefScope should fetch from the closest scope/2 depth',
        (tester) async {
      final resourceRef = Ref.scopedFamily((ctx, int f) => _Resource());

      await tester.pumpWidget(
        MaterialApp(
          home: LiteRefScope(
            child: Builder(
              builder: (context) {
                final val = resourceRef(context, 0);
                expect(val.disposed, false);
                val.disposed = true;
                return LiteRefScope(
                  onlyOverrides: true,
                  overrides: {
                    resourceRef.overrideWith((ctx, _) => _Resource()),
                  },
                  child: Builder(
                    builder: (context) {
                      return LiteRefScope(
                        onlyOverrides: true,
                        child: Builder(
                          builder: (context) {
                            final val2 = resourceRef(context, 0);
                            expect(val2.disposed, false);
                            return Text('${val2.disposed}');
                          },
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ),
      );

      expect(find.text('false'), findsOneWidget);
    });

    testWidgets('LiteRefScope should fetch from the closest scope/3 depth',
        (tester) async {
      final resourceRef = Ref.scopedFamily((ctx, int f) => _Resource());

      await tester.pumpWidget(
        MaterialApp(
          home: LiteRefScope(
            child: Builder(
              builder: (context) {
                final val = resourceRef(context, 0);
                expect(val.disposed, false);
                val.disposed = true;
                return LiteRefScope(
                  onlyOverrides: true,
                  overrides: {
                    resourceRef.overrideWith((ctx, _) => _Resource()),
                  },
                  child: Builder(
                    builder: (context) {
                      return LiteRefScope(
                        onlyOverrides: true,
                        child: Builder(
                          builder: (context) {
                            return LiteRefScope(
                              onlyOverrides: true,
                              child: Builder(
                                builder: (context) {
                                  final val2 = resourceRef(context, 0);
                                  expect(val2.disposed, false);
                                  return Text('${val2.disposed}');
                                },
                              ),
                            );
                          },
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ),
      );

      expect(find.text('false'), findsOneWidget);
    });

    testWidgets(
      'LiteRefScope should fetch from the parent scope when the '
      'closest scope is marked as onlyOverrides',
      (tester) async {
        final resourceRef = Ref.scopedFamily((ctx, int f) => _Resource());

        await tester.pumpWidget(
          MaterialApp(
            home: LiteRefScope(
              child: Builder(
                builder: (context) {
                  final val = resourceRef(context, 0);
                  expect(val.disposed, false);
                  val.disposed = true;
                  return LiteRefScope(
                    onlyOverrides: true,
                    child: Builder(
                      builder: (context) {
                        final val = resourceRef(context, 0);
                        expect(val.disposed, true);
                        return Text('${val.disposed}');
                      },
                    ),
                  );
                },
              ),
            ),
          ),
        );

        expect(find.text('true'), findsOneWidget);
      },
    );
  });
}

class _Controller {
  _Controller({required this.id, this.value = 0});

  final int id;
  int value;
}

class _Dependent {
  const _Dependent(this.resource);

  final _Resource resource;
}

class _Resource implements Disposable {
  bool disposed = false;

  @override
  void dispose() {
    disposed = true;
  }
}
