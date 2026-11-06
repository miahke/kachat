import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nym_bar/features/qwdtt/qwdtt_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('app.panchat/test-qwdtt');
  test('reported route stays unknown until a native route is received', () async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      throw PlatformException(code: 'synthetic_failure');
    });
    final original = HttpOverrides.current;
    final controller = QwdttController(channel: channel, supported: () => true);
    addTearDown(() {
      controller.dispose();
      HttpOverrides.global = original;
      messenger.setMockMethodCallHandler(channel, null);
    });
    expect(controller.reportedRoute, isNull);
    await controller.initialize();
    expect(controller.reportedRoute, isNull);
    expect(controller.state, 'ERROR');
    expect(controller.nativeNetworkAllowed, isFalse);
  });
  test(
    'cancelled captcha stops the protected route without direct fallback',
    () async {
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      var pending = true;
      final methods = <String>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        methods.add(call.method);
        if (call.method == 'solveCaptcha') {
          throw PlatformException(
            code: 'VK_CONFIRMATION',
            message: 'Проверка VK отменена.',
          );
        }
        if (call.method == 'disconnect') pending = false;
        return {
          'selected': true,
          'route': 'VK',
          'state': pending ? 'STARTING' : 'STOPPED',
          if (pending) 'captcha': {'id': 'synthetic'},
        };
      });
      final original = HttpOverrides.current;
      final c = QwdttController(channel: channel, supported: () => true);
      addTearDown(() {
        c.dispose();
        HttpOverrides.global = original;
        messenger.setMockMethodCallHandler(channel, null);
      });
      await c.initialize();
      await c.solveCaptcha();
      expect(methods, contains('disconnect'));
      expect(methods, isNot(contains('direct')));
      expect(c.selected, true);
      expect(c.nativeNetworkAllowed, false);
      expect(c.state, 'STOPPED');
    },
  );
  test('unchanged status polls do not rebuild settings but changed state still notifies', () async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    var state = 'STOPPED';
    messenger.setMockMethodCallHandler(
      channel,
      (call) async => {
        'selected': true,
        'state': state,
        'profiles': <Object>[],
      },
    );
    final original = HttpOverrides.current;
    final controller = QwdttController(channel: channel, supported: () => true);
    addTearDown(() {
      controller.dispose();
      HttpOverrides.global = original;
      messenger.setMockMethodCallHandler(channel, null);
    });
    await controller.initialize();
    var notifications = 0;
    controller.addListener(() {
      notifications++;
    });
    for (var i = 0; i < 20; i++) {
      await controller.refresh();
    }
    expect(notifications, 0);
    expect(controller.nativeNetworkAllowed, false);
    state = 'ERROR';
    await controller.refresh();
    expect(notifications, 1);
    expect(controller.state, 'ERROR');
    expect(controller.nativeNetworkAllowed, false);
  });
  test('late snapshot failure cannot undo explicit direct selection', () async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final started = Completer<void>();
    final stale = Completer<Map<String, dynamic>>();
    messenger.setMockMethodCallHandler(channel, (call) async {
      switch (call.method) {
        case 'initialize':
          return {'selected': true, 'state': 'STOPPED'};
        case 'snapshot':
          started.complete();
          return stale.future;
        case 'direct':
          return {'selected': false, 'state': 'STOPPED'};
        default:
          throw StateError('Unexpected method');
      }
    });
    final original = HttpOverrides.current;
    final controller = QwdttController(channel: channel, supported: () => true);
    addTearDown(() {
      controller.dispose();
      HttpOverrides.global = original;
      messenger.setMockMethodCallHandler(channel, null);
    });
    await controller.initialize();
    final pending = controller.refresh();
    await started.future;
    await controller.command('direct');
    stale.completeError(PlatformException(code: 'synthetic_snapshot_failure'));
    await pending;
    expect(controller.selected, false);
    expect(controller.nativeNetworkAllowed, true);
  });
  test(
    'late DIRECT snapshot cannot undo a completed qWDTT selection',
    () async {
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      final snapshotStarted = Completer<void>();
      final staleSnapshot = Completer<Map<String, dynamic>>();
      messenger.setMockMethodCallHandler(channel, (call) async {
        switch (call.method) {
          case 'initialize':
            return {'selected': false, 'state': 'STOPPED'};
          case 'snapshot':
            snapshotStarted.complete();
            return staleSnapshot.future;
          case 'select':
            return null;
          case 'connect':
            return {'selected': true, 'state': 'STARTING'};
          default:
            throw StateError('Unexpected method');
        }
      });
      final originalOverrides = HttpOverrides.current;
      final controller = QwdttController(
        channel: channel,
        supported: () => true,
      );
      addTearDown(() {
        controller.dispose();
        HttpOverrides.global = originalOverrides;
        messenger.setMockMethodCallHandler(channel, null);
      });
      await controller.initialize();
      final pending = controller.refresh();
      await snapshotStarted.future;
      await controller.command('connect', {'id': 'synthetic'});
      expect(controller.selected, true);
      staleSnapshot.complete({'selected': false, 'state': 'STOPPED'});
      await pending;
      expect(controller.selected, true);
      expect(controller.nativeNetworkAllowed, false);
    },
  );
  test(
    'selection persists before guards and guard failure releases busy state',
    () async {
      final order = <String>[];
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (call) async {
        order.add(call.method);
        return {'selected': true, 'state': 'STOPPED', 'profiles': []};
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      final controller = QwdttController(channel: channel);
      addTearDown(controller.dispose);
      Future<void> guard() async {
        order.add('guard');
        throw StateError('synthetic failure');
      }

      controller.registerNativeGuard(guard);
      await controller.command('connect', {'id': 'synthetic'});
      expect(order, ['select', 'guard']);
      expect(controller.busy, false);
      expect(controller.selected, true);
      expect(controller.error, isNotNull);
      controller.unregisterNativeGuard(guard);
      await controller.command('connect', {'id': 'synthetic'});
      expect(order, ['select', 'guard', 'select', 'connect']);
      expect(controller.busy, false);
    },
  );
  test(
    'editing inactive profiles does not select a tunnel or stop native work',
    () async {
      var guarded = false;
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
        channel,
        (call) async => {'selected': false, 'state': 'STOPPED', 'profiles': []},
      );
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      final controller = QwdttController(channel: channel);
      addTearDown(controller.dispose);
      controller.registerNativeGuard(() {
        guarded = true;
      });
      await controller.command('save', {'profile': 'synthetic'});
      expect(controller.selected, false);
      expect(guarded, false);
    },
  );
}
