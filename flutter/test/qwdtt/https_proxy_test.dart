import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nym_bar/features/qwdtt/qwdtt_controller.dart';
import 'package:nym_bar/features/qwdtt/routing_gateway.dart';

void main() {
  test(
    'real HTTPS and WSS retain TLS validation and send domain through SOCKS',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'panchat-tls-test-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final cert = '${directory.path}/cert.pem',
          key = '${directory.path}/key.pem';
      final generated = await Process.run('openssl', [
        'req',
        '-x509',
        '-newkey',
        'rsa:2048',
        '-nodes',
        '-days',
        '1',
        '-keyout',
        key,
        '-out',
        cert,
        '-subj',
        '/CN=relay.example.invalid',
        '-addext',
        'subjectAltName=DNS:relay.example.invalid',
      ]);
      expect(generated.exitCode, 0);
      final context = SecurityContext()
        ..useCertificateChain(cert)
        ..usePrivateKey(key);
      final server = await HttpServer.bindSecure(
        InternetAddress.loopbackIPv4,
        0,
        context,
      );
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        if (WebSocketTransformer.isUpgradeRequest(request)) {
          final ws = await WebSocketTransformer.upgrade(request);
          ws.listen((value) => ws.add(value));
        } else {
          request.response.write('synthetic-response');
          await request.response.close();
        }
      });
      final domains = <String>[];
      final sockets = <Socket>[];
      addTearDown(() {
        for (final s in sockets) {
          s.destroy();
        }
      });
      final proxy = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(proxy.close);
      proxy.listen((socket) async {
        sockets.add(socket);
        final stream = StreamIterator<List<int>>(socket);
        final buffer = <int>[];
        Future<List<int>> read(int n) async {
          while (buffer.length < n) {
            if (!await stream.moveNext()) throw const SocketException('closed');
            buffer.addAll(stream.current);
          }
          final out = buffer.sublist(0, n);
          buffer.removeRange(0, n);
          return out;
        }

        Socket? remote;
        try {
          expect(await read(3), [5, 1, 2]);
          socket.add([5, 2]);
          await socket.flush();
          final auth = await read(2);
          await read(auth[1]);
          await read((await read(1))[0]);
          socket.add([1, 0]);
          await socket.flush();
          expect(await read(4), [5, 1, 0, 3]);
          domains.add(utf8.decode(await read((await read(1))[0])));
          await read(2);
          remote = await Socket.connect(
            InternetAddress.loopbackIPv4,
            server.port,
          );
          sockets.add(remote);
          socket.add([5, 0, 0, 1, 127, 0, 0, 1, 0, 0]);
          await socket.flush();
          remote.listen(
            socket.add,
            onDone: socket.destroy,
            onError: (_) => socket.destroy(),
          );
          if (buffer.isNotEmpty) remote.add(buffer);
          while (await stream.moveNext()) {
            remote.add(stream.current);
            await remote.flush();
          }
        } catch (_) {
          /* TLS rejection closes both ends. */
        } finally {
          remote?.destroy();
          socket.destroy();
          await stream.cancel();
        }
      });
      final gateway = await RoutingGateway.start();
      addTearDown(gateway.dispose);
      gateway.useSocks(SocksTarget(proxy.port, 'synthetic', 'secret'));
      final trusted = SecurityContext(withTrustedRoots: false)
        ..setTrustedCertificates(cert);
      final client = QwdttHttpOverrides(gateway).createHttpClient(trusted);
      addTearDown(() => client.close(force: true));
      final request = await client
          .getUrl(Uri.parse('https://relay.example.invalid/'))
          .timeout(const Duration(seconds: 5));
      final response = await request.close().timeout(
        const Duration(seconds: 5),
      );
      expect(await utf8.decoder.bind(response).join(), 'synthetic-response');
      final ws = await WebSocket.connect(
        'wss://relay.example.invalid/echo',
        customClient: client,
      ).timeout(const Duration(seconds: 5));
      ws.add('synthetic-ping');
      expect(await ws.first, 'synthetic-ping');
      await ws.close();
      expect(domains, everyElement('relay.example.invalid'));
      expect(domains.length, greaterThanOrEqualTo(2));
      final untrusted = QwdttHttpOverrides(gateway)
          .createHttpClient(SecurityContext(withTrustedRoots: false));
      addTearDown(() => untrusted.close(force: true));
      await expectLater(() async {
        final r = await untrusted.getUrl(
          Uri.parse('https://relay.example.invalid/'),
        );
        await r.close();
      }, throwsA(isA<HandshakeException>()));
      gateway.block();
      await expectLater(() async {
        final r = await client.getUrl(
          Uri.parse('https://relay.example.invalid/'),
        );
        await r.close();
      }, throwsA(anything));
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );
}
