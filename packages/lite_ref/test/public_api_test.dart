// A consumer fixture for the refactor: it imports only the public entry point
// (plus Flutter itself) so the implementation cannot rely on library-private
// access that real users do not have.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lite_ref/lite_ref.dart';

void main() {
  test('ScopedObject exposes its configured lifetime', () {
    final cached = ScopedObject<int>(id: Object(), instance: 1);
    final retained = ScopedObject<int>(
      id: Object(),
      instance: 2,
      autoDispose: false,
    );
    final callerOwned = ScopedObject<int>(
      id: Object(),
      instance: 3,
      owned: false,
    );

    expect(cached.autoDispose, isTrue);
    expect(retained.autoDispose, isFalse);
    // The public constructor keeps the lifetime it was given, even though an
    // externally owned value can never be disowned by a scope.
    expect(callerOwned.autoDispose, isTrue);
  });

  test('refs expose and preserve their auto-dispose policy', () {
    final retained = Ref.scoped((_) => 1, autoDispose: false);
    expect(retained.autoDispose, isFalse);

    final retainedOverride = retained.overrideWith(
      (_) => 2,
      autoDispose: false,
    );
    expect(retainedOverride.autoDispose, isFalse);

    final callerOwned = retained.overrideWithValue(3);
    expect(callerOwned.autoDispose, isFalse);

    // Re-overriding a caller-owned ref creates a scope-owned value with no
    // disposer to carry over.
    final reOverridden = callerOwned.overrideWith((_) => 4);
    expect(reOverridden.autoDispose, isTrue);

    final family = Ref.scopedFamily<int, int>((_, family) => family);
    expect(family.autoDispose, isTrue);

    final retainedFamily = family.overrideWith(
      (_, family) => family,
      autoDispose: false,
    );
    expect(retainedFamily.autoDispose, isFalse);
  });

  testWidgets('the public workflow resolves a scoped value', (tester) async {
    var creations = 0;
    final countRef = Ref.scoped((_) => ++creations);

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: LiteRefScope(child: _Consumer(countRef)),
      ),
    );

    expect(find.text('value: 1'), findsOneWidget);
    expect(creations, 1);
  });

  testWidgets('a null family argument is a valid key', (tester) async {
    final familyRef = Ref.scopedFamily<int, String?>((_, family) {
      return family == null ? 1 : family.length;
    });

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: LiteRefScope(
          child: Builder(
            builder: (context) {
              return Column(
                children: [
                  Text('null: ${familyRef(context, null)}'),
                  Text('one: ${familyRef(context, 'one')}'),
                ],
              );
            },
          ),
        ),
      ),
    );

    expect(find.text('null: 1'), findsOneWidget);
    expect(find.text('one: 3'), findsOneWidget);
  });

  testWidgets(
    'a factory lookup through a captured context records a dependency',
    (tester) async {
      final disposed = <int>[];
      final show = ValueNotifier(true);
      late BuildContext captured;
      final sourceRef = Ref.scoped((_) => 1, dispose: disposed.add);
      final dependentRef = Ref.scoped<int>((_) => sourceRef(captured));

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: LiteRefScope(
            child: Builder(
              builder: (context) {
                captured = context;
                return ListenableBuilder(
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
                );
              },
            ),
          ),
        ),
      );

      expect(find.text('visible'), findsOneWidget);

      show.value = false;
      await tester.pumpAndSettle();

      expect(find.text('hidden'), findsOneWidget);
      // The factory resolved its dependency through a different context, so
      // it must still be released with the dependent object.
      expect(disposed, [1]);
    },
  );

  testWidgets(
    'removing a dependent from one scope keeps other scope bindings',
    (tester) async {
      final disposed = <int>[];
      final aRef = Ref.scoped((_) => 0, dispose: disposed.add);
      final bRef = Ref.scoped((_) => 0, dispose: disposed.add);
      final current = ValueNotifier(false);
      final rebuild = ValueNotifier(0);
      final innerKey = GlobalKey();
      final consumerKey = GlobalKey();

      final aRootOverride = aRef.overrideWith((_) => 1);
      final aInnerOverride = aRef.overrideWith((_) => 2);
      final bInnerOverride = bRef.overrideWith((_) => 10);

      final consumer = ListenableBuilder(
        key: consumerKey,
        listenable: rebuild,
        builder: (context, _) {
          return Column(
            children: [
              Text('a ${aRef(context)}'),
              Text('b ${bRef(context)}'),
            ],
          );
        },
      );

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: LiteRefScope(
            overrides: {aRootOverride},
            child: ListenableBuilder(
              listenable: current,
              builder: (context, _) {
                return LiteRefScope(
                  key: innerKey,
                  onlyOverrides: true,
                  overrides: {
                    bInnerOverride,
                    if (current.value) aInnerOverride,
                  },
                  child: consumer,
                );
              },
            ),
          ),
        ),
      );

      expect(find.text('a 1'), findsOneWidget);
      expect(find.text('b 10'), findsOneWidget);

      final innerElement =
          tester.element(find.byKey(innerKey)) as InheritedElement;
      final consumerElement = tester.element(find.byKey(consumerKey));
      // Simulate one scope losing the dependent while another keeps it. The
      // framework normally does this while deactivating a subtree.
      // ignore: invalid_use_of_protected_member
      innerElement.removeDependent(consumerElement);

      current.value = true;
      rebuild.value++;
      await tester.pumpAndSettle();

      expect(find.text('a 2'), findsOneWidget);
      // Only the inner scope lost the dependent; the outer binding must still
      // be known so switching to the inner override releases it.
      expect(disposed, [1]);
    },
  );

  testWidgets(
    'a failed factory releases the dependencies it acquired',
    (tester) async {
      final resource = _Resource();
      final resourceRef = Ref.scoped((_) => resource);
      final failingRef = Ref.scoped<int>((context) {
        resourceRef(context);
        throw StateError('factory failed');
      });

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: LiteRefScope(
            child: Builder(
              builder: (context) {
                expect(() => failingRef(context), throwsStateError);
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
}

class _Consumer extends StatelessWidget {
  const _Consumer(this.ref);

  final ScopedRef<int> ref;

  @override
  Widget build(BuildContext context) {
    return Text('value: ${ref(context)}');
  }
}

class _Resource implements Disposable {
  bool disposed = false;

  @override
  void dispose() {
    disposed = true;
  }
}
