import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nym_bar/features/i18n/ui_controls_localization.dart';

void main() {
  testWidgets(
    'Russian Material controls localize calendar and editing actions',
    (tester) async {
      MaterialLocalizations? copy;
      await tester.pumpWidget(
        MaterialApp(
          locale: uiControlLocale('ru-RU'),
          localizationsDelegates: kUiControlDelegates,
          supportedLocales: kUiControlLocales,
          home: Builder(
            builder: (context) {
              copy = MaterialLocalizations.of(context);
              return const Scaffold(body: Text('Synthetic calendar'));
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(copy, isNotNull);
      expect(copy!.cancelButtonLabel.toLowerCase(), 'отмена');
      expect(copy!.copyButtonLabel.toLowerCase(), 'копировать');
      expect(copy!.formatMonthYear(DateTime(2026, 11)), contains('ноябр'));
      expect(tester.takeException(), isNull);
    },
  );
}
