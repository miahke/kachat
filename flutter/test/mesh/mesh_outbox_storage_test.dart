import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:nym_bar/core/constants/storage_keys.dart';
import 'package:nym_bar/services/storage/at_rest_cipher.dart';
import 'package:nym_bar/services/storage/key_value_store.dart';
import 'package:nym_bar/services/storage/sealed_key_value.dart';

class MemoryKeys implements AtRestKeyStore {
  String? value;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String value) async {
    this.value = value;
  }

  @override
  Future<void> delete() async {
    value = null;
  }
}

class UnavailableKeys implements AtRestKeyStore {
  @override
  Future<String?> read() async => throw StateError('locked');
  @override
  Future<void> write(String value) async => throw StateError('locked');
  @override
  Future<void> delete() async {}
}

class FailingPrefs extends InMemorySharedPreferencesStore {
  FailingPrefs(super.data) : super.withData();
  @override
  Future<bool> setValue(String valueType, String key, Object value) async =>
      false;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'legacy mesh outbox migrates and remains readable after restart',
    () async {
      SharedPreferences.setMockInitialValues({
        StorageKeys.meshOutbox: '[{"content":"secret"}]',
      });
      final kv = await KeyValueStore.open();
      final cipher = AtRestCipher(MemoryKeys());
      expect(StorageKeys.sealedPrefs, contains(StorageKeys.meshOutbox));
      final store = SealedKeyValue(kv, cipher: cipher);
      expect(
        await store.read(StorageKeys.meshOutbox),
        '[{"content":"secret"}]',
      );
      await store.idle;
      expect(
        kv.getString(StorageKeys.meshOutbox),
        startsWith(AtRestCipher.stringPrefix),
      );
      expect(
        await SealedKeyValue(kv, cipher: cipher).read(StorageKeys.meshOutbox),
        '[{"content":"secret"}]',
      );
    },
  );
  test(
    'failed encryption reports failure without replacing legacy data',
    () async {
      SharedPreferences.setMockInitialValues({
        StorageKeys.meshOutbox: 'legacy',
      });
      final kv = await KeyValueStore.open();
      final store = SealedKeyValue(kv, cipher: AtRestCipher(UnavailableKeys()));
      expect(
        await store.writeChecked(StorageKeys.meshOutbox, 'new secret'),
        isFalse,
      );
      expect(kv.getString(StorageKeys.meshOutbox), 'legacy');
    },
  );

  test('checked write persists ciphertext and can be read again', () async {
    SharedPreferences.setMockInitialValues({});
    final kv = await KeyValueStore.open();
    final cipher = AtRestCipher(MemoryKeys());
    final store = SealedKeyValue(kv, cipher: cipher);
    expect(
      await store.writeChecked(StorageKeys.meshOutbox, 'new secret'),
      isTrue,
    );
    expect(
      kv.getString(StorageKeys.meshOutbox),
      startsWith(AtRestCipher.stringPrefix),
    );
    expect(await store.read(StorageKeys.meshOutbox), 'new secret');
  });

  test(
    'failed persistent storage reports failure and preserves old data',
    () async {
      SharedPreferences.setMockInitialValues({});
      final backend = FailingPrefs({
        'flutter.${StorageKeys.meshOutbox}': 'legacy',
      });
      SharedPreferencesStorePlatform.instance = backend;
      final kv = await KeyValueStore.open();
      final store = SealedKeyValue(kv, cipher: AtRestCipher(MemoryKeys()));
      expect(
        await store.writeChecked(StorageKeys.meshOutbox, 'new secret'),
        isFalse,
      );
      expect(
        (await backend.getAll())['flutter.${StorageKeys.meshOutbox}'],
        'legacy',
      );
      KeyValueStore.dropHeld();
    },
  );
}
