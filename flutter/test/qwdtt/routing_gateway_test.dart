import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nym_bar/features/qwdtt/routing_gateway.dart';

void main() {
  test(
    'selected unavailable tunnel refuses CONNECT without falling back',
    () async {
      final gateway = await RoutingGateway.start();
      addTearDown(gateway.dispose);
      final socket = await Socket.connect(
        InternetAddress.loopbackIPv4,
        gateway.port,
      );
      socket.write(
        'CONNECT unreachable.example.invalid:443 HTTP/1.1\r\n'
        'Proxy-Authorization: ${gateway.authorization}\r\n\r\n',
      );
      final response = await utf8.decoder
          .bind(socket)
          .join()
          .timeout(const Duration(seconds: 3));
      expect(response, startsWith('HTTP/1.1 503'));
    },
  );

  test('unauthenticated loopback client cannot open a connection', () async {
    final target = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(target.close);
    var accepted = 0;
    target.listen((s) {
      accepted++;
      s.destroy();
    });
    final gateway = await RoutingGateway.start();
    gateway.useDirect();
    addTearDown(gateway.dispose);
    final socket = await Socket.connect(
      InternetAddress.loopbackIPv4,
      gateway.port,
    );
    socket.write('CONNECT 127.0.0.1:${target.port} HTTP/1.1\r\n\r\n');
    final response = await utf8.decoder
        .bind(socket)
        .join()
        .timeout(const Duration(seconds: 3));
    expect(response, startsWith('HTTP/1.1 407'));
    expect(accepted, 0);
  });

  test(
    'authenticated SOCKS CONNECT sends domain to proxy and relays bytes',
    () async {
      final socks = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(socks.close);
      final domain = Completer<String>();
      socks.listen((socket) async {
        final reader = SocketBytes(socket);
        try {
          expect(await reader.read(3), [5, 1, 2]);
          socket.add([5, 2]);
          await socket.flush();
          expect((await reader.read(2))[0], 1);
          await reader.read(4); // synthetic username
          final passLength = (await reader.read(1))[0];
          await reader.read(passLength);
          socket.add([1, 0]);
          await socket.flush();
          expect(await reader.read(4), [5, 1, 0, 3]);
          final length = (await reader.read(1))[0];
          domain.complete(utf8.decode(await reader.read(length)));
          await reader.read(2);
          socket.add([5, 0, 0, 1, 127, 0, 0, 1, 0, 0]);
          await socket.flush();
          final body = await reader.read(4);
          expect(utf8.decode(body), 'ping');
          socket.add(utf8.encode('pong'));
          await socket.flush();
        } finally {
          socket.destroy();
          await reader.cancel();
        }
      });
      final gateway = await RoutingGateway.start();
      addTearDown(gateway.dispose);
      gateway.useSocks(SocksTarget(socks.port, 'user', 'synthetic-secret'));
      final socket = await Socket.connect(
        InternetAddress.loopbackIPv4,
        gateway.port,
      );
      final reader = SocketBytes(socket);
      addTearDown(() async {
        socket.destroy();
        await reader.cancel();
      });
      socket.write(
        'CONNECT never-resolve.example.invalid:443 HTTP/1.1\r\n'
        'Proxy-Authorization: ${gateway.authorization}\r\n\r\n',
      );
      expect(await reader.header(), startsWith('HTTP/1.1 200'));
      socket.add(utf8.encode('ping'));
      await socket.flush();
      expect(utf8.decode(await reader.read(4)), 'pong');
      expect(await domain.future, 'never-resolve.example.invalid');
    },
  );

  test('switching routes closes an already established connection', () async {
    final target = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(target.close);
    target.listen((socket) {
      socket.listen(socket.add, onDone: socket.destroy);
    });
    final gateway = await RoutingGateway.start();
    gateway.useDirect();
    addTearDown(gateway.dispose);
    final socket = await Socket.connect(
      InternetAddress.loopbackIPv4,
      gateway.port,
    );
    final reader = SocketBytes(socket);
    socket.write(
      'CONNECT 127.0.0.1:${target.port} HTTP/1.1\r\n'
      'Proxy-Authorization: ${gateway.authorization}\r\n\r\n',
    );
    expect(await reader.header(), startsWith('HTTP/1.1 200'));
    gateway.block();
    await expectLater(reader.read(1), throwsA(isA<SocketException>()));
    await reader.cancel();
    socket.destroy();
  });
}

class SocketBytes {
  SocketBytes(Socket socket) : _chunks = StreamIterator(socket);
  final StreamIterator<Uint8List> _chunks;
  final List<int> _buffer = [];
  Future<List<int>> read(int count) async {
    while (_buffer.length < count) {
      if (!await _chunks.moveNext()) throw const SocketException('closed');
      _buffer.addAll(_chunks.current);
    }
    final result = _buffer.sublist(0, count);
    _buffer.removeRange(0, count);
    return result;
  }

  Future<String> header() async {
    var value = '';
    while (!value.endsWith('\r\n\r\n')) {
      value += String.fromCharCode((await read(1))[0]);
    }
    return value;
  }

  Future<void> cancel() => _chunks.cancel();
}
