import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nym_bar/features/qwdtt/qwdtt_controller.dart';
import 'package:nym_bar/features/qwdtt/qwdtt_page.dart';

class FakeQwdtt extends QwdttController {
  final calls = <(String, Map<String, dynamic>?)>[];
  bool ready = false;
  @override
  String get state => ready ? 'READY' : 'STOPPED';
  @override
  bool get selected => ready;
  @override
  String? get activeId => ready ? 'synthetic-profile' : null;
  @override
  List<Map<String, dynamic>> get profiles => [
    {
      'profile': {
        'id': 'synthetic-profile',
        'name': 'Synthetic connection',
        'vkMode': 'WG',
        'socksPort': 1080,
        'serverHost': 'server.example.invalid',
      },
      'hasHash': true,
      'hasPassword': true,
    },
  ];
  @override
  Map<String, dynamic> get statistics => {
    'workers': 2,
    'up': 100,
    'down': 200,
    'received': true,
  };
  @override
  List<Map<String, dynamic>> get events => [];
  @override
  Future<void> refresh() async {}
  @override
  Future<void> command(String method, [Map<String, dynamic>? arguments]) async {
    calls.add((method, arguments));
  }
}

void main() {
  testWidgets('saved profile connects through its actual identifier', (
    tester,
  ) async {
    final controller = FakeQwdtt();
    await tester.pumpWidget(
      MaterialApp(home: QwdttPage(controller: controller)),
    );
    await tester.tap(find.byKey(const Key('qwdtt-connect-synthetic-profile')));
    expect(controller.calls.single.$1, 'connect');
    expect(controller.calls.single.$2, {'id': 'synthetic-profile'});
  });
  testWidgets(
    'import sends the provided subscription without automatic connection',
    (tester) async {
      final controller = FakeQwdtt();
      await tester.pumpWidget(
        MaterialApp(home: QwdttPage(controller: controller)),
      );
      await tester.tap(find.byKey(const Key('qwdtt-import')));
      await tester.pumpAndSettle();
      const source =
          'qwdtt://config?peer=server.example.invalid&pass=synthetic&hashes=synthetic_hash_123456';
      await tester.enterText(
        find.byKey(const Key('qwdtt-import-source')),
        source,
      );
      await tester.tap(find.byKey(const Key('qwdtt-import-confirm')));
      await tester.pumpAndSettle();
      expect(controller.calls.single.$1, 'import');
      expect(controller.calls.single.$2, {'source': source});
    },
  );
  testWidgets(
    'swipe deletion requires confirmation and sends the saved identifier',
    (tester) async {
      final controller = FakeQwdtt();
      await tester.pumpWidget(
        MaterialApp(home: QwdttPage(controller: controller)),
      );
      final row = find.byKey(const Key('qwdtt-swipe-synthetic-profile'));
      await tester.ensureVisible(row);
      await tester.drag(row, const Offset(-700, 0));
      await tester.pumpAndSettle();
      expect(find.text('Удалить подключение?'), findsOneWidget);
      expect(controller.calls, isEmpty);
      await tester.tap(find.text('Удалить'));
      await tester.pumpAndSettle();
      expect(controller.calls.single.$1, 'delete');
      expect(controller.calls.single.$2, {'id': 'synthetic-profile'});
    },
  );
  testWidgets(
    'ready state renders authoritative pipeline and real worker count',
    (tester) async {
      final controller = FakeQwdtt()..ready = true;
      await tester.pumpWidget(
        MaterialApp(home: QwdttPage(controller: controller)),
      );
      expect(find.text('qWDTT · Подключено'), findsOneWidget);
      expect(find.textContaining('2/2'), findsOneWidget);
    },
  );
}
