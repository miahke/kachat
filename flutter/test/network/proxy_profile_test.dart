import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nym_bar/features/network/proxy_profile.dart';

void main() {
  test('standard, encoded auth, raw and Telegram SOCKS imports', () {
    for (final value in [
      'socks5://demo:p%40ss@proxy.example:1080',
      'proxy.example:1080:demo:p@ss',
      'tg://socks?server=proxy.example&port=1080&user=demo&pass=p%40ss',
      'https://t.me/socks?server=proxy.example&port=1080&user=demo&pass=p%40ss',
      'socks://${base64Url.encode(utf8.encode('demo:p@ss'))}@proxy.example:1080',
    ]) {
      final p = ProxyProfile.parse(value);
      expect(p.type, 'SOCKS5');
      expect(p.host, 'proxy.example');
      expect(p.port, 1080);
      expect(p.username, 'demo');
      expect(p.password, 'p@ss');
      expect(p.toString(), isNot(contains('p@ss')));
    }
  });
  test('HTTP HTTPS and IPv6 addresses are retained', () {
    final encoded = base64Url.encode(utf8.encode('demo:p%a:b'));
    expect(
      ProxyProfile.parse('socks://$encoded@proxy.example:1080').password,
      'p%a:b',
    );
    expect(ProxyProfile.parse('http://proxy.example:3128').type, 'HTTP');
    expect(ProxyProfile.parse('https://proxy.example').port, 443);
    expect(ProxyProfile.parse('[::1]:1080').host, '::1');
    expect(ProxyProfile.parse('proxy.example:1080').username, isEmpty);
  });
  test('unsupported transports and malformed links are explicit errors', () {
    for (final text in [
      'tg://proxy?server=proxy.example&port=443&secret=synthetic',
      'https://t.me/proxy?server=proxy.example&port=443&secret=synthetic',
      'ss://synthetic@proxy.example:443',
      'http://proxy.example/path',
      'socks5://proxy.example:0',
      'socks5://proxy.example:70000',
      'socks5://u:%0d%0a@proxy.example:1080',
      'a:1\nb:2',
    ]) {
      expect(
        () => ProxyProfile.parse(text),
        throwsFormatException,
        reason: text,
      );
    }
  });
}
