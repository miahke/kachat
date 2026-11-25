import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nym_bar/features/qwdtt/routing_gateway.dart';

void main() {
  test('public address classification rejects special and mapped networks', () {
    for (final ip in [
      '0.1.2.3',
      '10.0.0.1',
      '100.64.0.1',
      '127.0.0.1',
      '169.254.2.3',
      '172.16.0.1',
      '192.0.0.9',
      '192.0.2.1',
      '192.88.99.1',
      '192.168.1.1',
      '198.18.0.1',
      '198.51.100.1',
      '203.0.113.1',
      '224.0.0.1',
      '255.255.255.255',
      '::',
      '::1',
      '::ffff:8.8.8.8',
      'fc00::1',
      'fe80::1',
      'ff02::1',
      '2001:db8::1',
      '2002:0808:0808::1',
      '3fff::1',
    ]) {
      expect(isPublicMediaAddress(InternetAddress(ip)), isFalse, reason: ip);
    }
    for (final ip in [
      '8.8.8.8',
      '1.1.1.1',
      '2606:4700:4700::1111',
      '2a00:1450:4001::1',
    ]) {
      expect(isPublicMediaAddress(InternetAddress(ip)), isTrue, reason: ip);
    }
  });
  test('media DNS rejects mixed answers and dials only the pinned public address', () async {
    final target = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(target.close);
    target.listen((socket) => socket.destroy());
    var answers = [InternetAddress('8.8.8.8'), InternetAddress('127.0.0.1')];
    final dialed = <Object>[];
    final gateway = await RoutingGateway.start(
      resolveMedia: (_) async => answers,
      connectMedia: (host, port) {
        dialed.add(host);
        return Socket.startConnect(InternetAddress.loopbackIPv4, target.port);
      },
    );
    addTearDown(gateway.dispose);
    gateway.useDirect();
    Future<String> connect([String host = 'media.example']) async {
      final socket = await Socket.connect(
        InternetAddress.loopbackIPv4,
        gateway.port,
      );
      final auth = base64.encode(
        utf8.encode('${gateway.username}:${gateway.mediaCredential()}'),
      );
      socket.write(
        'CONNECT $host:443 HTTP/1.1\r\nProxy-Authorization: Basic $auth\r\n\r\n',
      );
      return utf8.decoder
          .bind(socket)
          .join()
          .timeout(const Duration(seconds: 5));
    }

    expect(await connect(), isNot(startsWith('HTTP/1.1 200')));
    expect(dialed, isEmpty);
    expect(await connect('127.0.0.1'), isNot(startsWith('HTTP/1.1 200')));
    expect(dialed, isEmpty);
    answers = [];
    expect(await connect(), isNot(startsWith('HTTP/1.1 200')));
    expect(dialed, isEmpty);
    answers = [InternetAddress('8.8.8.8')];
    expect(await connect(), startsWith('HTTP/1.1 200'));
    expect(dialed, hasLength(1));
    expect(dialed.single, isA<InternetAddress>());
    expect((dialed.single as InternetAddress).address, '8.8.8.8');
  });
  test('route changes while resolving prevent dialing', () async {
    final pending = Completer<List<InternetAddress>>();
    var dialed = false;
    final gateway = await RoutingGateway.start(
      resolveMedia: (_) => pending.future,
      connectMedia: (host, port) {
        dialed = true;
        return Socket.startConnect(host, port);
      },
    );
    addTearDown(gateway.dispose);
    gateway.useDirect();
    final socket = await Socket.connect(
      InternetAddress.loopbackIPv4,
      gateway.port,
    );
    final auth = base64.encode(
      utf8.encode('${gateway.username}:${gateway.mediaCredential()}'),
    );
    socket.write(
      'CONNECT media.example:443 HTTP/1.1\r\nProxy-Authorization: Basic $auth\r\n\r\n',
    );
    await Future<void>.delayed(const Duration(milliseconds: 50));
    gateway.block();
    pending.complete([InternetAddress('8.8.8.8')]);
    await socket.drain<void>().timeout(const Duration(seconds: 5));
    await Future<void>.delayed(Duration.zero);
    expect(dialed, isFalse);
  });
}
