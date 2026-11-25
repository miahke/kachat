import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nym_bar/core/constants/storage_keys.dart';
import 'package:nym_bar/services/storage/key_value_store.dart';
import 'package:nym_bar/state/app_state.dart';
import 'package:nym_bar/state/last_view.dart';

void main() {
  test('saved view restoration keeps the launch list open', () async {
    SharedPreferences.setMockInitialValues({StorageKeys.lastView: '#remembered'});
    final kv = await KeyValueStore.open();
    final app = AppStateNotifier();
    addTearDown(app.dispose);
    final restore = BootViewRestore(app, kv);
    restore.beforeGoLive();
    app.goLive('a' * 64, 'tester');
    restore.afterGoLive();
    final restoringDuringSwitch = <bool>[];
    app.viewSwitches.addListener(() {
      restoringDuringSwitch.add(app.restoringBootView);
    });

    expect(restore.apply(), const ChatView.channel('remembered'));
    expect(restoringDuringSwitch, [true]);
    expect(app.lastSwitchWasBootRestore, isTrue);
    expect(app.restoringBootView, isFalse);

    app.switchChannel('chosen');
    expect(restoringDuringSwitch, [true, false]);
    expect(app.lastSwitchWasBootRestore, isFalse);
  });

  test('explicit pre-boot navigation remains an open-chat request', () async {
    SharedPreferences.setMockInitialValues({});
    final kv = await KeyValueStore.open();
    final app = AppStateNotifier();
    addTearDown(app.dispose);
    final restore = BootViewRestore(app, kv);
    app.switchChannel('requested');
    restore.beforeGoLive();
    app.goLive('a' * 64, 'tester');
    restore.afterGoLive();

    expect(restore.apply(), const ChatView.channel('requested'));
    expect(app.lastSwitchWasBootRestore, isFalse);
  });
}
