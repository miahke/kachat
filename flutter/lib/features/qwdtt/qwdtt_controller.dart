import 'package:collection/collection.dart';

// SPDX-License-Identifier: AGPL-3.0-only
import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'routing_gateway.dart';

/// Native transport secrets are never included in user-visible status or diagnostics.
class QwdttController extends ChangeNotifier {
  QwdttController({MethodChannel? channel, bool Function()? supported})
    : _channel = channel ?? const MethodChannel('app.panchat/qwdtt'),
      _supported = supported ?? (() => Platform.isAndroid);
  static final instance = QwdttController();
  final MethodChannel _channel;
  final bool Function() _supported;
  RoutingGateway? _gateway;
  Timer? _poll;
  Map<String, dynamic> _snapshot = {};
  String? _routeKey;
  bool _refreshing = false;
  bool _initialized = false;
  int _revision = 0;
  bool busy = false;
  String? error;
  final Set<FutureOr<void> Function()> _nativeRouteGuards = {};
  bool get selected => _snapshot['selected'] == true;
  String get state => _snapshot['state'] as String? ?? 'STOPPED';
  bool get vkLoggedIn => _snapshot['vkLoggedIn'] == true;
  Future<dynamic> admin(String method, Map<String, dynamic> arguments) =>
      _channel.invokeMethod<dynamic>(method, arguments);
  Future<String> generateHash() async {
    final hash = await _channel.invokeMethod<String>('generateHash');
    if (hash == null || hash.isEmpty) throw const FormatException('No hash');
    return hash;
  }

  String? get activeId => _snapshot['activeId'] as String?;
  List<Map<String, dynamic>> get profiles =>
      ((_snapshot['profiles'] as List?) ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
  List<Map<String, dynamic>> get events =>
      ((_snapshot['events'] as List?) ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
  Map<String, dynamic> get statistics =>
      Map<String, dynamic>.from((_snapshot['statistics'] as Map?) ?? {});
  String? get mode => _snapshot['mode'] as String?;
  bool? get dtls => _snapshot['dtls'] as bool?;
  bool get nativeNetworkAllowed =>
      !selected && _gateway?.mode != GatewayMode.blocked;

  void registerNativeGuard(FutureOr<void> Function() guard) =>
      _nativeRouteGuards.add(guard);
  void unregisterNativeGuard(FutureOr<void> Function() guard) =>
      _nativeRouteGuards.remove(guard);

  Future<void> initialize() async {
    if (_initialized || !_supported()) return;
    _initialized = true;
    // Default BLOCKED until persisted native selection is known, before any account/network boot.
    _gateway = await RoutingGateway.start();
    HttpOverrides.global = QwdttHttpOverrides(_gateway!);
    final revision = _revision;
    try {
      final value =
          await _channel.invokeMapMethod<String, dynamic>('initialize') ?? {};
      if (!busy && revision == _revision) _apply(value);
    } catch (_) {
      if (!busy && revision == _revision) {
        _snapshot = {'selected': true, 'state': 'ERROR'};
        error = 'Настройки qWDTT недоступны; прямой выход заблокирован.';
      }
    }
    _poll = Timer.periodic(const Duration(seconds: 1), (_) => refresh());
    notifyListeners();
  }

  Future<void> refresh() async {
    if (_refreshing || !_initialized || busy) return;
    _refreshing = true;
    final revision = _revision;
    try {
      final value =
          await _channel.invokeMapMethod<String, dynamic>('snapshot') ?? {};
      if (!busy && revision == _revision) _apply(value);
    } catch (_) {
      if (!busy && revision == _revision) {
        _gateway?.block();
        _routeKey = null;
        _snapshot = {..._snapshot, 'selected': true, 'state': 'ERROR'};
        notifyListeners();
      }
    } finally {
      _refreshing = false;
    }
  }

  void _apply(Map<String, dynamic> value) {
    // An absent or malformed selected flag never means permission to connect directly.
    if (value['selected'] is! bool) {
      throw const FormatException('Missing route selection');
    }
    final changed = !const DeepCollectionEquality().equals(_snapshot, value);
    _snapshot = value;
    final socks = value['socks'] as Map?;
    final key = !selected
        ? 'DIRECT'
        : state == 'READY' && socks != null
        ? '${value['generation']}:${socks['port']}:${socks['username']}:${socks['password']}'
        : 'BLOCKED';
    if (_routeKey != key) {
      if (selected) {
        for (final guard in _nativeRouteGuards.toList()) {
          unawaited(
            Future<void>.sync(guard).catchError((Object _) {
              _gateway?.block();
              _routeKey = null;
              error = 'Не удалось закрыть прежнее сетевое соединение.';
            }),
          );
        }
      }
      if (!selected) {
        _gateway?.useDirect();
      } else if (state == 'READY' && socks != null) {
        _gateway?.useSocks(
          SocksTarget(
            socks['port'] as int,
            socks['username'] as String,
            socks['password'] as String,
          ),
        );
      } else {
        _gateway?.block();
      }
      _routeKey = key;
    }
    if (changed) notifyListeners();
  }

  Future<void> command(String method, [Map<String, dynamic>? arguments]) async {
    if (busy) return;
    // An older native RPC must never overwrite the result of this user action.
    _revision++;
    busy = true;
    error = null;
    final switching =
        {'connect', 'disconnect', 'direct'}.contains(method) ||
        (method == 'delete' && arguments?['id'] == activeId);
    try {
      if (switching) {
        _gateway?.block();
        _routeKey = null;
        if (method == 'connect') {
          _snapshot = {..._snapshot, 'selected': true, 'state': 'STARTING'};
          // Persist fail-closed selection before awaiting native connection teardown.
          await _channel.invokeMethod<void>('select');
        }
        if (method != 'direct') {
          for (final guard in _nativeRouteGuards.toList()) {
            await guard();
          }
        }
      }
      notifyListeners();
      _apply(
        await _channel.invokeMapMethod<String, dynamic>(method, arguments) ??
            {},
      );
    } catch (_) {
      error = 'Не удалось выполнить действие. Проверьте профиль и реквизиты.';
      await refresh();
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _poll?.cancel();
    unawaited(_gateway?.dispose());
    super.dispose();
  }
}

/// Every Dart HTTPS/WSS connection uses the lifetime loopback adapter, including DIRECT mode.
/// Keeping a stable proxy endpoint lets route changes terminate pooled connections safely.
class QwdttHttpOverrides extends HttpOverrides {
  QwdttHttpOverrides(this.gateway);
  final RoutingGateway gateway;
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = super.createHttpClient(context);
    client.findProxy = (_) => 'PROXY 127.0.0.1:${gateway.port}';
    client.addProxyCredentials(
      '127.0.0.1',
      gateway.port,
      'panchat',
      HttpClientBasicCredentials(gateway.username, gateway.password),
    );
    client.authenticateProxy = (host, port, scheme, realm) async {
      if (host != '127.0.0.1' ||
          port != gateway.port ||
          scheme.toLowerCase() != 'basic') {
        return false;
      }
      client.addProxyCredentials(
        host,
        port,
        realm ?? 'panchat',
        HttpClientBasicCredentials(gateway.username, gateway.password),
      );
      return true;
    };
    return client;
  }
}
