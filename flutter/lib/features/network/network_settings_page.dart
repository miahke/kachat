import 'package:flutter/material.dart';

import '../qwdtt/qwdtt_controller.dart';
import '../qwdtt/qwdtt_page.dart';
import 'tor_page.dart';
import 'proxy_page.dart';

class NetworkSettingsPage extends StatefulWidget {
  const NetworkSettingsPage({super.key, this.controller});
  final QwdttController? controller;
  @override
  State<NetworkSettingsPage> createState() => _NetworkSettingsPageState();
}

class _NetworkSettingsPageState extends State<NetworkSettingsPage> {
  QwdttController get c => widget.controller ?? QwdttController.instance;
  @override
  void initState() {
    super.initState();
    c.refresh();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Сетевые подключения')),
    body: ListenableBuilder(
      listenable: c,
      builder: (context, _) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Способ подключения: ${switch (c.route) {
                      'TOR' => 'Tor',
                      'VK' => 'qWDTT',
                      'PROXY' => 'HTTP / SOCKS5',
                      'DIRECT' => 'Прямое подключение',
                      _ => 'Заблокирован',
                    }}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    c.selected
                        ? switch (c.state) {
                            'READY' =>
                              c.route == 'PROXY'
                                  ? 'Прокси выбран'
                                  : 'Локальный прокси готов',
                            'STARTING' => 'Устанавливаем соединение…',
                            'RECONNECTING' => 'Восстанавливаем соединение…',
                            'ERROR' => 'Не удалось подключиться',
                            _ => 'Выбранный маршрут остановлен',
                          }
                        : 'Приложение подключается к серверам напрямую.',
                  ),
                  if (c.route == 'TOR' && c.state == 'STARTING')
                    Text('Загрузка сети Tor: ${c.tor['percent'] ?? 0} %'),
                  if (c.statusError != null)
                    Text(
                      c.statusError!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  if (c.selected)
                    const Text(
                      'При сбое выбранного маршрута прямое подключение не включается. При его отключении вручную приложение переключится на прямое подключение.',
                    ),
                  if (c.selected && c.state == 'READY')
                    TextButton.icon(
                      onPressed: c.probeState == 'checking'
                          ? null
                          : c.checkConnection,
                      icon: const Icon(Icons.network_check),
                      label: const Text('Проверить HTTPS-соединение'),
                    ),
                  if (c.probeMessage != null) Text(c.probeMessage!),
                ],
              ),
            ),
          ),
          Card(
            child: ListTile(
              key: const Key('network-tor'),
              leading: const Icon(Icons.shield_outlined),
              title: const Text('Tor'),
              subtitle: const Text(
                'Обход блокировок без аккаунта. Внутри можно выбрать мосты и посмотреть ход подключения.',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute<void>(builder: (_) => TorPage(controller: c)),
              ),
            ),
          ),
          Card(
            child: ListTile(
              key: const Key('network-qwdtt'),
              leading: const Icon(Icons.router_outlined),
              title: const Text('qWDTT · VK TURN'),
              subtitle: const Text(
                'Подключение через свой сервер. Настройки ключа, VK TURN и сервера внутри.',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => QwdttPage(controller: c),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: ListTile(
              key: const Key('network-proxy'),
              leading: const Icon(Icons.vpn_key_outlined),
              title: const Text('Прокси'),
              subtitle: const Text(
                'Подключение через свой HTTP, HTTPS или SOCKS5-прокси. Можно вставить ссылку.',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => ProxyPage(controller: c),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (c.selected) ...[
            OutlinedButton.icon(
              key: const Key('network-direct'),
              onPressed: c.busy ? null : () => c.command('direct'),
              icon: const Icon(Icons.public),
              label: const Text('Включить прямое подключение'),
            ),
            const Text(
              'Этот вариант отключает Tor, qWDTT и внешний прокси. Соединения устанавливаются непосредственно с серверами приложения.',
            ),
          ],
          if (c.error != null)
            Text(
              c.error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
        ],
      ),
    ),
  );
}
