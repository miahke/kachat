import 'dart:io';

import 'package:nym_bar/features/zaps/zap_badge.dart';
import 'package:nym_bar/models/message.dart';
import 'package:nym_bar/state/app_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nym_bar/core/theme/nym_theme.dart';
import 'package:nym_bar/core/theme/nym_colors.dart';
import 'package:nym_bar/features/settings/about_screen.dart';
import 'package:nym_bar/features/messages/format/message_content.dart';
import 'package:nym_bar/features/payments/payment_policy.dart';
import 'package:nym_bar/features/shop/shop_modal.dart';

class _NoNetwork extends HttpOverrides {
  int calls = 0;
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    calls++;
    throw StateError('unexpected network client');
  }
}

ThemeData theme() => buildNymThemeData(
  resolveNymColors(
    theme: NymThemeKey.matrix,
    brightness: Brightness.dark,
    solidUi: true,
  ),
);
void main() {
  testWidgets('ordinary reactions have no payment notice; old receipts do', (
    tester,
  ) async {
    final message = Message(
      id: 'synthetic',
      author: 'Test',
      pubkey: 'test',
      content: 'hello',
      createdAt: 1,
    );
    Future<void> show(Map<String, MessageZaps> receipts) async {
      await tester.pumpWidget(
        ProviderScope(
          key: UniqueKey(),
          overrides: [zapsProvider.overrideWithValue(receipts)],
          child: MaterialApp(
            theme: theme(),
            home: Scaffold(body: ZapBadge(message: message)),
          ),
        ),
      );
    }

    await show({});
    expect(find.text(kPaymentsDisabled), findsNothing);
    await show({'synthetic': MessageZaps(totalSats: 1)});
    expect(find.text(kPaymentsDisabled), findsOneWidget);
  });
  testWidgets(
    'About names kachat and never checks upstream build/canary endpoints',
    (tester) async {
      final old = HttpOverrides.current, spy = _NoNetwork();
      HttpOverrides.global = spy;
      addTearDown(() => HttpOverrides.global = old);
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: theme(),
            home: const Scaffold(body: AboutScreen()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('kachat'), findsOneWidget);
      expect(find.text('Warrant canary'), findsNothing);
      expect(find.text('Build integrity'), findsNothing);
      expect(spy.calls, 0);
    },
  );
  testWidgets('encoded payment requests remain inert with a visible notice', (
    tester,
  ) async {
    const payload = 'lightning:lnbc1syntheticpayload1234567890';
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: theme(),
          home: const Scaffold(body: MessageContent(content: payload)),
        ),
      ),
    );
    expect(find.text(kPaymentsDisabled), findsOneWidget);
    expect(find.text(payload), findsOneWidget);
    expect(find.text('Pay'), findsNothing);
  });
  testWidgets(
    'obsolete shop routes show only the disabled-payment explanation',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: theme(),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => ShopModal.open(context),
                child: const Text('old route'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('old route'));
      await tester.pumpAndSettle();
      expect(find.text(kPaymentsDisabled), findsOneWidget);
      expect(find.text('Buy'), findsNothing);
    },
  );
}
