// SPDX-License-Identifier: AGPL-3.0-only
import 'dart:convert';

/// A single explicitly imported proxy; importing never fetches a remote URL.
class ProxyProfile {
  const ProxyProfile(
    this.type,
    this.host,
    this.port,
    this.username,
    this.password,
  );
  final String type, host, username, password;
  final int port;

  factory ProxyProfile.parse(String source) {
    var text = source.trim();
    if (text.isEmpty ||
        text.length > 8192 ||
        text.contains(RegExp(r'[\r\n]'))) {
      throw const FormatException('Вставьте одну ссылку или адрес прокси.');
    }
    if (!text.contains('://') && !text.contains(':')) {
      try {
        text = utf8.decode(base64Url.decode(base64Url.normalize(text)));
      } catch (_) {
        throw const FormatException('Не удалось прочитать ссылку прокси.');
      }
    }
    if (text.length > 8192 || text.contains(RegExp(r'[\r\n]'))) {
      throw const FormatException('Вставьте одну ссылку прокси.');
    }
    var type = 'SOCKS5';
    String host, user = '', pass = '';
    int? port;
    final parsed = Uri.tryParse(text);
    final telegram =
        parsed != null &&
        ((parsed.scheme == 'tg' && {'socks', 'proxy'}.contains(parsed.host)) ||
            ({'https', 'http'}.contains(parsed.scheme) &&
                {'t.me', 'telegram.me', 'www.t.me'}.contains(parsed.host) &&
                {'/socks', '/proxy'}.contains(parsed.path)));
    if (telegram) {
      if (parsed.queryParameters.containsKey('secret') ||
          parsed.host == 'proxy' ||
          parsed.path == '/proxy') {
        throw const FormatException(
          'Это MTProto-прокси Telegram. Он не передаёт обычный HTTPS-трафик. Нужна ссылка SOCKS5 или HTTP-прокси.',
        );
      }
      host = parsed.queryParameters['server'] ?? '';
      port = int.tryParse(parsed.queryParameters['port'] ?? '');
      user = parsed.queryParameters['user'] ?? '';
      pass = parsed.queryParameters['pass'] ?? '';
    } else {
      if (!text.contains('://')) {
        final parts = text.split(':');
        if (!text.startsWith('[') &&
            parts.length == 4 &&
            int.tryParse(parts[1]) != null) {
          text =
              'socks5://${Uri.encodeComponent(parts[2])}:${Uri.encodeComponent(parts[3])}@${parts[0]}:${parts[1]}';
        } else {
          text = 'socks5://$text';
        }
      }
      final uri = Uri.tryParse(text);
      if (uri == null ||
          !{
            'socks',
            'socks5',
            'socks5h',
            'http',
            'https',
          }.contains(uri.scheme.toLowerCase())) {
        throw const FormatException(
          'Поддерживаются SOCKS5, HTTP и HTTPS CONNECT. Другим протоколам требуется своё ядро.',
        );
      }
      type = switch (uri.scheme.toLowerCase()) {
        'http' => 'HTTP',
        'https' => 'HTTPS',
        _ => 'SOCKS5',
      };
      host = uri.host;
      final rawAuthority = text
          .substring(text.indexOf('://') + 3)
          .split(RegExp(r'[/#?]'))
          .first;
      final explicitPort = RegExp(r':([0-9]+)$').firstMatch(rawAuthority);
      port = explicitPort != null
          ? int.tryParse(explicitPort.group(1)!)
          : type == 'HTTP'
          ? 80
          : type == 'HTTPS'
          ? 443
          : 1080;
      if ((uri.path.isNotEmpty && uri.path != '/') || uri.hasQuery) {
        throw const FormatException(
          'Ожидается адрес прокси, а не веб-страница или подписка.',
        );
      }
      var auth = uri.userInfo;
      var decodedAuth = false;
      if (auth.isNotEmpty && !auth.contains(':')) {
        try {
          final decoded = utf8.decode(
            base64Url.decode(base64Url.normalize(auth)),
          );
          if (decoded.contains(':')) {
            auth = decoded;
            decodedAuth = true;
          }
        } catch (_) {
          /* plain username */
        }
      }
      final colon = auth.indexOf(':');
      final rawUser = colon < 0 ? auth : auth.substring(0, colon);
      final rawPass = colon < 0 ? '' : auth.substring(colon + 1);
      user = decodedAuth ? rawUser : Uri.decodeComponent(rawUser);
      pass = decodedAuth ? rawPass : Uri.decodeComponent(rawPass);
    }
    if (host.isEmpty ||
        host.length > 253 ||
        !RegExp(r'^[A-Za-z0-9.:%_-]+$').hasMatch(host) ||
        port == null ||
        port < 1 ||
        port > 65535 ||
        utf8.encode(user).length > 255 ||
        utf8.encode(pass).length > 255 ||
        user.contains(':') ||
        '$user$pass'.contains(RegExp(r'[\x00-\x1f\x7f]')) ||
        (user.isEmpty && pass.isNotEmpty)) {
      throw const FormatException(
        'Проверьте адрес, порт, логин и пароль прокси.',
      );
    }
    return ProxyProfile(type, host, port, user, pass);
  }
  Map<String, dynamic> toMap() => {
    'type': type,
    'host': host,
    'port': port,
    'username': username,
    'password': password,
  };
  @override
  String toString() => 'ProxyProfile($type, credentials redacted)';
}
