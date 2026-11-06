// Canonical notification-sound picker shared by Settings and the bell panel; both mount this one control.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/settings_provider.dart';
import '../i18n/i18n.dart';
import '../settings/settings_widgets.dart' show FormSelect;
import 'notifications_service.dart' show notificationsServiceProvider;

/// Notification-sound options in order.
List<({String value, String label})> notificationSoundOptions() => [
      (value: 'beep', label: tr('Classic Beep')),
      (value: 'low', label: tr('Low Tone')),
      (value: 'high', label: tr('High Ping')),
      (value: 'uhoh', label: tr('ICQ Uh-Oh')),
      (value: 'msnding', label: tr('MSN Alert')),
      (value: 'nudge', label: tr('MSN Nudge')),
      (value: 'nokia', label: tr('Nokia SMS')),
      (value: 'nokiatune', label: tr('Nokia Tune')),
      (value: 'dialup', label: tr('Dial-Up Modem')),
      (value: 'coin', label: tr('Mario Coin')),
      (value: 'oneup', label: tr('Mario 1-Up')),
      (value: 'powerup', label: tr('Mario Power-Up')),
      (value: 'secret', label: tr('Zelda Secret')),
      (value: 'gameboy', label: tr('Game Boy Boot')),
      (value: 'tetris', label: tr('Tetris')),
      (value: 'pokeheal', label: tr('Pokémon Heal')),
      (value: 'chirp', label: tr('Communicator Chirp')),
      (value: 'f1', label: tr('F1 Radio')),
      (value: 'none', label: tr('Silent')),
    ];

/// The single notification-sound control: persists `settings.sound` and previews the pick.
class NotificationSoundSelect extends ConsumerWidget {
  const NotificationSoundSelect({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FormSelect<String>(
      value: ref.watch(settingsProvider.select((s) => s.sound)),
      items: notificationSoundOptions(),
      onChanged: (v) {
        ref.read(settingsProvider.notifier).setSound(v);
        final svc = ref.read(notificationsServiceProvider);
        svc.resetSoundDedupe();
        unawaited(svc.playSound(v).catchError((_) {}));
      },
    );
  }
}
