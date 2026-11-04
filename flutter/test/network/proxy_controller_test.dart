import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nym_bar/features/qwdtt/qwdtt_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('external proxy selection persists before connect and keeps native bypass blocked', () async {
    const channel = MethodChannel('test/external-proxy');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final calls = <String>[];
    final config = {
      'type': 'HTTP',
      'host': 'proxy.example',
      'port': 8080,
      'username': '',
      'password': '',
    };
    var phase = 'STOPPED';
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      if (call.method == 'select') {
        expect((call.arguments as Map)['route'], 'PROXY');
      }
      if (call.method == 'connectProxy') phase = 'READY';
      if (call.method == 'disconnect') phase = 'STOPPED';
      return {
        'selected': true,
        'route': 'PROXY',
        'state': phase,
        'generation': 1,
        if (phase == 'READY') 'proxy': config,
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
    await c.command('connectProxy', config);
    expect(c.route, 'PROXY');
    expect(c.state, 'READY');
    expect(c.nativeNetworkAllowed, false);
    expect(calls.indexOf('select'), lessThan(calls.indexOf('connectProxy')));
    await c.command('disconnect');
    expect(c.selected, true);
    expect(c.nativeNetworkAllowed, false);
    expect(calls, isNot(contains('direct')));
  });
}
