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
