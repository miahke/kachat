import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nym_bar/models/nostr_event.dart';
import 'package:nym_bar/services/relay/dm_outbox.dart';

NostrEvent event() =>
    NostrEvent(id: 'x', pubkey: 'a', createdAt: 1, kind: 1059);

void main() {
  test('missing confirmation retries with backoff and stops at the limit', () {
    fakeAsync((clock) {
      var sends = 0;
      final outbox = DmOutbox(
        send: (_) async {
          sends++;
          return 1;
        },
        confirmationTimeout: const Duration(seconds: 1),
        maxConfirmationRetries: 2,
      );
      outbox.push(event());
      clock.flushMicrotasks();
      expect(sends, 1);
      clock.elapse(const Duration(seconds: 1));
      expect(sends, 2);
      clock.elapse(const Duration(seconds: 2));
      expect(sends, 3);
      clock.elapse(const Duration(seconds: 4));
      expect(sends, 3);
      expect(outbox.failed, 1);
      outbox.dispose();
    });
  });

  test('acceptance cancels pending retry', () {
    fakeAsync((clock) {
      var sends = 0;
      final outbox = DmOutbox(
        send: (_) async {
          sends++;
          return 1;
        },
        confirmationTimeout: const Duration(seconds: 1),
      );
      outbox.push(event());
      clock.flushMicrotasks();
      outbox.confirm('x');
      clock.elapse(const Duration(seconds: 30));
      expect(sends, 1);
      expect(outbox.unsentCount, 0);
      outbox.dispose();
    });
  });
  test('acceptance arriving before socket write completes prevents retry', () {
    fakeAsync((clock) {
      final result = Completer<int>();
      var sends = 0;
      final outbox = DmOutbox(
        send: (_) {
          sends++;
          return result.future;
        },
        confirmationTimeout: const Duration(seconds: 1),
      );
      outbox.push(event());
      outbox.confirm('x');
      result.complete(1);
      clock.flushMicrotasks();
      clock.elapse(const Duration(seconds: 30));
      expect(sends, 1);
      expect(outbox.failed, 0);
      outbox.dispose();
    });
  });
  test('zero sends stop after bounded retries', () {
    fakeAsync((clock) {
      var sends = 0;
      final outbox = DmOutbox(
        send: (_) async {
          sends++;
          return 0;
        },
        now: () =>
            DateTime.fromMillisecondsSinceEpoch(clock.elapsed.inMilliseconds),
        maxTries: 2,
        retryWait: const Duration(seconds: 1),
      );
      outbox.push(event());
      clock.flushMicrotasks();
      clock.elapse(const Duration(seconds: 10));
      expect(sends, 3);
      expect(outbox.failed, 1);
      expect(outbox.unsentCount, 0);
      outbox.dispose();
    });
  });

  test('duplicate push while send is in flight is ignored', () {
    fakeAsync((clock) {
      final result = Completer<int>();
      var sends = 0;
      final outbox = DmOutbox(
        send: (_) {
          sends++;
          return result.future;
        },
      );
      outbox.push(event());
      outbox.push(event());
      expect(sends, 1);
      result.complete(1);
      clock.flushMicrotasks();
      outbox.confirm('x');
      expect(outbox.unsentCount, 0);
      outbox.dispose();
    });
  });
}
