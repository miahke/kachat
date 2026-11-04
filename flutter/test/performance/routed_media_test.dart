import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:nym_bar/features/qwdtt/routed_media.dart';

class _Paths extends PathProviderPlatform {
  _Paths(this.path);
  final String path;
  @override
  Future<String?> getTemporaryPath() async => path;
}

class _LocalTls extends HttpOverrides {
  _LocalTls(this.port);
  final int port;
  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      super.createHttpClient(context)
        ..badCertificateCallback = ((cert, host, p) =>
            host == '127.0.0.1' && p == port);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('media queue deduplicates pending requests, bounds concurrency and rejects oversized responses', () async {
    final directory = await Directory.systemTemp.createTemp(
      'kachat-media-test-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final previous = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _Paths(directory.path);
    addTearDown(() => PathProviderPlatform.instance = previous);
    final cert = '${directory.path}/cert.pem',
        key = '${directory.path}/key.pem';
    final process = await Process.run('openssl', [
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
      '/CN=localhost',
    ]);
    expect(process.exitCode, 0);
    final server = await HttpServer.bindSecure(
      InternetAddress.loopbackIPv4,
      0,
      SecurityContext()
        ..useCertificateChain(cert)
        ..usePrivateKey(key),
    );
    addTearDown(() => server.close(force: true));
    var active = 0, maximum = 0;
    final counts = <String, int>{};
    server.listen((request) async {
      active++;
      if (active > maximum) maximum = active;
      counts.update(request.uri.path, (n) => n + 1, ifAbsent: () => 1);
      try {
        if (request.uri.path == '/oversized') {
          request.response.contentLength = RoutedMedia.maximumBytes + 1;
          await request.response.flush();
          await request.response.close();
        } else {
          for (var i = 0; i < 3; i++) {
            request.response.add([1, 2, 3, 4]);
            await request.response.flush();
            await Future<void>.delayed(const Duration(milliseconds: 2));
          }
          await request.response.close();
        }
      } catch (_) {
        /* The oversized fixture is intentionally terminated early. */
      } finally {
        active--;
      }
    });
    await HttpOverrides.runWithHttpOverrides(() async {
      final base = 'https://127.0.0.1:${server.port}';
      final all = await Future.wait([
        for (var i = 0; i < 40; i++) RoutedMedia.file('$base/shared'),
        for (var i = 0; i < 20; i++) RoutedMedia.file('$base/unique-$i'),
      ]);
      expect(counts['/shared'], 1);
      expect(maximum, lessThanOrEqualTo(2));
      expect(all.take(40).map((f) => f.path).toSet().length, 1);
      for (final f in all) {
        expect(await f.readAsBytes(), [1, 2, 3, 4, 1, 2, 3, 4, 1, 2, 3, 4]);
      }
      final cache = Directory('${directory.path}/panchat-routed-media');
      final before = await cache.list().length;
      await expectLater(
        RoutedMedia.file('$base/oversized'),
        throwsA(isA<HttpException>()),
      );
      expect(await cache.list().length, before);
    }, _LocalTls(server.port));
  }, timeout: const Timeout(Duration(seconds: 30)));
}
