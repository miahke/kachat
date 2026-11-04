import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nym_bar/features/qwdtt/qwdtt_controller.dart';
import 'package:nym_bar/features/qwdtt/qwdtt_admin_page.dart';

class FakeAdmin extends QwdttController {
  final calls = <(String, Map<String, dynamic>)>[];
  @override
  Future<dynamic> admin(String method, Map<String, dynamic> arguments) async {
    calls.add((method, arguments));
    if (method == 'sshProbe') {
      return 'SHA256:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA';
    }
    return {'access': []};
  }
}

void main() {
  testWidgets(
    'SSH credentials are sent only after explicit fingerprint acceptance',
    (tester) async {
      final controller = FakeAdmin();
      await tester.pumpWidget(
        MaterialApp(home: QwdttAdminPage(controller: controller)),
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Адрес VPS'),
        'server.example.invalid',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Пароль SSH'),
        'synthetic-password',
      );
      final button = find.text('Открыть панель подписок');
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(controller.calls.length, 1);
      expect(controller.calls.first.$1, 'sshProbe');
      expect(controller.calls.first.$2.containsKey('password'), false);
      await tester.tap(find.text('Отпечаток совпадает'));
      await tester.pumpAndSettle();
      expect(controller.calls.length, 2);
      expect(controller.calls.last.$1, 'sshAdmin');
      expect(controller.calls.last.$2['fingerprint'], startsWith('SHA256:'));
      expect(controller.calls.last.$2['password'], 'synthetic-password');
    },
  );
  testWidgets('cancelled fingerprint check never authenticates', (
    tester,
  ) async {
    final controller = FakeAdmin();
    await tester.pumpWidget(
      MaterialApp(home: QwdttAdminPage(controller: controller)),
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Адрес VPS'),
      'server.example.invalid',
    );
    final button = find.text('Открыть панель подписок');
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('Отмена'));
    await tester.pumpAndSettle();
    expect(controller.calls.length, 1);
    expect(controller.calls.single.$1, 'sshProbe');
  });
}
