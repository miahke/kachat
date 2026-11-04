import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../qwdtt/qwdtt_controller.dart';

class TorPage extends StatefulWidget {
  const TorPage({super.key, required this.controller});
  final QwdttController controller;
  @override
  State<TorPage> createState() => _TorPageState();
}

class _TorPageState extends State<TorPage> {
  final bridges = TextEditingController();
  final port = TextEditingController(text: '19050');
  String mode = 'WEBTUNNEL';
  final drafts = <String, String>{};
  String? localError;
  bool loaded = false;
  QwdttController get c => widget.controller;
  static const modes = {
    'WEBTUNNEL': 'WebTunnel',
    'OBFS4': 'obfs4',
    'SNOWFLAKE': 'Snowflake',
    'DIRECT_TOR': 'Tor без мостов',
  };
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final settings = await c.torSettings();
      if (!mounted) return;
      bridges.text = settings['bridges'] as String? ?? '';
      port.text = (settings['socksPort'] ?? 19050).toString();
      setState(() {
        mode = modes.containsKey(settings['mode'])
            ? settings['mode'] as String
            : 'WEBTUNNEL';
        drafts[mode] = bridges.text;
        loaded = true;
        localError = null;
      });
    } catch (_) {
      if (mounted) {
        setState(
          () => localError =
              'Не удалось прочитать настройки Tor. Повторите загрузку.',
        );
      }
    }
  }

  void changeMode(String value) {
    drafts[mode] = bridges.text;
    setState(() {
      mode = value;
      bridges.text = drafts[value] ?? '';
      localError = null;
    });
  }

  void detectMode(String value) {
    final line = value
        .split('\n')
        .map((s) => s.trim())
        .firstWhere(
          (s) => s.isNotEmpty && !s.startsWith('#'),
          orElse: () => '',
        );
    final first = line
        .replaceFirst(RegExp(r'^Bridge\s+'), '')
        .split(RegExp(r'\s+'))
        .first;
    final detected = {
      'obfs4': 'OBFS4',
      'webtunnel': 'WEBTUNNEL',
      'snowflake': 'SNOWFLAKE',
    }[first];
    if (detected != null && detected != mode) setState(() => mode = detected);
  }

  Future<void> connect() async {
    final number = int.tryParse(port.text.trim());
    if (number == null || number < 1024 || number > 65535) {
      setState(() => localError = 'Порт должен быть от 1024 до 65535.');
      return;
    }
    if ((mode == 'OBFS4' || mode == 'WEBTUNNEL') &&
        bridges.text.trim().isEmpty) {
      setState(() => localError = 'Вставьте хотя бы одну полную строку моста.');
      return;
    }
    setState(() => localError = null);
    await c.command('connectTor', {
      'mode': mode,
      'bridges': mode == 'DIRECT_TOR' ? '' : bridges.text.trim(),
      'socksPort': number,
    });
  }

  @override
  void dispose() {
    bridges.dispose();
    port.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Tor · Мосты и подключение')),
    body: ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        final active = c.route == 'TOR';
        final state = active ? c.state : 'STOPPED';
        final percent = state == 'READY'
            ? 100
            : state == 'STOPPED'
            ? 0
            : ((c.tor['percent'] as num?)?.toInt() ?? 0).clamp(0, 99);
        final stage = c.tor['stage'] as String? ?? 'STOPPED';
        final label = switch (stage) {
          'CONFIGURING' => 'Проверяем мосты',
          'LISTENING' => 'Запускаем локальный прокси',
          'BOOTSTRAPPING' => 'Подключаемся к сети Tor',
          'READY' => 'Tor подключён',
          'TIMEOUT' => 'Время ожидания истекло',
          'CONFIGURATION_ERROR' => 'Проверьте мосты и локальный порт',
          'BOOTSTRAP_ERROR' => 'Не удалось подключиться к сети Tor',
          _ => 'Tor остановлен',
        };
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      state == 'READY'
                          ? 'Tor подключён · 100 %'
                          : active && state != 'STOPPED'
                          ? '$label · $percent %'
                          : 'Tor не подключён',
                      key: const Key('tor-status'),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 12),
                    LinearProgressIndicator(
                      key: const Key('tor-progress'),
                      value: percent / 100,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Процент показывает загрузку сети Tor. Доступность серверов и доставку сообщений проверяем отдельно.',
                    ),
                    if (active && c.statusError != null)
                      Text(
                        c.statusError!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    if (active && state == 'READY')
                      TextButton.icon(
                        onPressed: c.probeState == 'checking'
                            ? null
                            : c.checkConnection,
                        icon: const Icon(Icons.network_check),
                        label: const Text('Проверить HTTPS-соединение'),
                      ),
                    if (active && c.probeMessage != null) Text(c.probeMessage!),
                    if (active && state != 'STOPPED')
                      TextButton(
                        onPressed: c.busy
                            ? null
                            : () => c.command('disconnect'),
                        child: const Text('Остановить Tor'),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              key: const Key('tor-mode'),
              initialValue: mode,
              decoration: const InputDecoration(labelText: 'Транспорт Tor'),
              items: modes.entries
                  .map(
                    (e) => DropdownMenuItem(value: e.key, child: Text(e.value)),
                  )
                  .toList(),
              onChanged: !loaded || c.busy
                  ? null
                  : (value) => changeMode(value!),
            ),
            const SizedBox(height: 12),
            if (mode != 'DIRECT_TOR') ...[
              TextField(
                key: const Key('tor-bridges'),
                enabled: loaded && !c.busy,
                controller: bridges,
                minLines: 4,
                maxLines: 9,
                maxLength: 32768,
                autocorrect: false,
                enableSuggestions: false,
                onChanged: detectMode,
                decoration: InputDecoration(
                  labelText: mode == 'SNOWFLAKE'
                      ? 'Своя строка Snowflake (необязательно)'
                      : 'Мосты — по одному на строке',
                  hintText: mode == 'OBFS4'
                      ? 'obfs4 адрес:порт fingerprint cert=… iat-mode=0'
                      : mode == 'WEBTUNNEL'
                      ? 'webtunnel адрес:порт fingerprint url=https://… ver=…'
                      : 'Пусто — использовать встроенные параметры Snowflake',
                ),
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () async {
                    final value = await Clipboard.getData('text/plain');
                    if (!mounted || value?.text == null) return;
                    bridges.text = value!.text!;
                    detectMode(bridges.text);
                  },
                  icon: const Icon(Icons.content_paste),
                  label: const Text('Вставить мосты'),
                ),
              ),
            ],
            if (mode == 'SNOWFLAKE')
              const Text(
                'Snowflake использует добровольческие прокси и публичные параметры Tor. Аккаунт или свой VPS не нужны. Первый запуск может занять несколько минут.',
              ),
            if (mode == 'DIRECT_TOR')
              const Text(
                'Соединение с сетью Tor без обходных транспортов. В сетях с блокировкой Tor выберите мосты или Snowflake.',
              ),
            ExpansionTile(
              title: const Text('Дополнительные параметры'),
              children: [
                TextField(
                  controller: port,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Локальный порт SOCKS5',
                  ),
                ),
              ],
            ),
            if (localError != null)
              Text(
                localError!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            if (c.error != null)
              Text(
                c.error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            if (!loaded && localError != null)
              TextButton(
                onPressed: load,
                child: const Text('Повторить загрузку настроек'),
              ),
            FilledButton.icon(
              key: const Key('tor-connect'),
              onPressed: loaded && !c.busy ? connect : null,
              icon: const Icon(Icons.shield_outlined),
              label: Text(c.busy ? 'Сохранение…' : 'Подключить Tor'),
            ),
            ExpansionTile(
              title: const Text('Журнал подключения'),
              children: [
                for (final event
                    in c.events
                        .where((e) => e['route'] == 'TOR')
                        .toList()
                        .reversed
                        .take(12))
                  ListTile(
                    dense: true,
                    title: Text(event['label'] as String? ?? ''),
                    trailing: event['progress'] is num
                        ? Text('${event['progress']} %')
                        : null,
                  ),
              ],
            ),
          ],
        );
      },
    ),
  );
}
