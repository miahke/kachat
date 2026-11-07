import 'dart:async';
import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nym_bar/models/nostr_event.dart';
import 'package:nym_bar/services/relay/dm_outbox.dart';
import 'package:nym_bar/services/relay/relay_connection.dart';
import 'package:nym_bar/services/relay/relay_pool_proxy.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class FakeSink implements WebSocketSink {
  final frames = <dynamic>[];
  @override
  void add(dynamic data) => frames.add(data);
  @override
  Future<void> close([int? closeCode, String? closeReason]) async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeSocket implements WebSocketChannel {
  final incoming = StreamController<dynamic>();
  @override
  final sink = FakeSink();
  @override
  Stream<dynamic> get stream => incoming.stream;
  @override
  Future<void> get ready => Future.value();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

NostrEvent event() => NostrEvent(id: 'x', pubkey: 'a', createdAt: 1, kind: 1);

void main() {
  test('concurrent publishes both complete on timeout', () {
    fakeAsync((clock) {
      final socket = FakeSocket();
      final connection = RelayConnection(
        'wss://relay.example',
        channelFactory: (_) => socket,
        publishTimeout: const Duration(seconds: 1),
      );
      connection.connect();
      clock.flushMicrotasks();
      final results = <dynamic>[];
      connection.publish(event()).then(results.add);
      connection.publish(event()).then(results.add);
      clock.elapse(const Duration(seconds: 1));
      expect(results.length, 2);
      expect(
        results.every((r) => !r.accepted && r.message == 'timeout'),
        isTrue,
      );
      connection.close();
      clock.flushMicrotasks();
    });
  });

  test('proxy delivers copies to each subscription only once', () {
    fakeAsync((clock) {
      final sockets = <FakeSocket>[];
      final pool = RelayPoolProxy(
        relays: ['wss://relay.example'],
        dmRelays: [],
        channelFactory: (_) {
          final socket = FakeSocket();
          sockets.add(socket);
          return socket;
        },
      );
      pool.connectAll();
      clock.flushMicrotasks();
      final first = pool.subscribe([], subId: 'first');
      final second = pool.subscribe([], subId: 'second');
      var firstCount = 0;
      var secondCount = 0;
      first.events.listen((_) => firstCount++);
      second.events.listen((_) => secondCount++);
      for (final id in ['first', 'first', 'second']) {
        sockets.first.incoming.add(jsonEncode(['EVENT', id, event().toJson()]));
      }
      clock.flushMicrotasks();
      expect(firstCount, 1);
      expect(secondCount, 1);
      first.close();
      clock.flushMicrotasks();
      final replacement = pool.subscribe([], subId: 'first');
      var replacementCount = 0;
      replacement.events.listen((_) => replacementCount++);
      sockets.first.incoming.add(
        jsonEncode(['EVENT', 'first', event().toJson()]),
      );
      clock.flushMicrotasks();
      expect(replacementCount, 1);
      pool.disconnectAll();
      clock.flushMicrotasks();
    });
  });

  test('outbox stops retrying when no relay accepts a send', () {
    fakeAsync((clock) {
      final fakeNow = clock.getClock(DateTime(2026, 1, 1));
      var sends = 0;
      final outbox = DmOutbox(
        send: (_) async {
          sends++;
          return 0;
        },
        now: fakeNow.now,
        retryWait: const Duration(seconds: 2),
        maxTries: 3,
      );
      outbox.push(event());
      clock.elapse(const Duration(minutes: 5));
      expect(sends, 4);
      expect(outbox.failed, 1);
      expect(outbox.length, 0);
      expect(outbox.unsentCount, 0);
      outbox.dispose();
    });
  });

  test('outbox retries successfully after transport recovery', () {
    fakeAsync((clock) {
      final fakeNow = clock.getClock(DateTime(2026, 1, 1));
      var sends = 0;
      final outbox = DmOutbox(
        send: (_) async {
          sends++;
          return sends < 3 ? 0 : 1;
        },
        now: fakeNow.now,
        retryWait: const Duration(seconds: 2),
        maxTries: 3,
      );
      outbox.push(event());
      clock.flushMicrotasks();
      clock.elapse(const Duration(seconds: 4));
      expect(sends, 3);
      expect(outbox.failed, 0);
      expect(outbox.unsentCount, 1);
      outbox.dispose();
    });
  });
}
