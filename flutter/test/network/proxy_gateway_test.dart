import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nym_bar/features/qwdtt/routing_gateway.dart';

import '../qwdtt/routing_gateway_test.dart' show SocketBytes;

void main() {
  test('HTTPS proxy starts TLS and never downgrades to a plain HTTP server', () async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);
    final firstByte = Completer<int>();
    server.listen((socket) {
      socket.listen(
        (data) async {
          if (firstByte.isCompleted) return;
          firstByte.complete(data.first);
          socket.write('HTTP/1.1 200 Connection established\r\n\r\n');
          await socket.flush();
          socket.destroy();
        },
        onError: (_) {
          socket.destroy();
        },
        onDone: socket.destroy,
      );
    });
    final gateway = await RoutingGateway.start();
    addTearDown(gateway.dispose);
    gateway.useSocks(
      SocksTarget(server.port, 'test', 'synthetic', type: 'HTTPS'),
    );
    final socket = await Socket.connect('127.0.0.1', gateway.port);
    socket.write(
      'CONNECT dest.example.invalid:443 HTTP/1.1\r\nProxy-Authorization: ${gateway.authorization}\r\n\r\n',
    );
    await socket.flush();
    expect(
      await utf8.decoder
          .bind(socket)
          .join()
          .timeout(const Duration(seconds: 5)),
      isEmpty,
    );
    expect(
      await firstByte.future,
      22,
    ); // TLS handshake record, not CONNECT/auth.
    expect(gateway.mode, GatewayMode.socks);
  });
  test('HTTP CONNECT forwards domain and upstream-only auth, relays bytes', () async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);
    final seen = Completer<String>();
    server.listen((socket) async {
      final r = SocketBytes(socket);
      try {
        seen.complete(await r.header());
        socket.write('HTTP/1.1 200 Connection established\r\n\r\n');
        await socket.flush();
        expect(ascii.decode(await r.read(4)), 'ping');
        socket.write('pong');
        await socket.flush();
      } finally {
        socket.destroy();
        await r.cancel();
      }
    });
    final gateway = await RoutingGateway.start();
    addTearDown(gateway.dispose);
    gateway.useSocks(
      SocksTarget(
        server.port,
        'test',
        'synthetic',
        type: 'HTTP',
        host: '127.0.0.1',
      ),
    );
    final socket = await Socket.connect('127.0.0.1', gateway.port);
    final r = SocketBytes(socket);
    addTearDown(() async {
      socket.destroy();
      await r.cancel();
    });
    socket.write(
      'CONNECT dest.example.invalid:443 HTTP/1.1\r\nProxy-Authorization: ${gateway.authorization}\r\n\r\n',
    );
    await socket.flush();
    expect(await r.header(), startsWith('HTTP/1.1 200'));
    final header = await seen.future;
    expect(header, contains('CONNECT dest.example.invalid:443'));
    expect(
      header,
      contains('Basic ${base64.encode(utf8.encode('test:synthetic'))}'),
    );
    expect(header, isNot(contains(gateway.password)));
    socket.write('ping');
    await socket.flush();
    expect(ascii.decode(await r.read(4)), 'pong');
  });
  test('unauthenticated SOCKS5 offers only no-auth and sends remote domain', () async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);
    final completed = Completer<void>();
    server.listen((socket) async {
      final r = SocketBytes(socket);
      try {
        expect(await r.read(3), [5, 1, 0]);
        socket.add([5, 0]);
        await socket.flush();
        expect(await r.read(4), [5, 1, 0, 3]);
        final n = (await r.read(1))[0];
        expect(ascii.decode(await r.read(n)), 'dest.example.invalid');
        await r.read(2);
        socket.add([5, 0, 0, 1, 0, 0, 0, 0, 0, 0]);
        await socket.flush();
        completed.complete();
        await r.read(1);
      } catch (_) {
        if (!completed.isCompleted) {
          completed.completeError(StateError('SOCKS exchange failed'));
        }
      } finally {
        socket.destroy();
        await r.cancel();
      }
    });
    final gateway = await RoutingGateway.start();
    addTearDown(gateway.dispose);
    gateway.useSocks(SocksTarget(server.port, '', ''));
    final socket = await Socket.connect('127.0.0.1', gateway.port);
    final r = SocketBytes(socket);
    socket.write(
      'CONNECT dest.example.invalid:443 HTTP/1.1\r\nProxy-Authorization: ${gateway.authorization}\r\n\r\n',
    );
    await socket.flush();
    expect(await r.header(), startsWith('HTTP/1.1 200'));
    await completed.future;
    gateway.block();
    socket.destroy();
    await r.cancel();
  });
  test('HTTP proxy refusal never opens destination directly', () async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);
    server.listen((socket) async {
      final r = SocketBytes(socket);
      try {
        await r.header();
        socket.write('HTTP/1.1 407 Authentication required\r\n\r\n');
        await socket.flush();
      } finally {
        socket.destroy();
        await r.cancel();
      }
    });
    final gateway = await RoutingGateway.start();
    addTearDown(gateway.dispose);
    gateway.useSocks(SocksTarget(server.port, '', '', type: 'HTTP'));
    final socket = await Socket.connect('127.0.0.1', gateway.port);
    socket.write(
      'CONNECT dest.example.invalid:443 HTTP/1.1\r\nProxy-Authorization: ${gateway.authorization}\r\n\r\n',
    );
    await socket.flush();
    expect(
      await utf8.decoder
          .bind(socket)
          .join()
          .timeout(const Duration(seconds: 3)),
      isNot(contains('200 Connection')),
    );
    expect(gateway.mode, GatewayMode.socks);
  });
}
