import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nym_bar/features/qwdtt/qwdtt_controller.dart';
import 'package:nym_bar/features/qwdtt/qwdtt_page.dart';

class FakeQwdtt extends QwdttController {
  final calls = <(String, Map<String, dynamic>?)>[];
  bool ready = false;
  String activeRoute = 'VK';
  @override
  String get route => activeRoute;
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
  Future<String> exportProfile(String id) async {
    calls.add(('export', {'id': id}));
    return 'qwdtt://config?pass=synthetic';
  }

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
      expect(find.text('qWDTT · Локальный прокси готов'), findsOneWidget);
      expect(find.textContaining('не подтверждает доступ'), findsOneWidget);
      expect(find.byIcon(Icons.check_circle), findsOneWidget);
      expect(find.textContaining('2/2'), findsOneWidget);
    },
  );
  testWidgets('editor preserves obfuscation and DNS selections on save', (
    tester,
  ) async {
    final controller = FakeQwdtt();
    await tester.pumpWidget(
      MaterialApp(
        home: QwdttProfileEditor(
          controller: controller,
          profile: {
            'id': 'synthetic-profile',
            'name': 'Synthetic profile',
            'serverHost': 'server.example.invalid',
            'obfuscation': 'video',
            'dns': 'doh-google',
          },
        ),
      ),
    );
    await tester.scrollUntilVisible(
      find.text('Дополнительные параметры'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Дополнительные параметры'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('qwdtt-obfuscation')));
    expect(find.text('Видеозвонок'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Сохранить'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Сохранить'));
    await tester.pumpAndSettle();
    final profile =
        jsonDecode(controller.calls.single.$2!['profile'] as String) as Map;
    expect(profile['obfuscation'], 'video');
    expect(profile['dns'], 'doh-google');
    expect(profile['route'], 'VK');
    expect(profile.containsKey('workers'), false);
  });

  testWidgets('invalid numeric settings stay in editor without saving', (
    tester,
  ) async {
    final controller = FakeQwdtt();
    await tester.pumpWidget(
      MaterialApp(
        home: QwdttProfileEditor(
          controller: controller,
          profile: {
            'id': 'synthetic-profile',
            'name': 'Synthetic profile',
            'serverHost': 'server.example.invalid',
          },
        ),
      ),
    );
    await tester.scrollUntilVisible(
      find.text('Дополнительные параметры'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Дополнительные параметры'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('qwdtt-field-socksPort')));
    await tester.enterText(
      find.byKey(const Key('qwdtt-field-socksPort')),
      '80',
    );
    await tester.scrollUntilVisible(
      find.text('Сохранить'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Сохранить'));
    await tester.pumpAndSettle();
    expect(controller.calls, isEmpty);
    expect(
      find.text('Локальный порт: допустимо от 1024 до 65535.'),
      findsOneWidget,
    );
  });
  testWidgets('Tor readiness never marks VK transport stages ready', (
    tester,
  ) async {
    final controller = FakeQwdtt()
      ..ready = true
      ..activeRoute = 'TOR';
    await tester.pumpWidget(
      MaterialApp(home: QwdttPage(controller: controller)),
    );
    expect(find.text('qWDTT · Выбран Tor'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle), findsNothing);
    expect(find.textContaining('2/2'), findsNothing);
  });

  testWidgets('sharing is explicit and explains included secrets before copy', (
    tester,
  ) async {
    final controller = FakeQwdtt();
    await tester.pumpWidget(
      MaterialApp(home: QwdttPage(controller: controller)),
    );
    expect(controller.calls, isEmpty);
    await tester.ensureVisible(find.byTooltip('Поделиться ключом'));
    await tester.tap(find.byTooltip('Поделиться ключом'));
    await tester.pumpAndSettle();
    expect(controller.calls.single.$1, 'export');
    expect(controller.calls.single.$2, {'id': 'synthetic-profile'});
    expect(find.textContaining('Ключ содержит пароль сервера'), findsOneWidget);
    expect(find.text('Скопировать ключ'), findsOneWidget);
    expect(find.textContaining('pass=synthetic'), findsNothing);
  });
}
