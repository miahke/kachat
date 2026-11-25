import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nym_bar/features/qwdtt/qwdtt_controller.dart';
import 'package:nym_bar/features/qwdtt/routing_gateway.dart';
import 'package:nym_bar/features/messages/media_fallbacks.dart';
import 'package:nym_bar/services/api/api_client.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('local TLS PUT succeeds and a hanging retry is cancelled on timeout', () async {
    final dir = await Directory.systemTemp.createTemp('media-route-test-');
    final cert = '${dir.path}/cert.pem';
    final key = '${dir.path}/key.pem';
    final generated = await Process.run('openssl', ['req','-x509','-newkey','rsa:2048','-nodes','-keyout',key,'-out',cert,'-days','1','-subj','/CN=media.example','-addext','subjectAltName=DNS:media.example']);
    expect(generated.exitCode, 0);
    SecurityContext.defaultContext.setTrustedCertificates(cert);
    final context = SecurityContext()..useCertificateChain(cert)..usePrivateKey(key);
    final server = await HttpServer.bindSecure(InternetAddress.loopbackIPv4, 0, context);
    var count = 0;
    final third = Completer<void>();
    final fourth = Completer<void>();
    server.listen((request) async {
      final body = await request.fold<List<int>>([], (a, b) => a..addAll(b));
      expect(body, [1,2,3]); expect(request.method, 'PUT'); expect(request.uri.path, '/upload');
      count++;
      if (count == 1) { request.response.write('{"url":"https://example.org/file"}'); await request.response.close(); }
      if (count == 3) third.complete();
      if (count == 4) fourth.complete();
    });
    const channel = MethodChannel('app.panchat/test-media-tls');
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async => {'selected': false, 'route': 'DIRECT'});
    final old = HttpOverrides.current;
    final controller = QwdttController(
      channel: channel,
      supported: () => true,
      gatewayFactory: () => RoutingGateway.start(
        resolveMedia: (_) async => [InternetAddress('8.8.8.8')],
        connectMedia: (address, port) =>
            Socket.startConnect(InternetAddress.loopbackIPv4, server.port),
      ),
    );
    final api = ApiClient();
    addTearDown(() async { api.dispose(); controller.dispose(); HttpOverrides.global = old; messenger.setMockMethodCallHandler(channel, null); await server.close(force: true); await dir.delete(recursive: true); });
    await controller.initialize();
    final session = controller.beginMediaSession()!;
    addTearDown(session.dispose);
    final serverUrl = 'https://media.example:${server.port}';
    final result = await api.uploadBlob(Uint8List.fromList([1,2,3]), serverUrl, 'Nostr test', contentType: 'image/png', mediaSession: session);
    expect(result['url'], 'https://example.org/file');
    final uploader = BlossomUploader(hostTimeout: const Duration(milliseconds: 100));
    final failed = await uploader.upload([serverUrl], 'image/png', (server, type) async {
      final result = await api.uploadBlob(Uint8List.fromList([1,2,3]), server, 'Nostr test', contentType: type, mediaSession: session);
      return result['url'] as String?;
    }, onTimeout: session.cancelActive, canContinue: () => session.valid);
    expect(failed, isNull); expect(count, 2);
    final pending = api.uploadBlob(Uint8List.fromList([1,2,3]), serverUrl,
        'Nostr test', contentType: 'image/png', mediaSession: session);
    final cancelled = expectLater(pending, throwsA(anything));
    await third.future.timeout(const Duration(seconds: 5));
    await controller.command('direct');
    await cancelled.timeout(const Duration(seconds: 5));
    expect(session.valid, isFalse);
    final next = controller.beginMediaSession()!;
    addTearDown(next.dispose);
    final pendingDispose = api.uploadBlob(Uint8List.fromList([1,2,3]), serverUrl,
        'Nostr test', contentType: 'image/png', mediaSession: next);
    final cancelledDispose = expectLater(pendingDispose, throwsA(anything));
    await fourth.future.timeout(const Duration(seconds: 5));
    api.dispose();
    await cancelledDispose.timeout(const Duration(seconds: 5));
  });
}
