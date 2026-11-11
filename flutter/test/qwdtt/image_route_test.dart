import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nym_bar/features/messages/routed_image_service.dart';
import 'package:nym_bar/features/qwdtt/qwdtt_controller.dart';
import 'package:nym_bar/features/qwdtt/routing_gateway.dart';
import 'package:nym_bar/services/api/api_config.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('direct media uses pinned gateway, handles redirects and bounded streams, and stops on switching', () async {
    final dir = await Directory.systemTemp.createTemp('image-route-');
    final cert = '${dir.path}/cert.pem', key = '${dir.path}/key.pem';
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
      '/CN=media.example',
      '-addext',
      'subjectAltName=DNS:media.example,DNS:other.example',
    ]);
    expect(generated.exitCode, 0);
    SecurityContext.defaultContext.setTrustedCertificates(cert);
    final server = await HttpServer.bindSecure(
      InternetAddress.loopbackIPv4,
      0,
      SecurityContext()
        ..useCertificateChain(cert)
        ..usePrivateKey(key),
    );
    final seenAuth = Completer<String?>();
    final initialAuth = Completer<String?>();
    final started = Completer<void>();
    server.listen((request) async {
      if (request.uri.path == '/redirect') {
        initialAuth.complete(request.headers.value('authorization'));
        request.response.statusCode = 302;
        request.response.headers.set(
          'location',
          Uri(
            scheme: 'https',
            host: 'other.example',
            port: server.port,
            path: '/result',
          ).toString(),
        );
      } else if (request.uri.path == '/result') {
        seenAuth.complete(request.headers.value('authorization'));
        request.response.add([1, 2, 3]);
      } else if (request.uri.path == '/private') {
        request.response.statusCode = 302;
        request.response.headers.set(
          'location',
          Uri(
            scheme: 'https',
            host: '127.0.0.1',
            port: server.port,
            path: '/',
          ).toString(),
        );
      } else if (request.uri.path == '/unsafe') {
        request.response.statusCode = 302;
        request.response.headers.set('location', 'http://example.com/image');
      } else if (request.uri.path == '/unchanged') {
        request.response.statusCode = 304;
        request.response.headers.set('etag', 'test-tag');
      } else if (request.uri.path == '/stream') {
        request.response.add([1]);
        await request.response.flush();
        started.complete();
        return;
      } else if (request.uri.path == '/large') {
        try {
          for (var i = 0; i < 21; i++) {
            request.response.add(List<int>.filled(1024 * 1024, 1));
            await request.response.flush();
          }
        } catch (_) {}
      }
      await request.response.close();
    });
    const channel = MethodChannel('app.panchat/test-routed-images');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    var snapshot = <String, dynamic>{'selected': false, 'route': 'DIRECT'};
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'connectTor') {
        snapshot = {'selected': true, 'route': 'TOR', 'state': 'STOPPED'};
      }
      if (call.method == 'select' || call.method == 'validateTor') {
        return <String, dynamic>{};
      }
      return snapshot;
    });
    final old = HttpOverrides.current;
    final dials = <String>[];
    final controller = QwdttController(
      channel: channel,
      supported: () => true,
      gatewayFactory: () => RoutingGateway.start(
        resolveMedia: (_) async => [InternetAddress('8.8.8.8')],
        connectMedia: (address, port) {
          dials.add(address.address);
          return Socket.startConnect(InternetAddress.loopbackIPv4, server.port);
        },
      ),
    );
    addTearDown(() async {
      controller.dispose();
      HttpOverrides.global = old;
      messenger.setMockMethodCallHandler(channel, null);
      await server.close(force: true);
      await dir.delete(recursive: true);
    });
    await controller.initialize();
    final service = RoutedImageFileService(controller: controller);
    String url(String path) => Uri.parse(ApiConfig.proxyBaseUrl())
        .replace(
          queryParameters: {
            'url': Uri(
              scheme: 'https',
              host: 'media.example',
              port: server.port,
              path: path,
            ).toString(),
          },
        )
        .toString();
    final image = await service.get(
      url('/redirect'),
      headers: {'Authorization': 'secret'},
    );
    expect(await image.content.expand((e) => e).toList(), [1, 2, 3]);
    expect(await initialAuth.future, isNull);
    expect(await seenAuth.future, isNull);
    expect(dials, ['8.8.8.8', '8.8.8.8']);
    final unchanged = await service.get(url('/unchanged'));
    expect(unchanged.statusCode, 304);
    expect(unchanged.eTag, 'test-tag');
    await expectLater(
      service.get(url('/unsafe')),
      throwsA(isA<HttpException>()),
    );
    await expectLater(service.get(url('/private')), throwsA(anything));
    final large = await service.get(url('/large'));
    await expectLater(
      large.content.drain<void>(),
      throwsA(isA<HttpException>()),
    );
    final streaming = await service.get(url('/stream'));
    final completion = streaming.content.toList();
    await started.future;
    final failed = expectLater(completion, throwsA(anything));
    await controller.command('connectTor');
    await failed.timeout(const Duration(seconds: 5));
    await expectLater(service.get(url('/image')), throwsA(anything));
  });
  test('unwraps only an unambiguous HTTPS image proxy URL', () {
    String proxy(String target) =>
        Uri.parse(ApiConfig.proxyBaseUrl())
            .replace(queryParameters: {'url': target})
            .toString();
    expect(
      directImageTarget(proxy('https://example.org/a'))?.host,
      'example.org',
    );
    expect(directImageTarget(proxy('http://example.org/a')), isNull);
    expect(directImageTarget(proxy('https://user@example.org/a')), isNull);
    expect(
      directImageTarget(
        'https://other.example/api/proxy?url=https%3A%2F%2Fexample.org',
      ),
      isNull,
    );
    expect(
      directImageTarget(
        Uri.parse(ApiConfig.proxyBaseUrl())
            .replace(
              queryParameters: {
                'action': 'unfurl',
                'url': 'https://example.org',
              },
            )
            .toString(),
      ),
      isNull,
    );
    expect(
      directImageTarget(
        Uri.parse(ApiConfig.proxyBaseUrl())
            .replace(
              query: 'url=https%3A%2F%2Fa.example&url=https%3A%2F%2Fb.example',
            )
            .toString(),
      ),
      isNull,
    );
  });
  test(
    'protected routes send remote images to the Nym API via SOCKS',
    () async {
      final socks = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final destination = Completer<String>();
      socks.listen((socket) {
        var phase = 0;
        final buffer = <int>[];
        socket.listen((data) {
          buffer.addAll(data);
          if (phase == 0 && buffer.length >= 3) {
            buffer.clear();
            phase = 1;
            socket.add([5, 0]);
          } else if (phase == 1 &&
              buffer.length >= 5 &&
              buffer[3] == 3 &&
              buffer.length >= 7 + buffer[4]) {
            destination.complete(
              String.fromCharCodes(buffer.sublist(5, 5 + buffer[4])),
            );
            socket.add([5, 1, 0, 1, 0, 0, 0, 0, 0, 0]);
          }
        });
      });
      const channel = MethodChannel('app.panchat/test-protected-image');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
        channel,
        (_) async => {
          'selected': true,
          'route': 'TOR',
          'state': 'READY',
          'generation': 1,
          'socks': {'port': socks.port, 'username': '', 'password': ''},
        },
      );
      final old = HttpOverrides.current;
      final controller = QwdttController(
        channel: channel,
        supported: () => true,
      );
      addTearDown(() async {
        controller.dispose();
        HttpOverrides.global = old;
        messenger.setMockMethodCallHandler(channel, null);
        await socks.close();
      });
      await controller.initialize();
      final service = RoutedImageFileService(controller: controller);
      final failed = expectLater(
        service.get('https://files.example/image.png'),
        throwsA(anything),
      );
      expect(
        await destination.future.timeout(const Duration(seconds: 5)),
        ApiConfig.apiHost,
      );
      await failed.timeout(const Duration(seconds: 5));
    },
  );
}
