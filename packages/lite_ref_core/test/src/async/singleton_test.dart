import 'dart:async';

import 'package:lite_ref_core/lite_ref_core.dart';
import 'package:test/test.dart';

import '../common.dart';

const k10ms = Duration(milliseconds: 10);

void main() {
  test('returns cached instance', () async {
    final asyncRef = Ref.asyncSingleton<Point>(
      () async => Point(1, 2),
    );

    expect(asyncRef.hasInstance, isFalse);

    final firstInstance = await asyncRef();
    final secondInstance = await asyncRef();

    expect(firstInstance == secondInstance, isTrue);

    expect(asyncRef.hasInstance, isTrue);

    expect(asyncRef.assertInstance == firstInstance, isTrue);
  });

  test('returns same instance with race condition', () async {
    var count = 0;
    final asyncRef = Ref.asyncSingleton<Point>(
      () async {
        count++;
        await Future<void>.delayed(k10ms * count);
        return Point(1, 2);
      },
    );

    final (firstInstance, secondInstance) =
        await (asyncRef.instance, asyncRef.instance).wait;

    expect(firstInstance == secondInstance, isTrue);
  });

  test('should override with new create function', () async {
    final asyncRef = Ref.asyncSingleton<Point>(() async => Point(1, 2));

    final firstInstance = await asyncRef();
    expect(firstInstance.x, 1);

    await asyncRef.overrideWith(() async {
      return Point(3, 4);
    });

    final secondInstance = await asyncRef();
    expect(secondInstance.x, 3);
  });

  test('return new instance when overriding fails', () async {
    final asyncRef = Ref.asyncSingleton<Point>(
      () async {
        return Point(1, 2);
      },
    );

    final firstInstance = await asyncRef();
    expect(firstInstance.x, 1);

    var count = 0;

    await expectLater(
      () async => asyncRef.overrideWith(() async {
        count++;
        if (count == 1) throw Exception('Crashed $count');
        return Point(3, 4);
      }),
      throwsException,
    );

    expect(asyncRef.hasInstance, isFalse);

    final secondInstance = await asyncRef();

    expect(secondInstance.x, 3);

    expect(count, 2);
  });

  test('should throw when overriding frozen ref', () async {
    final asyncRef = Ref.asyncSingleton<Point>(() async => Point(1, 2));

    final firstInstance = await asyncRef();
    expect(firstInstance.x, 1);

    await asyncRef.overrideWith(() async {
      return Point(3, 4);
    });

    final secondInstance = await asyncRef();
    expect(secondInstance.x, 3);

    asyncRef.freeze();

    expect(
      () async => asyncRef.overrideWith(() async => Point(5, 6)),
      throwsStateError,
    );
  });

  test('should work with uninitialized ref', () async {
    late final AsyncSingletonRef<Point> asyncRef1;

    final asyncRef2 = Ref.asyncSingleton<Point>(
      () async {
        final yValue = (await asyncRef1()).y;
        return Point(1, yValue);
      },
    );

    asyncRef1 = Ref.asyncSingleton<Point>(() async {
      return Point(5, 6);
    });

    final ref1Instance = await asyncRef1();
    final ref2Instance = await asyncRef2();

    expect(ref1Instance.x, 5);
    expect(ref1Instance.y, 6);
    expect(ref2Instance.x, 1);
    expect(ref2Instance.y, 6);
  });

  test('should rerun create function if it crashed', () async {
    var count = 0;
    final asyncRef = Ref.asyncSingleton<Point>(
      () async {
        count++;
        if (count == 1) {
          throw Exception('Crashed $count');
        }
        return Point(1, 2);
      },
    );

    await expectLater(asyncRef.call, throwsException);

    expect(count, 1);

    expect(asyncRef.hasInstance, isFalse);

    expect(() => asyncRef.assertInstance, throwsStateError);

    final instance = await asyncRef();
    expect(instance.x, 1);
    expect(instance.y, 2);

    expect(count, 2);

    final secondInstance = await asyncRef();

    expect(instance == secondInstance, isTrue);

    expect(count, 2);
  });

  test('concurrent retries create a single instance', () async {
    var count = 0;
    final asyncRef = Ref.asyncSingleton<Point>(
      () async {
        count++;
        await Future<void>.delayed(k10ms);
        if (count == 1) throw Exception('Crashed $count');
        return Point(count, count);
      },
    );

    // Start the failing creation, then pile up waiters on its lock.
    final first = asyncRef.instance;
    final waiters = [asyncRef.instance, asyncRef.instance, asyncRef.instance];

    await expectLater(first, throwsException);
    final results = await Future.wait(waiters);

    // Only one retry should have run even though three callers were waiting.
    expect(count, 2);
    expect(results.every((p) => identical(p, results.first)), isTrue);
    expect(results.first.x, 2);
  });

  test('reading during override does not run the replacement factory twice',
      () async {
    final asyncRef = Ref.asyncSingleton<Point>(() async => Point(1, 2));
    await asyncRef();

    var count = 0;
    final gate = Completer<void>();
    final override = asyncRef.overrideWith(() async {
      count++;
      await gate.future;
      return Point(3, 4);
    });

    // This read must wait on the override's creation, not start a new one.
    final read = asyncRef.instance;

    gate.complete();
    await override;
    final instance = await read;

    expect(count, 1);
    expect(instance.x, 3);
  });

  test('override during initial creation uses the replacement factory',
      () async {
    var oldCount = 0;
    var newCount = 0;
    final gate = Completer<void>();
    final asyncRef = Ref.asyncSingleton<Point>(
      () async {
        oldCount++;
        await gate.future;
        return Point(1, 2);
      },
    );

    final first = asyncRef.instance;
    final override = asyncRef.overrideWith(() async {
      newCount++;
      return Point(3, 4);
    });

    gate.complete();
    await override;
    await first;

    final instance = await asyncRef.instance;

    // The original result must be discarded in favour of the replacement.
    expect(oldCount, 1);
    expect(newCount, 1);
    expect(instance.x, 3);
  });
}
