// SPDX-License-Identifier: AGPL-3.0-only
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import 'qwdtt_controller.dart';
import 'qwdtt_admin_page.dart';

class QwdttPage extends StatefulWidget {
  const QwdttPage({super.key, this.controller});
  final QwdttController? controller;
  @override
  State<QwdttPage> createState() => _QwdttPageState();
}

class _QwdttPageState extends State<QwdttPage> {
  QwdttController get controller =>
      widget.controller ?? QwdttController.instance;
  @override
  void initState() {
    super.initState();
    controller.refresh();
  }

  Future<void> _import() async {
    final source = await showDialog<String>(
      context: context,
      builder: (_) => const _QwdttImportDialog(),
    );
    if (source != null && source.trim().isNotEmpty) {
      await controller.command('import', {'source': source.trim()});
    }
  }

  Future<void> _delete(String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удалить подключение?'),
        content: const Text(
          'Удалится сохранённый профиль и его реквизиты. Активный туннель будет остановлен.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (confirmed == true) await controller.command('delete', {'id': id});
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('qWDTT · Обход блокировок')),
    body: ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final ready = controller.state == 'READY';
        final label = !controller.selected
            ? 'Прямое подключение'
            : switch (controller.state) {
                'READY' => 'Подключено',
                'STARTING' => 'Подключение…',
                'RECONNECTING' => 'Переподключение…',
                'ERROR' => 'Ошибка подключения',
                _ => 'Туннель остановлен',
              };
        final profiles = controller.profiles;
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          ready ? Icons.lock : Icons.router_outlined,
                          color: controller.state == 'ERROR'
                              ? Theme.of(context).colorScheme.error
                              : Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'qWDTT · $label',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _QwdttPipeline(controller: controller),
                    const SizedBox(height: 12),
                    if (controller.statistics['received'] == true)
                      Wrap(
                        spacing: 12,
                        runSpacing: 4,
                        children: [
                          Text('Каналы: ${controller.statistics['workers']}/2'),
                          Semantics(
                            label: 'Отправлено',
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.arrow_upward, size: 16),
                                const SizedBox(width: 4),
                                Text(_bytes(controller.statistics['up'])),
                              ],
                            ),
                          ),
                          Semantics(
                            label: 'Получено',
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.arrow_downward, size: 16),
                                const SizedBox(width: 4),
                                Text(_bytes(controller.statistics['down'])),
                              ],
                            ),
                          ),
                        ],
                      ),
                    if (controller.mode != null)
                      Text(
                        '${controller.mode == 'RAW' ? 'Защищённый Raw' : 'WireGuard'}${controller.dtls == null
                            ? ''
                            : controller.dtls!
                            ? ' · DTLS'
                            : ' · RTP AEAD'}',
                      ),
                    const SizedBox(height: 12),
                    Text(
                      controller.selected
                          ? 'При остановке или ошибке интернет-трафик заблокирован. Прямого переключения нет.'
                          : 'Для обхода через VK TURN выберите сохранённый профиль и нажмите «Подключить».',
                    ),
                    if (controller.selected)
                      Wrap(
                        spacing: 8,
                        children: [
                          OutlinedButton(
                            onPressed: controller.busy
                                ? null
                                : () => controller.command('disconnect'),
                            child: const Text('Остановить туннель'),
                          ),
                          TextButton(
                            onPressed: controller.busy
                                ? null
                                : () => controller.command('direct'),
                            child: const Text('Включить прямое подключение'),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
            if (controller.error != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  controller.error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            const SizedBox(height: 12),
            FilledButton.icon(
              key: const Key('qwdtt-import'),
              onPressed: controller.busy ? null : _import,
              icon: const Icon(Icons.add_link),
              label: const Text('Вставить ключ подключения'),
            ),
            TextButton.icon(
              onPressed: controller.busy
                  ? null
                  : () => Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) =>
                            QwdttProfileEditor(controller: controller),
                      ),
                    ),
              icon: const Icon(Icons.tune),
              label: const Text('Настроить вручную'),
            ),
            const SizedBox(height: 12),
            if (profiles.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'Подключений пока нет. Получите ключ у администратора или укажите свой сервер и готовый хэш звонка.',
                ),
              ),
            for (final entry in profiles)
              Builder(
                builder: (context) {
                  final profile = Map<String, dynamic>.from(
                    entry['profile'] as Map,
                  );
                  final id = profile['id'] as String;
                  return Dismissible(
                    key: Key('qwdtt-swipe-$id'),
                    direction: DismissDirection.endToStart,
                    background: Container(
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.all(20),
                      color: Theme.of(context).colorScheme.errorContainer,
                      child: const Icon(Icons.delete_outline),
                    ),
                    confirmDismiss: (_) async {
                      if (!controller.busy) {
                        await _delete(id);
                      }
                      return false;
                    },
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    profile['name'] as String? ?? 'qWDTT',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleSmall,
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'Изменить профиль',
                                  icon: const Icon(Icons.edit_outlined),
                                  onPressed: controller.busy
                                      ? null
                                      : () => Navigator.push(
                                          context,
                                          MaterialPageRoute<void>(
                                            builder: (_) => QwdttProfileEditor(
                                              controller: controller,
                                              profile: profile,
                                            ),
                                          ),
                                        ),
                                ),
                                IconButton(
                                  tooltip: 'Удалить профиль',
                                  icon: const Icon(Icons.delete_outline),
                                  onPressed: controller.busy
                                      ? null
                                      : () => _delete(id),
                                ),
                              ],
                            ),
                            Text(
                              '${profile['vkMode'] == 'RAW' ? 'Raw v2' : 'WireGuard'} · SOCKS 127.0.0.1:${(profile['socksPort'] as num?)?.toInt() ?? 1080}',
                            ),
                            if (entry['hasHash'] != true)
                              const Text(
                                'Нужен хэш звонка: вставьте его в редакторе или получите через вход VK.',
                              ),
                            const SizedBox(height: 8),
                            FilledButton.tonal(
                              key: Key('qwdtt-connect-$id'),
                              onPressed:
                                  controller.busy ||
                                      entry['hasHash'] != true ||
                                      entry['hasPassword'] != true
                                  ? null
                                  : () => controller.command('connect', {
                                      'id': id,
                                    }),
                              child: Text(
                                controller.selected &&
                                        controller.activeId == id &&
                                        ready
                                    ? 'Переподключить'
                                    : 'Подключить',
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            const SizedBox(height: 12),
            Card(
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.account_circle_outlined),
                    title: const Text('VK для получения хэшей'),
                    subtitle: Text(
                      controller.vkLoggedIn
                          ? 'Сессия сохранена только на этом устройстве'
                          : 'Готовые хэши работают без входа в аккаунт',
                    ),
                    trailing: TextButton(
                      onPressed: controller.busy
                          ? null
                          : () => controller.command(
                              controller.vkLoggedIn ? 'logoutVk' : 'loginVk',
                            ),
                      child: Text(controller.vkLoggedIn ? 'Выйти' : 'Войти'),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: ListTile(
                leading: const Icon(Icons.dns_outlined),
                title: const Text('Сервер и подписки'),
                subtitle: const Text(
                  'Развернуть qWDTT на VPS и выдать доступ друзьям',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => QwdttAdminPage(controller: controller),
                  ),
                ),
              ),
            ),
            ExpansionTile(
              title: const Text('Сведения о подключении'),
              subtitle: const Text(
                'Этапы текущего процесса без ключей и адресов',
              ),
              children: [
                for (final event in controller.events)
                  ListTile(
                    dense: true,
                    title: Text(
                      event['label'] as String? ?? 'Событие транспорта',
                    ),
                  ),
              ],
            ),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Text(
                'Маршрут: NYM → локальный прокси → qWDTT / VK TURN → ваш VPS → интернет. WebRTC-звонки и P2P не включаются в обход выбранного туннеля.',
              ),
            ),
          ],
        );
      },
    ),
  );
  String _bytes(dynamic value) {
    final n = (value as num?)?.toDouble() ?? 0;
    if (n >= 1048576) return '${(n / 1048576).toStringAsFixed(1)} МБ';
    if (n >= 1024) return '${(n / 1024).toStringAsFixed(1)} КБ';
    return '${n.toInt()} Б';
  }
}

class _QwdttPipeline extends StatelessWidget {
  const _QwdttPipeline({required this.controller});
  final QwdttController controller;
  @override
  Widget build(BuildContext context) {
    final progress = controller.selected && controller.state != 'STOPPED';
    final ready = controller.state == 'READY';
    final stages = controller.events.map((e) => e['stage']).toSet();
    final steps = <(String, bool)>[
      ('VK', stages.contains('VK_CREDENTIALS')),
      ('TURN', stages.contains('TURN_READY')),
      (
        controller.mode == 'RAW' ? 'Raw' : 'WG',
        stages.contains('WIREGUARD_READY') || stages.contains('RAW_READY'),
      ),
      ('SOCKS', ready),
    ];
    return Row(
      children: [
        for (var i = 0; i < steps.length; i++) ...[
          if (i > 0)
            Expanded(
              child: Divider(
                color: ready ? Theme.of(context).colorScheme.primary : null,
              ),
            ),
          Column(
            children: [
              Icon(
                ready || (progress && steps[i].$2)
                    ? Icons.check_circle
                    : Icons.radio_button_unchecked,
                size: 22,
                color: ready || (progress && steps[i].$2)
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context).colorScheme.outline,
              ),
              const SizedBox(height: 4),
              Text(steps[i].$1, style: Theme.of(context).textTheme.labelSmall),
            ],
          ),
        ],
      ],
    );
  }
}

class QwdttProfileEditor extends StatefulWidget {
  const QwdttProfileEditor({super.key, required this.controller, this.profile});
  final QwdttController controller;
  final Map<String, dynamic>? profile;
  @override
  State<QwdttProfileEditor> createState() => _QwdttProfileEditorState();
}

class _QwdttProfileEditorState extends State<QwdttProfileEditor> {
  final fields = <String, TextEditingController>{};
  late Map<String, dynamic> profile;
  late String mode;
  late String transport;
  bool saving = false;
  String? error;
  @override
  void initState() {
    super.initState();
    profile = {...?widget.profile};
    profile.putIfAbsent('id', () => const Uuid().v4());
    profile.putIfAbsent('deviceId', () => const Uuid().v4());
    mode = profile['vkMode'] as String? ?? 'WG';
    transport = profile['noDtls'] == true
        ? 'RTP'
        : profile['autoPeerMode'] == false
        ? 'DTLS'
        : 'AUTO';
    final defaults = <String, dynamic>{
      'name': 'qWDTT',
      'serverHost': '',
      'serverPort': mode == 'RAW' ? 56003 : 56000,
      'socksPort': 1080,
      'username': 'panchat',
      'turnHost': '',
      'turnPort': 0,
      'fallbackPort': 56002,
      'connectTimeoutSeconds': 90,
      'handshakeTimeoutSeconds': 20,
      'configTimeoutSeconds': 15,
      'tunnelDns': '',
      'tunnelMtu': 0,
      'wgKeepaliveSeconds': -1,
      'dns': 'doh-cloudflare',
      'hash': '',
      'password': '',
    };
    for (final e in defaults.entries) {
      final value = profile[e.key] ?? e.value;
      fields[e.key] = TextEditingController(
        text: value is num ? value.toInt().toString() : value.toString(),
      );
    }
  }

  @override
  void dispose() {
    for (final field in fields.values) {
      field.dispose();
    }
    super.dispose();
  }

  Widget field(
    String key,
    String label, {
    bool secret = false,
    bool number = false,
  }) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: TextField(
      controller: fields[key],
      obscureText: secret,
      autocorrect: false,
      enableSuggestions: false,
      autofillHints: const [],
      maxLength: secret ? 4096 : 253,
      keyboardType: number
          ? const TextInputType.numberWithOptions(signed: true)
          : TextInputType.text,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        counterText: '',
      ),
    ),
  );
  Future<void> save() async {
    setState(() {
      saving = true;
      error = null;
    });
    try {
      final out = {
        ...profile,
        'route': 'VK',
        'vkMode': mode,
        'autoPeerMode': transport == 'AUTO',
        'noDtls': transport == 'RTP',
        'turnTcp': profile['turnTcp'] ?? true,
        'obfuscation': profile['obfuscation'] ?? 'audio',
      };
      for (final e in fields.entries) {
        if (e.key == 'hash' || e.key == 'password') continue;
        out[e.key] =
            {
              'serverPort',
              'socksPort',
              'turnPort',
              'fallbackPort',
              'connectTimeoutSeconds',
              'handshakeTimeoutSeconds',
              'configTimeoutSeconds',
              'tunnelMtu',
              'wgKeepaliveSeconds',
            }.contains(e.key)
            ? int.parse(e.value.text.trim())
            : e.value.text.trim();
      }
      if ((out['serverHost'] as String).isEmpty ||
          (out['name'] as String).isEmpty) {
        throw const FormatException();
      }
      await widget.controller.command('save', {
        'profile': jsonEncode(out),
        'password': fields['password']!.text,
        'hash': fields['hash']!.text.trim(),
      });
      if (widget.controller.error != null) throw const FormatException();
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        setState(
          () => error = 'Проверьте сервер, порты и реквизиты. Для нового профиля нужен пароль сервера.',
        );
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        widget.profile == null ? 'Новое подключение' : 'Параметры qWDTT',
      ),
    ),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        field('name', 'Название'),
        field('serverHost', 'Адрес VPS без порта'),
        DropdownButtonFormField<String>(
          initialValue: mode,
          decoration: const InputDecoration(labelText: 'Режим туннеля'),
          items: const [
            DropdownMenuItem(value: 'WG', child: Text('WireGuard')),
            DropdownMenuItem(value: 'RAW', child: Text('Защищённый Raw v2')),
          ],
          onChanged: (value) => setState(() {
            mode = value!;
            if ({
              '56000',
              '56002',
              '56003',
            }.contains(fields['serverPort']!.text)) {
              fields['serverPort']!.text = mode == 'RAW'
                  ? '56003'
                  : transport == 'RTP'
                  ? '56002'
                  : '56000';
            }
          }),
        ),
        field(
          'password',
          widget.profile == null
              ? 'Пароль сервера'
              : 'Новый пароль сервера (пусто — сохранить прежний)',
          secret: true,
        ),
        field(
          'hash',
          'Хэш звонка или ссылка VK (пусто — сохранить прежний)',
          secret: true,
        ),
        if (widget.controller.vkLoggedIn)
          TextButton.icon(
            onPressed: saving
                ? null
                : () async {
                    try {
                      final hash = await widget.controller.generateHash();
                      if (mounted) fields['hash']!.text = hash;
                    } catch (_) {
                      if (mounted) {
                        setState(
                          () => error = 'VK не выдал хэш. Повторите вход или вставьте готовый.',
                        );
                      }
                    }
                  },
            icon: const Icon(Icons.call_outlined),
            label: const Text('Получить новый хэш VK'),
          ),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 12),
          child: Text(
            'Используются два транспортных канала. Готовый ключ подключения обычно уже содержит необходимые параметры.',
          ),
        ),
        ExpansionTile(
          title: const Text('Дополнительные параметры'),
          children: [
            field('serverPort', 'Порт выхода на VPS', number: true),
            field('socksPort', 'Локальный порт SOCKS5', number: true),
            field('username', 'Логин локального прокси'),
            const Text(
              'Пароль локального прокси генерируется автоматически и хранится зашифрованным.',
            ),
            if (mode == 'WG')
              DropdownButtonFormField<String>(
                initialValue: transport,
                decoration: const InputDecoration(
                  labelText: 'Транспорт до VPS',
                ),
                items: const [
                  DropdownMenuItem(
                    value: 'AUTO',
                    child: Text('Авто: DTLS / RTP AEAD'),
                  ),
                  DropdownMenuItem(value: 'DTLS', child: Text('DTLS')),
                  DropdownMenuItem(value: 'RTP', child: Text('RTP AEAD')),
                ],
                onChanged: (value) => setState(() {
                  transport = value!;
                  if ({'56000', '56002'}.contains(fields['serverPort']!.text)) {
                    fields['serverPort']!.text = transport == 'RTP'
                        ? '56002'
                        : '56000';
                  }
                }),
              ),
            field('fallbackPort', 'Порт RTP AEAD для авто', number: true),
            SwitchListTile(
              title: const Text('TURN через TCP'),
              value: profile['turnTcp'] != false,
              onChanged: (value) => setState(() => profile['turnTcp'] = value),
            ),
            field('turnHost', 'Свой TURN-хост (пусто — VK)'),
            field('turnPort', 'TURN-порт (0 — автоматически)', number: true),
            field('dns', 'DNS/DoH для подключения транспорта'),
            field('tunnelDns', 'DNS внутри туннеля (IPv4 через запятую)'),
            field('tunnelMtu', 'MTU (0 — автоматически)', number: true),
            field(
              'wgKeepaliveSeconds',
              'WG keepalive (-1 — автоматически)',
              number: true,
            ),
            field(
              'connectTimeoutSeconds',
              'Таймаут подключения, секунд',
              number: true,
            ),
            field(
              'handshakeTimeoutSeconds',
              'Таймаут рукопожатия, секунд',
              number: true,
            ),
            field(
              'configTimeoutSeconds',
              'Таймаут конфигурации, секунд',
              number: true,
            ),
          ],
        ),
        if (error != null)
          Text(
            error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: saving ? null : save,
          child: Text(saving ? 'Сохранение…' : 'Сохранить'),
        ),
      ],
    ),
  );
}

class _QwdttImportDialog extends StatefulWidget {
  const _QwdttImportDialog();
  @override
  State<_QwdttImportDialog> createState() => _QwdttImportDialogState();
}

class _QwdttImportDialogState extends State<_QwdttImportDialog> {
  final text = TextEditingController();
  @override
  void dispose() {
    text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Вставить ключ qWDTT'),
    content: SizedBox(
      width: 440,
      child: TextField(
        key: const Key('qwdtt-import-source'),
        controller: text,
        minLines: 3,
        maxLines: 7,
        maxLength: 131072,
        autocorrect: false,
        enableSuggestions: false,
        decoration: const InputDecoration(
          hintText: 'qwdtt://config?… или JSON подписки',
          helperText: 'Сервер, пароль и хэши извлекутся автоматически.',
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Отмена'),
      ),
      FilledButton(
        key: const Key('qwdtt-import-confirm'),
        onPressed: () => Navigator.pop(context, text.text),
        child: const Text('Импортировать'),
      ),
    ],
  );
}
