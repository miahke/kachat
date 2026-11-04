import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nym_bar/core/constants/storage_keys.dart';
import 'package:nym_bar/services/storage/key_value_store.dart';
import 'package:nym_bar/models/settings.dart';
import 'package:nym_bar/features/composer/composer_model.dart';
import 'package:nym_bar/features/reactions/hover_actions.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('old synced Zap gestures migrate to safe actions while keeping other settings', () async {
    SharedPreferences.setMockInitialValues({
      StorageKeys.swipeLeftAction: 'zap',
      StorageKeys.swipeRightAction: 'zap',
      StorageKeys.hoverActions: '["react","zap","copy"]',
    });
    final settings = Settings.fromStore(await KeyValueStore.open());
    expect(settings.swipeLeftAction, 'quote');
    expect(settings.swipeRightAction, 'translate');
    expect(settings.hoverActions, isNot(contains('zap')));
    expect(kHoverActionIds, isNot(contains('zap')));
    expect(MainMenuItems.secondary, isNot(contains('shop')));
  });
}
