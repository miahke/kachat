import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nym_bar/core/constants/storage_keys.dart';
import 'package:nym_bar/features/mesh/mesh_outbox.dart';
import 'package:nym_bar/services/storage/at_rest_cipher.dart';
import 'package:nym_bar/services/storage/key_value_store.dart';
import 'package:nym_bar/services/storage/sealed_key_value.dart';
import 'package:nym_bar/state/nostr_controller.dart';
import 'package:nym_bar/state/settings_provider.dart';

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

class LockedKeys implements AtRestKeyStore {
  @override
  Future<String?> read() async => throw StateError('locked');
  @override
  Future<void> write(String value) async => throw StateError('locked');
  @override
  Future<void> delete() async {}
}

class SwitchableKeys extends MemoryKeys {
  bool locked = true;
  @override
  Future<String?> read() async {
    if (locked) throw StateError('locked');
    return super.read();
  }
}

class DelayedKeys extends MemoryKeys {
  final started = Completer<void>();
  final release = Completer<void>();
  @override
  Future<String?> read() async {
    if (!started.isCompleted) started.complete();
    await release.future;
    return super.read();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'controller migrates legacy queue and persists new message encrypted',
    () async {
      final old = MeshOutbox()
        ..add(
          MeshOutboxEntry(
            kind: MeshOutboxKind.pm,
            target: 'alice',
            content: 'old secret',
            createdAtSec: 100,
            localId: 'old',
          ),
        );
      SharedPreferences.setMockInitialValues({
        StorageKeys.meshOutbox: old.encode(),
      });
      final kv = await KeyValueStore.open();
      final original = AtRestCipher.instance;
      final cipher = AtRestCipher(MemoryKeys());
      AtRestCipher.instance = cipher;
      final container = ProviderContainer(
        overrides: [keyValueStoreProvider.overrideWithValue(kv)],
      );
      addTearDown(() {
        container.dispose();
        AtRestCipher.instance = original;
      });
      final controller = container.read(nostrControllerProvider);
      await controller.enqueueMeshOutbox(
        MeshOutboxEntry(
          kind: MeshOutboxKind.pm,
          target: 'alice',
          content: 'new secret',
          createdAtSec: 101,
          localId: 'new',
        ),
      );
      expect(
        kv.getString(StorageKeys.meshOutbox),
        startsWith(AtRestCipher.stringPrefix),
      );
      final saved = await SealedKeyValue(
        kv,
        cipher: cipher,
      ).read(StorageKeys.meshOutbox);
      final restored = MeshOutbox()..decode(saved);
      expect(restored.entries.map((e) => e.content), [
        'old secret',
        'new secret',
      ]);
    },
  );
  test('account switch waits for an in-flight encrypted queue write', () async {
    SharedPreferences.setMockInitialValues({});
    final kv = await KeyValueStore.open();
    final keys = DelayedKeys();
    final cipher = AtRestCipher(keys);
    final original = AtRestCipher.instance;
    AtRestCipher.instance = cipher;
    final container = ProviderContainer(
      overrides: [keyValueStoreProvider.overrideWithValue(kv)],
    );
    addTearDown(() {
      container.dispose();
      AtRestCipher.instance = original;
    });
    final controller = container.read(nostrControllerProvider);
    final enqueue = controller.enqueueMeshOutbox(
      MeshOutboxEntry(
        kind: MeshOutboxKind.pm,
        target: 'alice',
        content: 'queued secret',
        createdAtSec: 100,
        localId: 'one',
      ),
    );
    await keys.started.future;
    var switched = false;
    final switching = controller
        .suspendForAccountSwitch(drainBudget: const Duration(milliseconds: 100))
        .then((_) {
          switched = true;
        });
    await Future<void>.delayed(Duration.zero);
    expect(switched, isFalse);
    keys.release.complete();
    await enqueue;
    await switching;
    expect(switched, isTrue);
    final saved = await SealedKeyValue(
      kv,
      cipher: cipher,
    ).read(StorageKeys.meshOutbox);
    expect(saved, contains('queued secret'));
    expect(
      kv.getString(StorageKeys.meshOutbox),
      startsWith(AtRestCipher.stringPrefix),
    );
  });

  test(
    'controller reports encryption failure without overwriting legacy queue',
    () async {
      final old = MeshOutbox()
        ..add(
          MeshOutboxEntry(
            kind: MeshOutboxKind.pm,
            target: 'alice',
            content: 'old secret',
            createdAtSec: 100,
            localId: 'old',
          ),
        );
      final legacy = old.encode();
      SharedPreferences.setMockInitialValues({StorageKeys.meshOutbox: legacy});
      final kv = await KeyValueStore.open();
      final original = AtRestCipher.instance;
      AtRestCipher.instance = AtRestCipher(LockedKeys());
      final container = ProviderContainer(
        overrides: [keyValueStoreProvider.overrideWithValue(kv)],
      );
      addTearDown(() {
        container.dispose();
        AtRestCipher.instance = original;
      });
      final controller = container.read(nostrControllerProvider);
      await expectLater(
        controller.enqueueMeshOutbox(
          MeshOutboxEntry(
            kind: MeshOutboxKind.pm,
            target: 'alice',
            content: 'new secret',
            createdAtSec: 101,
            localId: 'new',
          ),
        ),
        throwsStateError,
      );
      expect(kv.getString(StorageKeys.meshOutbox), legacy);
    },
  );
  test('failed enqueue is not included in a later successful save', () async {
    SharedPreferences.setMockInitialValues({});
    final kv = await KeyValueStore.open();
    final keys = SwitchableKeys();
    final cipher = AtRestCipher(keys);
    final original = AtRestCipher.instance;
    AtRestCipher.instance = cipher;
    final container = ProviderContainer(
      overrides: [keyValueStoreProvider.overrideWithValue(kv)],
    );
    addTearDown(() { container.dispose(); AtRestCipher.instance = original; });
    final controller = container.read(nostrControllerProvider);
    MeshOutboxEntry entry(String id) => MeshOutboxEntry(
      kind: MeshOutboxKind.pm, target: 'alice', content: id,
      createdAtSec: 100, localId: id,
    );
    await expectLater(controller.enqueueMeshOutbox(entry('failed')), throwsStateError);
    keys.locked = false;
    await controller.enqueueMeshOutbox(entry('successful'));
    final saved = await SealedKeyValue(kv, cipher: cipher).read(StorageKeys.meshOutbox);
    final restored = MeshOutbox()..decode(saved);
    expect(restored.entries.map((e) => e.localId), ['successful']);
  });

}
