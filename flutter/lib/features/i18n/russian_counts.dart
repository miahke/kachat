/// Numeric UI labels; values are substituted afterwards, preserving user names.
String? russianCountTemplate(String source, Map<String, Object?>? args) {
  final match = _counter.firstMatch(source);
  if (match == null) return null;
  final key = match.group(1)!;
  final value = args?[key];
  final int? count;
  if (value is int) {
    count = value;
  } else if (value is num &&
      value.isFinite &&
      value == value.truncateToDouble()) {
    count = value.toInt();
  } else {
    count = value is String ? int.tryParse(value) : null;
  }
  // Abbreviations such as 2K retain the dictionary's plural label.
  if (count == null) return null;
  final hundred = count.abs() % 100;
  final last = hundred % 10;
  final form = hundred >= 11 && hundred <= 14
      ? 2
      : last == 1
      ? 0
      : last >= 2 && last <= 4
      ? 1
      : 2;
  String choose((String, String, String) words) => switch (form) {
    0 => words.$1,
    1 => words.$2,
    _ => words.$3,
  };
  final noun = match.group(2)!;
  final words = _nouns[noun];
  if (words != null) {
    final suffix = switch (match.group(3)) {
      ' from {name}' => ' от {name}',
      ' in {chat}' => ' в {chat}',
      _ => '',
    };
    return '{$key} ${choose(words)}$suffix';
  }
  if (noun.endsWith(' ago')) {
    final unit = _timeUnits[noun.substring(0, noun.length - 4)];
    if (unit != null) return '{$key} ${choose(unit)} назад';
  }
  if (noun.startsWith('people are ')) {
    final activity = _activities[noun.substring('people are '.length)];
    if (activity != null) {
      return '{$key} ${choose(('участник', 'участника', 'участников'))} ${form == 0 ? activity.$1 : activity.$2}';
    }
  }
  return null;
}

final _counter = RegExp(r'^\{(n|count)\} (.+?)( from \{name\}| in \{chat\})?$');
const _nouns = <String, (String, String, String)>{
  'messages': ('сообщение', 'сообщения', 'сообщений'),
  'msg': ('сообщение', 'сообщения', 'сообщений'),
  'msgs': ('сообщение', 'сообщения', 'сообщений'),
  'new messages': ('новое сообщение', 'новых сообщения', 'новых сообщений'),
  'new notifications': (
    'новое уведомление',
    'новых уведомления',
    'новых уведомлений',
  ),
  'scheduled messages': (
    'запланированное сообщение',
    'запланированных сообщения',
    'запланированных сообщений',
  ),
  'member': ('участник', 'участника', 'участников'),
  'members': ('участник', 'участника', 'участников'),
  'peers': ('узел', 'узла', 'узлов'),
  'links': ('ссылка', 'ссылки', 'ссылок'),
  'replies': ('ответ', 'ответа', 'ответов'),
  'votes': ('голос', 'голоса', 'голосов'),
  'results': ('результат', 'результата', 'результатов'),
  'file(s)': ('файл', 'файла', 'файлов'),
  'nyms online': (
    'пользователь в сети',
    'пользователя в сети',
    'пользователей в сети',
  ),
  'online nyms': (
    'пользователь в сети',
    'пользователя в сети',
    'пользователей в сети',
  ),
  'credit': ('кредит', 'кредита', 'кредитов'),
  'credits': ('кредит', 'кредита', 'кредитов'),
};
const _timeUnits = <String, (String, String, String)>{
  'second': ('секунду', 'секунды', 'секунд'),
  'seconds': ('секунду', 'секунды', 'секунд'),
  'minute': ('минуту', 'минуты', 'минут'),
  'minutes': ('минуту', 'минуты', 'минут'),
  'hour': ('час', 'часа', 'часов'),
  'hours': ('час', 'часа', 'часов'),
  'day': ('день', 'дня', 'дней'),
  'days': ('день', 'дня', 'дней'),
  'month': ('месяц', 'месяца', 'месяцев'),
  'months': ('месяц', 'месяца', 'месяцев'),
  'year': ('год', 'года', 'лет'),
  'years': ('год', 'года', 'лет'),
};
const _activities = <String, (String, String)>{
  'typing': ('печатает', 'печатают'),
  'recording video messages': (
    'записывает видеосообщение',
    'записывают видеосообщения',
  ),
  'recording voice messages': (
    'записывает голосовое сообщение',
    'записывают голосовые сообщения',
  ),
  'sending files': ('отправляет файл', 'отправляют файлы'),
  'sending photos': ('отправляет фото', 'отправляют фото'),
  'sending videos': ('отправляет видео', 'отправляют видео'),
  'sending voice messages': (
    'отправляет голосовое сообщение',
    'отправляют голосовые сообщения',
  ),
};
