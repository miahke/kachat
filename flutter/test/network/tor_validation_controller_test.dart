import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nym_bar/features/qwdtt/qwdtt_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('invalid Tor configuration leaves the current route intact', () async {
    const channel = MethodChannel('test/tor-validation');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final calls = <String>[];
    const snapshot = {'selected': false, 'route': 'DIRECT', 'state': 'STOPPED'};
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      if (call.method == 'validateTor') {
        throw PlatformException(code: 'TOR_BRIDGE', message: 'Invalid bridge');
      }
      return snapshot;
    });
    final original = HttpOverrides.current;
    final controller = QwdttController(channel: channel, supported: () => true);
    addTearDown(() {
      controller.dispose();
      HttpOverrides.global = original;
      messenger.setMockMethodCallHandler(channel, null);
    });
    await controller.initialize();
    var guardCalls = 0;
    controller.registerNativeGuard(() {
      guardCalls++;
    });
    await controller.command('connectTor', {
      'mode': 'WEBTUNNEL',
      'bridges': 'bad',
      'socksPort': 19050,
    });
    expect(controller.route, 'DIRECT');
    expect(controller.nativeNetworkAllowed, isTrue);
    expect(controller.error, 'Invalid bridge');
    expect(guardCalls, 0);
    expect(calls, contains('validateTor'));
    expect(calls, isNot(contains('select')));
    expect(calls, isNot(contains('connectTor')));
  });
  test('valid Tor configuration is checked before route selection', () async {
    const channel = MethodChannel('test/tor-validation-success');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final calls = <String>[];
    var route = 'DIRECT';
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      if (call.method == 'validateTor') return true;
      if (call.method == 'select') route = 'TOR';
      return {'selected': route == 'TOR', 'route': route, 'state': 'STARTING'};
    });
    final original = HttpOverrides.current;
    final controller = QwdttController(channel: channel, supported: () => true);
    addTearDown(() {
      controller.dispose();
      HttpOverrides.global = original;
      messenger.setMockMethodCallHandler(channel, null);
    });
    await controller.initialize();
    await controller.command('connectTor', {
      'mode': 'DIRECT_TOR',
      'bridges': '',
      'socksPort': 19050,
    });
    expect(calls, containsAll(['validateTor', 'select', 'connectTor']));
    expect(calls.indexOf('validateTor'), lessThan(calls.indexOf('select')));
    expect(calls.indexOf('select'), lessThan(calls.indexOf('connectTor')));
    expect(controller.route, 'TOR');
    expect(controller.nativeNetworkAllowed, isFalse);
  });
}
