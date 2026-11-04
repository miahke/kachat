// SPDX-License-Identifier: AGPL-3.0-only
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

  Future<void> _export(String id) async {
    try {
      final source = await controller.exportProfile(id);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Ключ подключения qWDTT'),
          content: const Text(
            'Ключ содержит пароль сервера и хэш звонка. Передавайте его только тем, кому разрешён доступ. Личный пароль локального прокси и сессия VK не передаются.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Закрыть'),
            ),
            FilledButton.icon(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: source));
                if (context.mounted) Navigator.pop(context);
              },
              icon: const Icon(Icons.copy),
              label: const Text('Скопировать ключ'),
            ),
          ],
        ),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Не удалось создать ключ: проверьте сохранённый пароль сервера.',
            ),
          ),
        );
      }
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
        final ready = controller.route == 'VK' && controller.state == 'READY';
        final label = controller.route == 'TOR'
            ? 'Выбран Tor'
            : !controller.selected
            ? 'Прямое подключение'
            : switch (controller.state) {
                'READY' => 'Локальный прокси готов',
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
                    if (ready)
                      const Padding(
                        padding: EdgeInsets.only(top: 8),
                        child: Text(
                          'Готовность прокси не подтверждает доступ в интернет через сервер.',
                        ),
                      ),
                    const SizedBox(height: 12),
                    if (controller.route == 'VK' &&
                        controller.statistics['received'] == true)
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
                    if (controller.route == 'VK' && controller.mode != null)
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
                          ? 'При остановке или ошибке интернет-трафик kachat заблокирован. Прямого переключения нет.'
                          : 'Для обхода через VK TURN выберите сохранённый профиль и нажмите «Подключить».',
                    ),
                    if (controller.captchaPending)
                      FilledButton.icon(
                        onPressed: controller.captchaPresenting
                            ? null
                            : controller.solveCaptcha,
                        icon: const Icon(Icons.fact_check_outlined),
                        label: Text(
                          controller.captchaPresenting
                              ? 'Капча открыта…'
                              : 'Пройти капчу VK',
                        ),
                      ),
                    if (controller.selected && controller.state == 'READY') ...[
                      OutlinedButton.icon(
                        onPressed: controller.probeState == 'checking'
                            ? null
                            : controller.checkConnection,
                        icon: const Icon(Icons.network_check),
                        label: Text(
                          controller.probeState == 'checking'
                              ? 'Проверка…'
                              : 'Проверить соединение',
                        ),
                      ),
                      if (controller.probeMessage != null)
                        Text(controller.probeMessage!),
                    ],
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
                                  tooltip: 'Поделиться ключом',
                                  icon: const Icon(Icons.share_outlined),
                                  onPressed:
                                      controller.busy ||
                                          entry['hasPassword'] != true
                                      ? null
                                      : () => _export(id),
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
                            if (entry['hasPassword'] != true)
                              const Text(
                                'Нужен пароль сервера: укажите его в параметрах профиля.',
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
                'Маршрут: kachat → локальный прокси → qWDTT / VK TURN → ваш VPS → интернет. WebRTC-звонки и P2P не включаются в обход выбранного туннеля.',
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
    final progress =
        controller.route == 'VK' &&
        controller.selected &&
        controller.state != 'STOPPED';
    final ready = controller.route == 'VK' && controller.state == 'READY';
    final stages = controller.route == 'VK'
        ? controller.events.map((e) => e['stage']).toSet()
        : <dynamic>{};
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
                (progress && steps[i].$2)
                    ? Icons.check_circle
                    : Icons.radio_button_unchecked,
                size: 22,
                color: (progress && steps[i].$2)
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
    String? helper,
  }) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: TextField(
      key: Key('qwdtt-field-$key'),
      controller: fields[key],
      obscureText: secret,
      autocorrect: false,
      enableSuggestions: false,
      autofillHints: const [],
      maxLength: secret
          ? 4096
          : key == 'dns'
          ? 2048
          : 253,
      keyboardType: number
          ? const TextInputType.numberWithOptions(signed: true)
          : TextInputType.text,
      decoration: InputDecoration(
        labelText: label,
        helperText: helper,
        helperMaxLines: 3,
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
        'vkAnonPath': profile['vkAnonPath'] ?? 'vkcalls',
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
      _validate(out);
      if (widget.profile == null && fields['password']!.text.isEmpty) {
        throw const FormatException('Укажите пароль сервера.');
      }
      await widget.controller.command('save', {
        'profile': jsonEncode(out),
        'password': fields['password']!.text,
        'hash': fields['hash']!.text.trim(),
      });
      if (widget.controller.error != null) {
        throw FormatException(widget.controller.error!);
      }
      if (mounted) Navigator.pop(context);
    } on FormatException catch (exception) {
      if (mounted) {
        setState(
          () => error = exception.message.isEmpty
              ? 'Введите целые числа в полях портов, MTU и времени ожидания.'
              : exception.message.startsWith('Invalid radix') ||
                    exception.message.startsWith('Invalid number')
              ? 'Введите целые числа в полях портов, MTU и времени ожидания.'
              : exception.message,
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => error = 'Не удалось сохранить профиль. Повторите попытку.',
        );
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  void _validate(Map<String, dynamic> values) {
    void range(String key, String label, int min, int max) {
      final n = values[key] as int;
      if (n < min || n > max) {
        throw FormatException('$label: допустимо от $min до $max.');
      }
    }

    if ((values['name'] as String).isEmpty ||
        (values['name'] as String).length > 100) {
      throw const FormatException(
        'Название должно содержать от 1 до 100 символов.',
      );
    }
    final host = values['serverHost'] as String;
    if (host.isEmpty ||
        host.contains(RegExp(r'[\s/@?#]')) ||
        host.contains('://')) {
      throw const FormatException('Укажите адрес VPS без схемы, пути и порта.');
    }
    bool validHost(String host) {
      if (host.isEmpty || host.contains(RegExp(r'[\s/@?#]'))) return false;
      final authority = host.contains(':') ? '[$host]' : host;
      final parsed = Uri.tryParse('tcp://$authority');
      return parsed != null &&
          parsed.host.isNotEmpty &&
          !parsed.hasPort &&
          parsed.path.isEmpty &&
          parsed.userInfo.isEmpty;
    }

    if (!validHost(host)) {
      throw const FormatException('Укажите адрес VPS без схемы, пути и порта.');
    }
    final turn = values['turnHost'] as String;
    if (turn.isNotEmpty && !validHost(turn)) {
      throw const FormatException(
        'Укажите адрес TURN без схемы, пути и порта.',
      );
    }
    bool validIpv4(String value) {
      final parts = value.trim().split('.');
      return parts.length == 4 &&
          parts.every(
            (p) =>
                RegExp(r'^\d+$').hasMatch(p) &&
                int.tryParse(p) != null &&
                int.parse(p) <= 255,
          ) &&
          int.parse(parts.first) >= 1 &&
          int.parse(parts.first) <= 223;
    }

    final tunnelDns = values['tunnelDns'] as String;
    if (tunnelDns.isNotEmpty &&
        (tunnelDns.split(',').length > 4 ||
            !tunnelDns.split(',').every(validIpv4))) {
      throw const FormatException(
        'DNS внутри туннеля: укажите до четырёх IPv4 через запятую.',
      );
    }
    final dns = values['dns'] as String;
    if (!const [
      '',
      'yandex',
      'cloudflare',
      'google',
      'doh-yandex',
      'doh-cloudflare',
      'doh-google',
    ].contains(dns)) {
      var valid = false;
      final entries = dns.substring(dns.indexOf(':') + 1).split(',');
      if (entries.length <= 4 && dns.startsWith('custom:')) {
        valid = entries.every((e) {
          final parts = e.trim().split(':');
          return parts.length <= 2 &&
              validIpv4(parts.first) &&
              (parts.length == 1 ||
                  (int.tryParse(parts.last) ?? 0) >= 1 &&
                      (int.tryParse(parts.last) ?? 0) <= 65535);
        });
      } else if (entries.length <= 4 && dns.startsWith('doh:')) {
        valid = entries.every((e) {
          final uri = Uri.tryParse(e.trim());
          return uri != null &&
              uri.scheme == 'https' &&
              uri.host.isNotEmpty &&
              uri.userInfo.isEmpty &&
              !uri.hasFragment &&
              (!uri.hasPort || uri.port >= 1 && uri.port <= 65535);
        });
      }
      if (!valid) {
        throw const FormatException(
          'DNS для VK: выберите провайдера или укажите custom:IPv4 / doh:https://…',
        );
      }
    }
    range('serverPort', 'Порт сервера', 1, 65535);
    range('socksPort', 'Локальный порт', 1024, 65535);
    range('turnPort', 'TURN-порт', 0, 65535);
    range('fallbackPort', 'Порт RTP AEAD', 1, 65535);
    range('connectTimeoutSeconds', 'Ожидание подключения', 15, 300);
    range('handshakeTimeoutSeconds', 'Ожидание рукопожатия', 5, 60);
    range('configTimeoutSeconds', 'Ожидание конфигурации', 5, 60);
    range('wgKeepaliveSeconds', 'Поддержание связи WG', -1, 120);
    if (values['tunnelMtu'] != 0) range('tunnelMtu', 'MTU', 576, 1500);
    if ((values['username'] as String).isEmpty ||
        utf8.encode(values['username'] as String).length > 255) {
      throw const FormatException(
        'Логин прокси должен занимать от 1 до 255 байт.',
      );
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
        Text(
          'Основные параметры',
          style: Theme.of(context).textTheme.titleMedium,
        ),
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
            'Используются два транспортных канала. Обход действует только внутри kachat через локальный прокси; системный VPN не создаётся. Готовый ключ обычно уже содержит параметры сервера.',
          ),
        ),
        ExpansionTile(
          title: const Text('Дополнительные параметры'),
          children: [
            field('serverPort', 'Порт qWDTT на сервере', number: true),
            field('socksPort', 'Локальный порт SOCKS5', number: true),
            field('username', 'Логин локального прокси'),
            const Text(
              'Пароль локального прокси генерируется автоматически и хранится зашифрованным.',
            ),
            if (mode == 'WG')
              DropdownButtonFormField<String>(
                initialValue: transport,
                decoration: const InputDecoration(
                  labelText: 'Способ передачи до сервера',
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
            field(
              'fallbackPort',
              'Порт RTP AEAD в автоматическом режиме',
              number: true,
            ),
            SwitchListTile(
              title: const Text('TURN через TCP'),
              value: profile['turnTcp'] != false,
              onChanged: (value) => setState(() => profile['turnTcp'] = value),
            ),
            field('turnHost', 'Адрес TURN-сервера (пусто — сервер VK)'),
            field('turnPort', 'TURN-порт (0 — автоматически)', number: true),
            DropdownButtonFormField<String>(
              key: const Key('qwdtt-vk-path'),
              initialValue: profile['vkAnonPath'] as String? ?? 'vkcalls',
              decoration: const InputDecoration(
                labelText: 'Способ получения TURN в VK',
              ),
              items: const [
                DropdownMenuItem(
                  value: 'vkcalls',
                  child: Text('VK Звонки (рекомендуется)'),
                ),
                DropdownMenuItem(
                  value: 'legacy',
                  child: Text('Прежний способ (legacy)'),
                ),
              ],
              onChanged: (value) =>
                  setState(() => profile['vkAnonPath'] = value),
            ),
            DropdownButtonFormField<String>(
              key: const Key('qwdtt-obfuscation'),
              initialValue: profile['obfuscation'] as String? ?? 'audio',
              decoration: const InputDecoration(
                labelText: 'Маскировка трафика',
              ),
              items: const [
                DropdownMenuItem(value: 'audio', child: Text('Аудиозвонок')),
                DropdownMenuItem(value: 'video', child: Text('Видеозвонок')),
              ],
              onChanged: (value) =>
                  setState(() => profile['obfuscation'] = value),
            ),
            DropdownButtonFormField<String>(
              key: const Key('qwdtt-dns-preset'),
              initialValue:
                  const [
                    'yandex',
                    'cloudflare',
                    'google',
                    'doh-yandex',
                    'doh-cloudflare',
                    'doh-google',
                  ].contains(fields['dns']!.text)
                  ? fields['dns']!.text
                  : 'custom',
              decoration: const InputDecoration(labelText: 'DNS для VK'),
              items: const [
                DropdownMenuItem(
                  value: 'yandex',
                  child: Text('Яндекс DNS · UDP'),
                ),
                DropdownMenuItem(
                  value: 'cloudflare',
                  child: Text('Cloudflare · UDP'),
                ),
                DropdownMenuItem(
                  value: 'google',
                  child: Text('Google DNS · UDP'),
                ),
                DropdownMenuItem(
                  value: 'doh-yandex',
                  child: Text('Яндекс · DoH'),
                ),
                DropdownMenuItem(
                  value: 'doh-cloudflare',
                  child: Text('Cloudflare · DoH'),
                ),
                DropdownMenuItem(
                  value: 'doh-google',
                  child: Text('Google · DoH'),
                ),
                DropdownMenuItem(
                  value: 'custom',
                  child: Text('Свой DNS / DoH'),
                ),
              ],
              onChanged: (value) => setState(
                () => fields['dns']!.text = value == 'custom'
                    ? 'custom:'
                    : value!,
              ),
            ),
            field(
              'dns',
              'DNS/DoH для подключения транспорта',
              helper: 'Для VK API: custom:1.1.1.1,8.8.8.8 или doh:https://…/dns-query. Это не DNS приложений Android.',
            ),
            field(
              'tunnelDns',
              'DNS внутри туннеля (IPv4 через запятую)',
              helper: 'Пусто — DNS сервера. Используется для запросов через локальный прокси.',
            ),
            field('tunnelMtu', 'MTU (0 — автоматически)', number: true),
            field(
              'wgKeepaliveSeconds',
              'Поддержание связи WG, с (-1 — авто)',
              number: true,
            ),
            field(
              'connectTimeoutSeconds',
              'Время ожидания подключения, с',
              number: true,
            ),
            field(
              'handshakeTimeoutSeconds',
              'Время ожидания рукопожатия, с',
              number: true,
            ),
            field(
              'configTimeoutSeconds',
              'Время ожидания конфигурации, с',
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
          helperText:
              'Адрес сервера, пароль и хэши будут заполнены автоматически.',
          helperMaxLines: 3,
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
