// SPDX-License-Identifier: AGPL-3.0-only
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

enum GatewayMode { blocked, direct, socks }

class SocksTarget {
  SocksTarget(this.port, this.username, this.password) {
    if (port < 1024 ||
        port > 65535 ||
        utf8.encode(username).isEmpty ||
        utf8.encode(username).length > 255 ||
        utf8.encode(password).isEmpty ||
        utf8.encode(password).length > 255) {
      throw ArgumentError('Invalid local proxy');
    }
  }
  final int port;
  final String username;
  final String password;
  @override
  String toString() => 'SocksTarget(loopback, credentials redacted)';
}

/// One local CONNECT adapter for the lifetime of an isolate. TLS stays end to end.
/// Changing routes closes sockets, so pooled HttpClients cannot retain direct tunnels.
class RoutingGateway {
  RoutingGateway._(this._server, this.password) {
    _listener = _server.listen(_accept);
  }
  static Future<RoutingGateway> start() async {
    final random = Random.secure();
    final token = base64Url.encode(
      List.generate(32, (_) => random.nextInt(256)),
    );
    return RoutingGateway._(
      await ServerSocket.bind(InternetAddress.loopbackIPv4, 0),
      token,
    );
  }

  final ServerSocket _server;
  StreamSubscription<Socket>? _listener;
  final Set<Socket> _sockets = {};
  final Set<void Function()> _connecting = {};
  int _generation = 0;
  int _clients = 0;
  bool _disposed = false;
  GatewayMode _mode = GatewayMode.blocked;
  SocksTarget? _target;
  final String password;
  String get username => 'panchat';
  int get port => _server.port;
  GatewayMode get mode => _mode;
  String get authorization =>
      'Basic ${base64.encode(utf8.encode('$username:$password'))}';

  void block() => _switch(GatewayMode.blocked, null);
  void useDirect() => _switch(GatewayMode.direct, null);
  void useSocks(SocksTarget target) => _switch(GatewayMode.socks, target);
  void _switch(GatewayMode mode, SocksTarget? target) {
    if (_disposed) throw StateError('Gateway disposed');
    _generation++;
    _mode = mode;
    _target = target;
    for (final cancel in _connecting.toList()) {
      cancel();
    }
    for (final socket in _sockets.toList()) {
      socket.destroy();
    }
    _sockets.clear();
  }

  Future<void> dispose() async {
    if (_disposed) return;
    block();
    _disposed = true;
    await _listener?.cancel();
    await _server.close();
  }

  void _accept(Socket client) {
    if (_disposed || _clients >= 64) {
      client.destroy();
      return;
    }
    _clients++;
    _sockets.add(client);
    unawaited(
      _serve(client).whenComplete(() {
        _clients--;
        _sockets.remove(client);
      }),
    );
  }

  Future<void> _reply(Socket socket, int status) async {
    final challenge = status == 407
        ? 'Proxy-Authenticate: Basic realm="panchat"\r\n'
        : '';
    socket.write(
      'HTTP/1.1 $status ${status == 200 ? 'Connection Established' : 'Connection refused'}\r\n'
      '${challenge}Content-Length: 0\r\n\r\n',
    );
    await socket.flush();
  }

  Future<Socket> _connect(String host, int port, int generation) async {
    final task = await Socket.startConnect(host, port);
    if (generation != _generation || _disposed) {
      task.cancel();
      throw const SocketException('Route changed');
    }
    _connecting.add(task.cancel);
    try {
      final socket = await task.socket.timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          task.cancel();
          throw const SocketException('Connection timeout');
        },
      );
      if (generation != _generation || _disposed) {
        socket.destroy();
        throw const SocketException('Route changed');
      }
      _sockets.add(socket);
      return socket;
    } finally {
      _connecting.remove(task.cancel);
    }
  }

  Future<void> _serve(Socket client) async {
    Socket? upstream;
    final incoming = _SocketBytes(client);
    _SocketBytes? outgoing;
    try {
      final header = await incoming.header().timeout(
        const Duration(seconds: 10),
      );
      final lines = header.split('\r\n');
      final first = lines.first.split(' ');
      if (first.length != 3 ||
          first[0] != 'CONNECT' ||
          first[2] != 'HTTP/1.1') {
        await _reply(client, 405);
        return;
      }
      final auth = lines
          .skip(1)
          .where((s) => s.toLowerCase().startsWith('proxy-authorization:'))
          .toList();
      if (auth.length != 1 ||
          !_constantEquals(
            auth.single.substring(auth.single.indexOf(':') + 1).trim(),
            authorization,
          )) {
        await _reply(client, 407);
        return;
      }
      final authority = first[1];
      final uri = Uri.tryParse('https://$authority');
      if (uri == null ||
          uri.host.isEmpty ||
          uri.userInfo.isNotEmpty ||
          uri.path.isNotEmpty ||
          uri.hasQuery ||
          uri.hasFragment ||
          !RegExp(r'^[0-9]{1,5}$')
              .hasMatch(authority.substring(authority.lastIndexOf(':') + 1)) ||
          uri.port < 1 ||
          uri.port > 65535 ||
          uri.host.length > 253 ||
          uri.host.codeUnits.any((c) => c < 33 || c > 126)) {
        await _reply(client, 400);
        return;
      }
      final generation = _generation;
      final mode = _mode;
      final target = _target;
      if (mode == GatewayMode.blocked) {
        await _reply(client, 503);
        return;
      }
      if (mode == GatewayMode.direct) {
        upstream = await _connect(uri.host, uri.port, generation);
      } else {
        if (target == null) {
          await _reply(client, 503);
          return;
        }
        upstream = await _connect('127.0.0.1', target.port, generation);
        outgoing = _SocketBytes(upstream);
        await _socks(
          upstream,
          outgoing,
          target,
          uri.host,
          uri.port,
        ).timeout(const Duration(seconds: 15));
      }
      outgoing ??= _SocketBytes(upstream);
      if (generation != _generation) return;
      await _reply(client, 200);
      // Consume both futures: closing either side terminates the other without an unhandled error.
      final a = incoming.pump(upstream).whenComplete(() {
        client.destroy();
        upstream?.destroy();
      });
      final b = outgoing.pump(client).whenComplete(() {
        client.destroy();
        upstream?.destroy();
      });
      await Future.wait([a, b]);
    } catch (_) {
      // Never log destination names, credentials, account keys or payloads.
    } finally {
      client.destroy();
      upstream?.destroy();
      if (upstream != null) _sockets.remove(upstream);
      await incoming.cancel();
      await outgoing?.cancel();
    }
  }

  Future<void> _socks(
    Socket socket,
    _SocketBytes reader,
    SocksTarget target,
    String host,
    int port,
  ) async {
    socket.add([5, 1, 2]);
    await socket.flush();
    final method = await reader.read(2);
    if (method[0] != 5 || method[1] != 2) {
      throw const SocketException('Authentication required');
    }
    final user = utf8.encode(target.username),
        pass = utf8.encode(target.password);
    socket.add([1, user.length, ...user, pass.length, ...pass]);
    await socket.flush();
    final auth = await reader.read(2);
    if (auth[0] != 1 || auth[1] != 0) {
      throw const SocketException('Authentication failed');
    }
    final literal = InternetAddress.tryParse(host);
    final address = literal == null
        ? [3, host.length, ...ascii.encode(host)]
        : [
            literal.type == InternetAddressType.IPv4 ? 1 : 4,
            ...literal.rawAddress,
          ];
    socket.add([5, 1, 0, ...address, port >> 8, port & 255]);
    await socket.flush();
    final response = await reader.read(4);
    if (response[0] != 5 || response[1] != 0 || response[2] != 0) {
      throw const SocketException('Proxy refused connection');
    }
    final length = switch (response[3]) {
      1 => 4,
      4 => 16,
      3 => (await reader.read(1))[0],
      _ => throw const SocketException('Invalid proxy response'),
    };
    await reader.read(length + 2);
  }

  static bool _constantEquals(String a, String b) {
    if (a.length != b.length) return false;
    var difference = 0;
    for (var i = 0; i < a.length; i++) {
      difference |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return difference == 0;
  }
}

class _SocketBytes {
  _SocketBytes(Socket socket) : _chunks = StreamIterator(socket);
  final StreamIterator<Uint8List> _chunks;
  Uint8List _current = Uint8List(0);
  int _offset = 0;
  Future<void> _next() async {
    while (_offset == _current.length) {
      if (!await _chunks.moveNext()) {
        throw const SocketException('Connection closed');
      }
      _current = _chunks.current;
      _offset = 0;
    }
  }

  Future<int> byte() async {
    await _next();
    return _current[_offset++];
  }

  Future<List<int>> read(int count) async {
    final output = BytesBuilder(copy: false);
    while (count > 0) {
      await _next();
      final n = min(count, _current.length - _offset);
      output.add(Uint8List.sublistView(_current, _offset, _offset + n));
      _offset += n;
      count -= n;
    }
    return output.takeBytes();
  }

  Future<String> header() async {
    final bytes = <int>[];
    while (bytes.length < 16384) {
      bytes.add(await byte());
      final n = bytes.length;
      if (n >= 4 &&
          bytes[n - 4] == 13 &&
          bytes[n - 3] == 10 &&
          bytes[n - 2] == 13 &&
          bytes[n - 1] == 10) {
        return ascii.decode(bytes);
      }
    }
    throw const SocketException('Headers too large');
  }

  Future<void> pump(Socket target) async {
    if (_offset < _current.length) {
      target.add(Uint8List.sublistView(_current, _offset));
    }
    while (await _chunks.moveNext()) {
      target.add(_chunks.current);
      await target.flush();
    }
  }

  Future<void> cancel() => _chunks.cancel();
}
