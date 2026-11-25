import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nym_bar/features/qwdtt/qwdtt_controller.dart';
import 'package:nym_bar/services/api/api_client.dart';

class Bytes {
  Bytes(Socket socket) : iterator = StreamIterator(socket);
  final StreamIterator<Uint8List> iterator;
  final buffer = <int>[];
  Future<List<int>> read(int n) async {
    while (buffer.length < n) {
      if (!await iterator.moveNext()) throw StateError('closed');
      buffer.addAll(iterator.current);
    }
    final result = buffer.sublist(0, n); buffer.removeRange(0, n); return result;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('protected upload goes through SOCKS to the API proxy', () async {
    final dir = await Directory.systemTemp.createTemp('media-socks-test-');
    final cert = '${dir.path}/cert.pem', key = '${dir.path}/key.pem';
    final generated = await Process.run('openssl', ['req','-x509','-newkey','rsa:2048','-nodes','-keyout',key,'-out',cert,'-days','1','-subj','/CN=localhost','-addext','subjectAltName=IP:127.0.0.1']);
    expect(generated.exitCode, 0);
    SecurityContext.defaultContext.setTrustedCertificates(cert);
    final tls = await HttpServer.bindSecure(InternetAddress.loopbackIPv4, 0,
        SecurityContext()..useCertificateChain(cert)..usePrivateKey(key));
    final requestSeen = Completer<void>();
    tls.listen((request) async {
      expect(request.method, 'PUT');
      expect(request.uri.path, '/api/proxy');
      final action = request.uri.queryParameters['action'];
      expect(action, anyOf('upload', 'mirror'));
      expect(request.uri.queryParameters['server'], 'https://blossom.example');
      final body = await request.fold<List<int>>([], (a, b) => a..addAll(b));
      if (action == 'upload') {
        expect(body, [1,2,3]);
      } else {
        expect(String.fromCharCodes(body), '{"url":"https://blossom.example/file"}');
      }
      request.response.write('{"url":"https://blossom.example/file"}');
      await request.response.close(); if (!requestSeen.isCompleted) requestSeen.complete();
    });
    final socks = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final targetSeen = Completer<String>();
    socks.listen((socket) async {
      final reader = Bytes(socket);
      try {
        expect(await reader.read(3), [5,1,2]); socket.add([5,2]); await socket.flush();
        expect(await reader.read(2), [1,1]); await reader.read(1); expect(await reader.read(1), [1]); await reader.read(1);
        socket.add([1,0]); await socket.flush();
        expect(await reader.read(4), [5,1,0,1]);
        final target = (await reader.read(4)).join('.');
        if (!targetSeen.isCompleted) targetSeen.complete(target);
        final portBytes = await reader.read(2); final port = portBytes[0]*256+portBytes[1];
        final upstream = await Socket.connect(InternetAddress.loopbackIPv4, port);
        socket.add([5,0,0,1,127,0,0,1,0,0]); await socket.flush();
        upstream.listen(socket.add, onDone: socket.close);
        while (await reader.iterator.moveNext()) { upstream.add(reader.iterator.current); }
        await upstream.close();
      } catch (_) { socket.destroy(); }
    });
    const channel = MethodChannel('app.panchat/test-media-socks');
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async => {
      'selected': true, 'route': 'TOR', 'state': 'READY', 'generation': 1,
      'socks': {'port': socks.port, 'username': 'u', 'password': 'p'},
    });
    final old = HttpOverrides.current;
    final controller = QwdttController(channel: channel, supported: () => true);
    final api = ApiClient(baseUrl: 'https://127.0.0.1:${tls.port}/api/proxy');
    addTearDown(() async { api.dispose(); controller.dispose(); HttpOverrides.global = old; messenger.setMockMethodCallHandler(channel, null); await socks.close(); await tls.close(force: true); await dir.delete(recursive: true); });
    await controller.initialize();
    final session = controller.beginMediaSession()!;
    addTearDown(session.dispose);
    expect(session.direct, isFalse);
    final result = await api.uploadBlob(Uint8List.fromList([1,2,3]), 'https://blossom.example', 'Nostr test', contentType: 'image/png', mediaSession: session).timeout(const Duration(seconds: 8));
    expect(result['url'], 'https://blossom.example/file');
    await requestSeen.future;
    expect(await targetSeen.future, '127.0.0.1');
    final mirror = await api.mirrorBlob('https://blossom.example/file',
        'https://blossom.example', 'Nostr test', mediaSession: session)
        .timeout(const Duration(seconds: 8));
    expect(mirror['url'], 'https://blossom.example/file');
    session.dispose();
    await expectLater(
      api.mirrorBlob('https://blossom.example/file', 'https://blossom.example',
          'Nostr test', mediaSession: session),
      throwsStateError,
    );
  });
}
