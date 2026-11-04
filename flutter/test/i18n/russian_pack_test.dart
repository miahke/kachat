import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nym_bar/features/commands/command_i18n.dart';
import 'package:nym_bar/features/i18n/app_strings_catalog.dart';

void main() {
  final pack = Map<String, String>.from(
    jsonDecode(File('assets/i18n/ru.json').readAsStringSync()) as Map,
  );
  test('Russian covers every static UI and command source offline', () {
    final required = {...kAppStringsCatalog, ...commandSourcePhrases()};
    final missing = required.where(
      (key) => !pack.containsKey(key) || pack[key]!.trim().isEmpty,
    );
    expect(
      missing,
      isEmpty,
      reason: 'Reviewed Russian must never depend on machine fallback',
    );
  });
  test(
    'translations retain placeholders and spaces between composed fragments',
    () {
      final placeholders = RegExp(r'\{\w+\}|%(?:\d+\$)?[ds]');
      Map<String, int> tokens(String text) {
        final result = <String, int>{};
        for (final match in placeholders.allMatches(text)) {
          result.update(match.group(0)!, (n) => n + 1, ifAbsent: () => 1);
        }
        return result;
      }

      for (final entry in pack.entries) {
        expect(entry.value.trim(), isNotEmpty, reason: entry.key);
        expect(tokens(entry.value), tokens(entry.key), reason: entry.key);
        if (entry.key.startsWith(' ')) {
          expect(entry.value.startsWith(' '), true, reason: entry.key);
        }
        if (entry.key.endsWith(' ')) {
          expect(entry.value.endsWith(' '), true, reason: entry.key);
        }
      }
    },
  );
}
