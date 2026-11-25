import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nym_bar/features/qwdtt/qwdtt_controller.dart';
import 'package:nym_bar/features/qwdtt/routing_gateway.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('media credentials expire across each route transition', () async {
    final gateway = await RoutingGateway.start();
    addTearDown(gateway.dispose);
    Future<void> rejected(String credential) async {
      final socket = await Socket.connect(InternetAddress.loopbackIPv4, gateway.port);
      final auth = base64.encode(utf8.encode('${gateway.username}:$credential'));
      socket.write('CONNECT example.invalid:443 HTTP/1.1\r\nProxy-Authorization: Basic $auth\r\n\r\n');
      expect(await utf8.decoder.bind(socket).join().timeout(const Duration(seconds: 3)), startsWith('HTTP/1.1 407'));
    }
    gateway.useDirect();
    final direct = gateway.mediaCredential()!;
    gateway.useSocks(SocksTarget(1234, '', ''));
    await rejected(direct);
    final socks = gateway.mediaCredential()!;
    gateway.useDirect();
    await rejected(socks);
    gateway.useSocks(SocksTarget(1234, '', ''));
    final socks2 = gateway.mediaCredential()!;
    gateway.useSocks(SocksTarget(1235, '', ''));
    await rejected(socks2);
  });
  test('switch invalidates upload session before Tor validation and keeps route on invalid config', () async {
    const channel = MethodChannel('app.panchat/test-upload-session');
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final validation = Completer<void>();
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'validateTor') { await validation.future; throw PlatformException(code: 'TOR_BRIDGE'); }
      return {'selected': false, 'route': 'DIRECT'};
    });
    final old = HttpOverrides.current;
    final controller = QwdttController(channel: channel, supported: () => true);
    addTearDown(() { controller.dispose(); HttpOverrides.global = old; messenger.setMockMethodCallHandler(channel, null); });
    expect(controller.beginMediaSession(), isNull);
    await controller.initialize();
    final session = controller.beginMediaSession()!;
    expect(session.direct, isTrue);
    final client = session.createClient();
    final switching = controller.command('connectTor');
    expect(session.valid, isFalse);
    expect(controller.beginMediaSession(), isNull);
    expect(() => session.createClient(), throwsStateError);
    validation.complete();
    await switching;
    final next = controller.beginMediaSession();
    expect(next?.direct, isTrue);
    client.close(force: true); session.dispose(); next?.dispose();
  });
}
