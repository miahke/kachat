import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nym_bar/features/network/tor_page.dart';
import 'package:nym_bar/features/qwdtt/qwdtt_controller.dart';

class TorFake extends QwdttController {
  String phase = 'STARTING';
  int percent = 42;
  void updatePhase(String value) {
    phase = value;
    notifyListeners();
  }

  final calls = <(String, Map<String, dynamic>?)>[];
  @override
  String get route => 'TOR';
  @override
  bool get selected => true;
  @override
  String get state => phase;
  @override
  Map<String, dynamic> get tor => {
    'percent': percent,
    'stage': 'BOOTSTRAPPING',
  };
  @override
  Future<Map<String, dynamic>> torSettings() async => {
    'mode': 'WEBTUNNEL',
    'bridges': 'webtunnel 192.0.2.1:443 synthetic',
    'socksPort': 19050,
  };
  @override
  Future<void> command(String method, [Map<String, dynamic>? args]) async {
    calls.add((method, args));
  }
}

void main() {
  testWidgets('pasted plain bridge selects the real bridge mode', (
    tester,
  ) async {
    final c = TorFake();
    await tester.pumpWidget(MaterialApp(home: TorPage(controller: c)));
    await tester.pumpAndSettle();
    final source =
        'Bridge 192.0.2.1:443 0123456789ABCDEF0123456789ABCDEF01234567';
    await tester.scrollUntilVisible(
      find.byKey(const Key('tor-bridges')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.enterText(find.byKey(const Key('tor-bridges')), source);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('tor-connect')),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(const Key('tor-connect')));
    await tester.pumpAndSettle();
    expect(c.calls.single.$2!['mode'], 'PLAIN_BRIDGES');
    expect(c.calls.single.$2!['bridges'], source);
    c.dispose();
  });
  testWidgets('Tor progress never shows 100 until native readiness', (
    tester,
  ) async {
    final c = TorFake()..percent = 100;
    await tester.pumpWidget(MaterialApp(home: TorPage(controller: c)));
    await tester.pumpAndSettle();
    expect(find.textContaining('99 %'), findsOneWidget);
    c.updatePhase('READY');
    await tester.pump();
    expect(find.text('Tor подключён · 100 %'), findsOneWidget);
    c.dispose();
  });
  testWidgets(
    'Snowflake starts with builtin configuration rather than stale WebTunnel line',
    (tester) async {
      final c = TorFake();
      await tester.pumpWidget(MaterialApp(home: TorPage(controller: c)));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('tor-mode')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Snowflake').last);
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const Key('tor-connect')),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.byKey(const Key('tor-connect')));
      await tester.pumpAndSettle();
      expect(c.calls.single.$1, 'connectTor');
      expect(c.calls.single.$2!['mode'], 'SNOWFLAKE');
      expect(c.calls.single.$2!['bridges'], '');
      c.dispose();
    },
  );
}
