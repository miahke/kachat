// SPDX-License-Identifier: AGPL-3.0-only
import 'package:flutter/material.dart';

import '../qwdtt/qwdtt_controller.dart';
import 'proxy_profile.dart';

class ProxyPage extends StatefulWidget {
  const ProxyPage({super.key, this.controller});
  final QwdttController? controller;
  @override
  State<ProxyPage> createState() => _ProxyPageState();
}

class _ProxyPageState extends State<ProxyPage> {
  QwdttController get c => widget.controller ?? QwdttController.instance;
  final link = TextEditingController(),
      host = TextEditingController(),
      port = TextEditingController(text: '1080'),
      user = TextEditingController(),
      password = TextEditingController();
  String type = 'SOCKS5';
  String? error;
  bool _edited = false;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final saved = await c.proxySettings();
      if (!mounted || _edited || saved.isEmpty) return;
      setState(() {
        type = saved['type'] as String;
        host.text = saved['host'] as String;
        port.text = '${saved['port']}';
        user.text = saved['username'] as String;
        password.text = saved['password'] as String;
      });
    } catch (_) {
      if (mounted) {
        setState(() => error = 'Не удалось прочитать настройки прокси.');
      }
    }
  }

  void _import() {
    _edited = true;
    try {
      final profile = ProxyProfile.parse(link.text);
      setState(() {
        type = profile.type;
        host.text = profile.host;
        port.text = '${profile.port}';
        user.text = profile.username;
        password.text = profile.password;
        link.clear();
        error = null;
      });
    } on FormatException catch (e) {
      setState(() => error = e.message);
    } catch (_) {
      setState(() => error = 'Проверьте формат ссылки прокси.');
    }
  }

  Future<void> _connect() async {
    try {
      final address = host.text.trim();
      final authority = address.contains(':') && !address.startsWith('[')
          ? '[$address]'
          : address;
      final auth = user.text.isEmpty
          ? ''
          : '${Uri.encodeComponent(user.text)}:${Uri.encodeComponent(password.text)}@';
      final profile = ProxyProfile.parse(
        '${type.toLowerCase()}://$auth$authority:${port.text.trim()}',
      );
      setState(() => error = null);
      await c.command('connectProxy', profile.toMap());
      if (c.error == null) await c.checkConnection();
    } on FormatException catch (e) {
      if (mounted) setState(() => error = e.message);
    } catch (_) {
      if (mounted) setState(() => error = 'Проверьте настройки прокси.');
    }
  }

  @override
  void dispose() {
    for (final f in [link, host, port, user, password]) {
      f.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('HTTP и SOCKS5 прокси')),
    body: ListenableBuilder(
      listenable: c,
      builder: (context, _) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Вставьте ссылку SOCKS5, HTTP/HTTPS или Telegram SOCKS. Импорт заполняет поля и не включает прокси без нажатия «Подключить».',
          ),
          TextField(
            controller: link,
            obscureText: true,
            enableSuggestions: false,
            autocorrect: false,
            decoration: const InputDecoration(
              labelText: 'Ссылка прокси',
              hintText: 'socks5://… или https://t.me/socks?…',
            ),
            onChanged: (_) => _edited = true,
          ),
          OutlinedButton.icon(
            onPressed: c.busy ? null : _import,
            icon: const Icon(Icons.download),
            label: const Text('Импортировать ссылку'),
          ),
          DropdownButtonFormField<String>(
            initialValue: type,
            key: ValueKey(type),
            decoration: const InputDecoration(labelText: 'Тип прокси'),
            items: [
              'SOCKS5',
              'HTTP',
              'HTTPS',
            ].map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
            onChanged: c.busy
                ? null
                : (v) {
                    _edited = true;
                    setState(() => type = v!);
                  },
          ),
          for (final entry in [
            (host, 'Адрес сервера'),
            (port, 'Порт'),
            (user, 'Логин (необязательно)'),
            (password, 'Пароль'),
          ])
            TextField(
              controller: entry.$1,
              obscureText: identical(entry.$1, password),
              autocorrect: false,
              enableSuggestions: false,
              keyboardType: identical(entry.$1, port)
                  ? TextInputType.number
                  : TextInputType.text,
              decoration: InputDecoration(labelText: entry.$2),
              onChanged: (_) => _edited = true,
            ),
          const SizedBox(height: 16),
          const Text(
            'Обычный HTTP-прокси передаёт свои реквизиты без шифрования до прокси. HTTPS защищает этот участок TLS. Шифрование HTTPS-соединений приложения сохраняется в обоих случаях. MTProto Telegram и Shadowsocks требуют других ядер и не являются SOCKS5.',
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: c.busy ? null : _connect,
            icon: const Icon(Icons.link),
            label: const Text('Подключить и проверить HTTPS'),
          ),
          if (c.route == 'PROXY') ...[
            Text(
              c.state == 'READY'
                  ? 'Прокси выбран. Доступность проверяется HTTPS-запросом.'
                  : 'Выбранный прокси остановлен. Прямого обхода нет.',
            ),
            if (c.probeMessage != null) Text(c.probeMessage!),
            OutlinedButton(
              onPressed: c.busy ? null : () => c.command('disconnect'),
              child: const Text('Остановить'),
            ),
          ],
          if (error != null || c.error != null)
            Text(
              error ?? c.error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
        ],
      ),
    ),
  );
}
