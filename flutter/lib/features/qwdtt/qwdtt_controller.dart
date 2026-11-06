import 'package:collection/collection.dart';

// SPDX-License-Identifier: AGPL-3.0-only
import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

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
  bool captchaPresenting = false;
  String? _lastCaptchaId;
  bool _disposed = false;
  String probeState = 'idle';
  String? probeMessage;
  HttpClient? _probeClient;

  /// True on platforms with the native routing stack; elsewhere this controller stays inert.
  bool get supported => _supported();

  /// True once initialization has started.
  bool get initialized => _initialized;

  /// The route explicitly reported by native code, or null while unknown.
  String? get reportedRoute => _snapshot['route'] as String?;

  String get route =>
      _snapshot['route'] as String? ?? (selected ? 'VK' : 'DIRECT');
  Map<String, dynamic> get tor =>
      Map<String, dynamic>.from((_snapshot['tor'] as Map?) ?? {});
  bool get captchaPending => route == 'VK' && _snapshot['captcha'] is Map;
  String? get statusError => _snapshot['error'] as String?;

  Future<Map<String, dynamic>> torSettings() async =>
      await _channel.invokeMapMethod<String, dynamic>('torSettings') ?? {};
  Future<Map<String, dynamic>> proxySettings() async =>
      await _channel.invokeMapMethod<String, dynamic>('proxySettings') ?? {};
  Future<String> exportProfile(String id) async {
    final value = await _channel.invokeMethod<String>('export', {'id': id});
    if (value == null || value.isEmpty) {
      throw const FormatException('Export unavailable');
    }
    return value;
  }

  Future<void> solveCaptcha() async {
    if (captchaPresenting || !captchaPending) return;
    captchaPresenting = true;
    _lastCaptchaId = (_snapshot['captcha'] as Map)['id'] as String?;
    final revision = _revision;
    notifyListeners();
    try {
      final value = await _channel.invokeMapMethod<String, dynamic>(
        'solveCaptcha',
      );
      if (!_disposed && revision == _revision && value != null) _apply(value);
    } on PlatformException catch (e) {
      if (!_disposed && revision == _revision) {
        final message = e.code == 'VK_CONFIRMATION'
            ? e.message
            : 'Проверка VK отменена или истекла. Повторите подключение.';
        // A cancelled challenge must not open a fresh popup on every core retry.
        _revision++;
        _gateway?.block();
        _routeKey = null;
        try {
          final stopped = await _channel.invokeMapMethod<String, dynamic>(
            'disconnect',
          );
          if (!_disposed && stopped != null) _apply(stopped);
        } catch (_) {
          _snapshot = {
            ..._snapshot,
            'selected': true,
            'state': 'STOPPED',
            'captcha': null,
          };
        }
        error = message;
      }
    } finally {
      captchaPresenting = false;
      if (!_disposed) notifyListeners();
    }
  }

  void _maybePresentCaptcha() {
    if (!captchaPending || captchaPresenting || _disposed) return;
    if ((_snapshot['captcha'] as Map)['id'] == _lastCaptchaId) return;
    try {
      if (WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
        return;
      }
    } catch (_) {
      return;
    }
    unawaited(solveCaptcha());
  }

  Future<void> checkConnection() async {
    if (probeState == 'checking') return;
    final gateway = _gateway;
    if (!selected || state != 'READY' || gateway == null) {
      probeState = 'error';
      probeMessage = 'Сначала подключите защищённый маршрут.';
      notifyListeners();
      return;
    }
    final revision = _revision;
    final key = _routeKey;
    probeState = 'checking';
    probeMessage = 'Проверяем HTTPS через выбранный прокси…';
    notifyListeners();
    final client = QwdttHttpOverrides(gateway).createHttpClient(null)
      ..connectionTimeout = const Duration(seconds: 12);
    _probeClient = client;
    try {
      final request = await client
          .headUrl(Uri.https('web.nymchat.app', '/'))
          .timeout(const Duration(seconds: 15));
      request.followRedirects = false;
      final response = await request.close().timeout(
        const Duration(seconds: 15),
      );
      await response.drain<void>().timeout(const Duration(seconds: 5));
      if (!_disposed && revision == _revision && key == _routeKey) {
        probeState = 'ok';
        probeMessage =
            'Сервер ответил через выбранный прокси (HTTPS, HTTP ${response.statusCode}). Доставка сообщений проверяется отдельно.';
      }
    } catch (_) {
      if (!_disposed && revision == _revision && key == _routeKey) {
        probeState = 'error';
        probeMessage = 'Нет HTTPS-ответа через выбранный прокси. Проверьте туннель и доступность сервера.';
      }
    } finally {
      client.close(force: true);
      if (identical(_probeClient, client)) _probeClient = null;
      if (!_disposed) notifyListeners();
    }
  }

  String? error;
  final Set<FutureOr<void> Function()> _nativeRouteGuards = {};
  bool get selected => _snapshot['selected'] == true;
  String get state => _snapshot['state'] as String? ?? 'STOPPED';
  bool get vkLoggedIn => _snapshot['vkLoggedIn'] == true;
  Future<dynamic> admin(String method, Map<String, dynamic> arguments) =>
      _channel.invokeMethod<dynamic>(method, arguments);
  Future<String>? _hashInFlight;
  Future<String> generateHash() => _hashInFlight ??= _generateHash()
      .whenComplete(() => _hashInFlight = null);

  Future<String> _generateHash() async {
    final hash = await _channel.invokeMethod<String>('generateHash');
    if (hash == null || hash.isEmpty) {
      throw const FormatException('VK не выдал хэш.');
    }
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
        error = 'Настройки сети недоступны; прямой выход заблокирован.';
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
    if (_disposed) return;
    // An absent or malformed selected flag never means permission to connect directly.
    if (value['selected'] is! bool) {
      throw const FormatException('Missing route selection');
    }
    final changed = !const DeepCollectionEquality().equals(_snapshot, value);
    _snapshot = value;
    final external = value['route'] == 'PROXY';
    final socks = (external ? value['proxy'] : value['socks']) as Map?;
    final key = !selected
        ? 'DIRECT'
        : state == 'READY' && socks != null
        ? '${value['generation']}:${socks['host']}:${socks['type']}:${socks['port']}:${socks['username']}:${socks['password']}'
        : 'BLOCKED';
    if (_routeKey != key) {
      _probeClient?.close(force: true);
      probeState = 'idle';
      probeMessage = null;
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
            host: external ? socks['host'] as String : '127.0.0.1',
            type: external ? socks['type'] as String : 'SOCKS5',
          ),
        );
      } else {
        _gateway?.block();
      }
      _routeKey = key;
    }
    if (changed) notifyListeners();
    _maybePresentCaptcha();
  }

  Future<void> command(String method, [Map<String, dynamic>? arguments]) async {
    if (busy) return;
    // An older native RPC must never overwrite the result of this user action.
    _revision++;
    busy = true;
    error = null;
    final switching =
        {
          'connect',
          'connectTor',
          'connectProxy',
          'disconnect',
          'direct',
        }.contains(method) ||
        (method == 'delete' && arguments?['id'] == activeId);
    try {
      if (switching) {
        _gateway?.block();
        _routeKey = null;
        if (method == 'connect' ||
            method == 'connectTor' ||
            method == 'connectProxy') {
          final nextRoute = method == 'connectTor'
              ? 'TOR'
              : method == 'connectProxy'
              ? 'PROXY'
              : 'VK';
          _snapshot = {
            ..._snapshot,
            'selected': true,
            'state': 'STARTING',
            'route': nextRoute,
          };
          // Persist fail-closed selection before awaiting native connection teardown.
          await _channel.invokeMethod<void>('select', {'route': nextRoute});
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
    } on PlatformException catch (e) {
      error =
          const {
            'VK_CONFIRMATION',
            'TOR_BRIDGE',
            'QWDTT_FAILED',
          }.contains(e.code)
          ? e.message
          : 'Не удалось выполнить действие. Проверьте профиль и реквизиты.';
    } catch (_) {
      error = 'Не удалось выполнить действие. Проверьте профиль и реквизиты.';
    } finally {
      busy = false;
      unawaited(refresh());
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _probeClient?.close(force: true);
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
