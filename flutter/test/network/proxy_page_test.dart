import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nym_bar/features/network/proxy_page.dart';
import 'package:nym_bar/features/qwdtt/qwdtt_controller.dart';

class _ProxyFake extends QwdttController {
  final calls = <String>[];

  @override
  String get route => 'PROXY';

  @override
  String get state => 'READY';

  @override
  Future<Map<String, dynamic>> proxySettings() async => {};

  @override
  Future<void> command(String method, [Map<String, dynamic>? arguments]) async {
    calls.add(method);
  }
}

void main() {
  testWidgets('stopping external proxy explicitly selects direct connection', (
    tester,
  ) async {
    final controller = _ProxyFake();
    await tester.pumpWidget(
      MaterialApp(home: ProxyPage(controller: controller)),
    );
    await tester.scrollUntilVisible(
      find.text('Выключить прокси'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Выключить прокси'));
    expect(controller.calls, ['direct']);
  });
}
