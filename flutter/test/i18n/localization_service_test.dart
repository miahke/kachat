import 'dart:convert';

import 'package:intl/intl.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nym_bar/features/i18n/localization_service.dart';
import 'package:nym_bar/services/api/api_client.dart';
import 'package:nym_bar/services/storage/key_value_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final service = LocalizationService.instance;
  final originalLoader = service.packLoader;
  setUp(() {
    service.setLanguage('');
    service.resetPackStateForTest();
    SharedPreferences.setMockInitialValues({});
  });
  tearDown(() {
    service.setLanguage('');
    service.packLoader = originalLoader;
    service.resetPackStateForTest();
  });

  test('Russian ignores old machine cache and never sends UI text to translation API', () async {
    SharedPreferences.setMockInitialValues({
      'nym_ui_i18n_ru': jsonEncode({
        'v': LocalizationService.cacheVersion,
        'm': {'Unknown label': 'Неудачный старый перевод'},
      }),
    });
    var requests = 0;
    final api = ApiClient(
      client: MockClient((r) async {
        requests++;
        return http.Response(
          jsonEncode({
            'translatedText': 'Автоперевод',
            'detectedLanguage': 'en',
          }),
          200,
        );
      }),
    );
    addTearDown(api.dispose);
    service.packLoader = (_) async => jsonEncode({'Settings': 'Настройки'});
    service.configure(
      kv: await KeyValueStore.open(),
      language: 'ru',
      apiClient: api,
    );
    await Future<void>.delayed(Duration.zero);
    expect(service.translate('Settings'), 'Настройки');
    expect(service.translate('Unknown label'), 'Unknown label');
    service.prime(['Another missing label']);
    service.sweep(['Third missing label']);
    await Future<void>.delayed(const Duration(milliseconds: 350));
    expect(requests, 0);
    expect(service.isTranslating, false);
  });

  test('bundled Russian survives switching languages after persisted cache eviction', () async {
    var loads = 0;
    service.packLoader = (_) async {
      loads++;
      return jsonEncode({'Settings': 'Настройки'});
    };
    final kv = await KeyValueStore.open();
    service.configure(kv: kv, language: 'ru');
    await Future<void>.delayed(Duration.zero);
    expect(service.translate('Settings'), 'Настройки');
    service.setLanguage('');
    await kv.remove('nym_ui_i18n_ru');
    service.setLanguage('ru');
    await Future<void>.delayed(Duration.zero);
    expect(service.translate('Settings'), 'Настройки');
    expect(loads, 1);
  });

  test(
    'Russian regional locale and user-supplied placeholder text stay intact',
    () async {
      service.packLoader = (_) async =>
          jsonEncode({'Back to {nym}': 'Вернуться к {nym}'});
      service.configure(kv: await KeyValueStore.open(), language: 'ru-RU');
      await Future<void>.delayed(Duration.zero);
      expect(service.language, 'ru');
      expect(
        service.translate('Back to {nym}', {'nym': 'Nymchat user'}),
        'Вернуться к Nymchat user',
      );
    },
  );
  test('Russian counters use 1/2/5 forms, including teens and notification templates', () async {
    service.packLoader = (_) async => jsonEncode({
      '{n} messages': '{n} сообщений',
      '{count} new messages from {name}': '{count} новых сообщений от {name}',
      '{n} hours ago': '{n} часов назад',
      '{n} replies': '{n} ответов',
    });
    service.configure(kv: await KeyValueStore.open(), language: 'ru');
    await Future<void>.delayed(Duration.zero);
    for (final entry in {
      1: '1 сообщение',
      2: '2 сообщения',
      5: '5 сообщений',
      11: '11 сообщений',
      21: '21 сообщение',
      24: '24 сообщения',
      111: '111 сообщений',
      0: '0 сообщений',
    }.entries) {
      expect(service.translate('{n} messages', {'n': entry.key}), entry.value);
    }
    expect(
      service.translate('{count} new messages from {name}', {
        'count': 2,
        'name': 'Nymchat user',
      }),
      '2 новых сообщения от Nymchat user',
    );
    expect(service.translate('{n} hours ago', {'n': 21}), '21 час назад');
    expect(service.translate('{n} replies', {'n': '2K'}), '2K ответов');
  });
  test(
    'localized upstream developer and bot names are not rebranded',
    () async {
      service.packLoader = (_) async => jsonEncode({
        'Nymchat developer': 'Разработчик Nymchat',
        'Nymchat Bot': 'Бот Nymchat',
      });
      service.configure(kv: await KeyValueStore.open(), language: 'ru');
      await Future<void>.delayed(Duration.zero);
      expect(service.translate('Nymchat developer'), 'Разработчик Nymchat');
      expect(service.translate('Nymchat Bot'), 'Бот Nymchat');
    },
  );
  test('other languages retain their existing translation fallback', () async {
    var requests = 0;
    final api = ApiClient(
      client: MockClient((request) async {
        requests++;
        return http.Response(
          jsonEncode({'translatedText': 'Übersetzt', 'detectedLanguage': 'en'}),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );
    addTearDown(api.dispose);
    service.packLoader = (_) async => '{}';
    service.configure(
      kv: await KeyValueStore.open(),
      language: 'de',
      apiClient: api,
    );
    await Future<void>.delayed(Duration.zero);
    expect(
      service.translate('Synthetic label for fallback'),
      'Synthetic label for fallback',
    );
    await Future<void>.delayed(const Duration(milliseconds: 350));
    expect(requests, greaterThan(0));
    expect(service.translate('Synthetic label for fallback'), 'Übersetzt');
  });
  test(
    'Russian month names use local date data and reset after switching back',
    () async {
      service.packLoader = (_) async => '{}';
      service.configure(kv: await KeyValueStore.open(), language: 'ru');
      await Future<void>.delayed(Duration.zero);
      expect(
        DateFormat.yMMMMd().format(DateTime(2026, 11, 4)),
        contains('ноября'),
      );
      service.setLanguage('');
      expect(
        DateFormat.yMMMMd().format(DateTime(2026, 11, 4)),
        contains('November'),
      );
    },
  );
}
