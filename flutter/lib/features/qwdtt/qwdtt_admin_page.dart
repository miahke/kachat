// SPDX-License-Identifier: AGPL-3.0-only
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'qwdtt_controller.dart';

/// Credentials exist only while this page is open; no restoration or preference writes.
class QwdttAdminPage extends StatefulWidget {
  const QwdttAdminPage({super.key, required this.controller});
  final QwdttController controller;
  @override
  State<QwdttAdminPage> createState() => _QwdttAdminPageState();
}

class _QwdttAdminPageState extends State<QwdttAdminPage> {
  final host = TextEditingController(),
      port = TextEditingController(text: '22'),
      user = TextEditingController(text: 'root');
  final password = TextEditingController(),
      privateKey = TextEditingController(),
      passphrase = TextEditingController();
  String? fingerprint, pinnedTarget, status;
  bool busy = false, keyAuth = false;
  List<Map<String, dynamic>> access = [];
  @override
  void dispose() {
    for (final c in [host, port, user, password, privateKey, passphrase]) {
      c.clear();
      c.dispose();
    }
    super.dispose();
  }

  String get target =>
      '${host.text.trim()}:${port.text.trim()}:${user.text.trim()}';
  Map<String, dynamic> arguments({bool credentials = true}) => {
    'host': host.text.trim(),
    'port': int.parse(port.text.trim()),
    'username': user.text.trim(),
    'fingerprint': fingerprint ?? '',
    if (credentials)
      ...keyAuth
          ? {'key': privateKey.text, 'passphrase': passphrase.text}
          : {'password': password.text},
  };
  Future<bool> pin() async {
    if (fingerprint != null && pinnedTarget == target) return true;
    fingerprint = null;
    access = [];
    final observed = await widget.controller.admin(
      'sshProbe',
      arguments(credentials: false),
    ) as String;
    if (!mounted) return false;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Проверить сервер SSH'),
        content: SelectableText(
          'Сверьте отпечаток с консолью вашего VPS:\n\n$observed\n\nПароль и ключ ещё не передавались. SSH-настройка подключается к VPS напрямую.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Отпечаток совпадает'),
          ),
        ],
      ),
    );
    if (confirmed != true) return false;
    fingerprint = observed;
    pinnedTarget = target;
    return true;
  }

  Future<void> run(
    String method, {
    String action = 'list',
    Map<String, String> fields = const {},
  }) async {
    if (busy) return;
    setState(() {
      busy = true;
      status = null;
    });
    try {
      if (!await pin()) return;
      if (!mounted) return;
      final result = Map<String, dynamic>.from(
        await widget.controller.admin(method, {
          ...arguments(),
          'action': action,
          'fields': fields,
        }) as Map,
      );
      if (!mounted) return;
      setState(() {
        if (result['access'] is List) {
          access = (result['access'] as List)
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
        }
        status = method == 'sshDeploy'
            ? 'Сервер qWDTT установлен и проверен. Теперь создайте доступ.'
            : 'Панель обновлена.';
      });
    } catch (_) {
      if (mounted) {
        setState(
          () => status = 'Не удалось выполнить действие. Проверьте SSH, отпечаток и права root или sudo без пароля. Деплоер поддерживает Debian x86_64.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> deploy() async {
    final approved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Установить qWDTT на VPS?'),
        content: const Text(
          'Будут созданы службы qWDTT и панель подписок, ключи и правила маршрутизации. Нужен Debian x86_64 и root либо sudo без пароля. Используйте свой сервер.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Установить'),
          ),
        ],
      ),
    );
    if (approved == true) await run('sshDeploy');
  }

  Future<void> create() async {
    final fields = await showDialog<Map<String, String>>(
      context: context,
      builder: (_) => const _AccessDialog(),
    );
    if (fields != null) await run('sshAdmin', action: 'create', fields: fields);
  }

  Future<void> change(Map<String, dynamic> row, String action) async {
    final approved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Изменить доступ?'),
        content: Text(
          action == 'delete'
              ? 'Доступ будет удалён без восстановления.'
              : action == 'deactivate'
              ? 'Подключения с этим ключом будут запрещены.'
              : 'Доступ снова станет активным.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Продолжить'),
          ),
        ],
      ),
    );
    if (approved == true) {
      await run(
        'sshAdmin',
        action: action,
        fields: {'password': row['password'] as String},
      );
    }
  }

  Widget field(
    TextEditingController c,
    String label, {
    bool secret = false,
    int lines = 1,
  }) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: TextField(
      controller: c,
      enabled: !busy,
      obscureText: secret && lines == 1,
      maxLines: lines,
      minLines: 1,
      autocorrect: false,
      enableSuggestions: false,
      autofillHints: const [],
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
    ),
  );
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Сервер и подписки qWDTT')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'Администрирование своего VPS через SSH. Его адрес используется напрямую только для этих действий. Трафик чатов идёт по выбранному маршруту.',
        ),
        const SizedBox(height: 12),
        field(host, 'Адрес VPS'),
        Row(
          children: [
            Expanded(child: field(port, 'Порт SSH')),
            const SizedBox(width: 12),
            Expanded(child: field(user, 'Пользователь')),
          ],
        ),
        SwitchListTile(
          title: const Text('Вход по закрытому ключу'),
          value: keyAuth,
          onChanged: busy ? null : (v) => setState(() => keyAuth = v),
        ),
        if (keyAuth) ...[
          field(privateKey, 'Закрытый ключ SSH', lines: 5),
          field(passphrase, 'Пароль ключа (если есть)', secret: true),
        ] else
          field(password, 'Пароль SSH', secret: true),
        const Text(
          'Реквизиты SSH не сохраняются. Отпечаток проверяется до отправки пароля или ключа.',
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: busy ? null : deploy,
          icon: const Icon(Icons.cloud_upload_outlined),
          label: const Text('Установить qWDTT на сервер'),
        ),
        OutlinedButton.icon(
          onPressed: busy ? null : () => run('sshAdmin'),
          icon: const Icon(Icons.refresh),
          label: const Text('Открыть панель подписок'),
        ),
        if (busy)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Column(
              children: [
                LinearProgressIndicator(),
                SizedBox(height: 8),
                Text('Проверка SSH и выполнение операции…'),
              ],
            ),
          ),
        if (status != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(status!),
          ),
        OutlinedButton.icon(
          onPressed: busy ? null : create,
          icon: const Icon(Icons.person_add_alt),
          label: const Text('Создать доступ другу'),
        ),
        for (final row in access)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    row['label'] as String? ?? 'Доступ',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  Text(
                    '${row['revoked'] == true ? 'Отключён' : 'Активен'} · устройств: ${row['devices']}',
                  ),
                  Text(
                    'Действует до: ${DateTime.fromMillisecondsSinceEpoch(((row['expiresAt'] as num?)?.toInt() ?? 0) * 1000).toLocal().toString().split('.').first}',
                  ),
                  Wrap(
                    spacing: 8,
                    children: [
                      TextButton(
                        onPressed: busy
                            ? null
                            : () async {
                                final ok = await showDialog<bool>(
                                  context: context,
                                  builder: (context) => AlertDialog(
                                    title: const Text(
                                      'Скопировать ключ подключения?',
                                    ),
                                    content: const Text(
                                      'Ключ содержит пароль доступа. Передавайте его только получателю.',
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.pop(context, false),
                                        child: const Text('Отмена'),
                                      ),
                                      FilledButton(
                                        onPressed: () =>
                                            Navigator.pop(context, true),
                                        child: const Text('Копировать'),
                                      ),
                                    ],
                                  ),
                                );
                                if (ok == true) {
                                  await Clipboard.setData(
                                    ClipboardData(
                                      text: row['subscription'] as String,
                                    ),
                                  );
                                }
                              },
                        child: const Text('Копировать ключ'),
                      ),
                      TextButton(
                        onPressed: busy
                            ? null
                            : () => widget.controller.command('import', {
                                'source': row['subscription'],
                              }),
                        child: const Text('Добавить себе'),
                      ),
                      TextButton(
                        onPressed: busy
                            ? null
                            : () => change(
                                row,
                                row['revoked'] == true
                                    ? 'activate'
                                    : 'deactivate',
                              ),
                        child: Text(
                          row['revoked'] == true ? 'Включить' : 'Отключить',
                        ),
                      ),
                      TextButton(
                        onPressed: busy ? null : () => change(row, 'delete'),
                        child: const Text('Удалить'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
      ],
    ),
  );
}

class _AccessDialog extends StatefulWidget {
  const _AccessDialog();
  @override
  State<_AccessDialog> createState() => _AccessDialogState();
}

class _AccessDialogState extends State<_AccessDialog> {
  final name = TextEditingController(),
      hash = TextEditingController(),
      days = TextEditingController(text: '30'),
      devices = TextEditingController(text: '2');
  String? error;
  @override
  void dispose() {
    for (final c in [name, hash, days, devices]) {
      c.clear();
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Новый доступ'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: name,
            decoration: const InputDecoration(labelText: 'Название'),
          ),
          TextField(
            controller: hash,
            autocorrect: false,
            enableSuggestions: false,
            autofillHints: const [],
            decoration: const InputDecoration(
              labelText: 'Готовый хэш звонка VK',
            ),
          ),
          TextField(
            controller: days,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Срок, дней (1–365)'),
          ),
          TextField(
            controller: devices,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Устройства (1–32)'),
          ),
          if (error != null) Text(error!),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Отмена'),
      ),
      FilledButton(
        onPressed: () {
          final d = int.tryParse(days.text), n = int.tryParse(devices.text);
          if (hash.text.trim().isEmpty ||
              d == null ||
              d < 1 ||
              d > 365 ||
              n == null ||
              n < 1 ||
              n > 32) {
            setState(() => error = 'Проверьте хэш, срок и число устройств.');
            return;
          }
          Navigator.pop(context, {
            'label': name.text.trim(),
            'vk_hash': hash.text.trim(),
            'days': '$d',
            'max_devices': '$n',
          });
        },
        child: const Text('Создать'),
      ),
    ],
  );
}
