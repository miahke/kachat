import 'dart:async';
import 'dart:collection';
// SPDX-License-Identifier: AGPL-3.0-only
import 'dart:io';
import 'dart:math';

import 'package:path_provider/path_provider.dart';

/// Native audio/video plugins receive files, never remote URLs that bypass Dart routing.
class RoutedMedia {
  static const maximumBytes = 100 * 1024 * 1024;
  static final _pending = <String, Future<File>>{};
  static final _completed = <String, File>{};
  static final _waiters = Queue<Completer<void>>();
  static final _writing = <String>{};
  static int _active = 0;
  static DateTime? _lastMaintenance;
  static Future<void> _maintenance = Future.value();

  static Future<File> file(String url) async {
    final uri = Uri.parse(url);
    if (uri.scheme != 'https' || uri.host.isEmpty || uri.userInfo.isNotEmpty) {
      throw const FormatException('HTTPS media required');
    }
    final cached = _completed[url];
    if (cached != null && await cached.exists()) {
      _completed.remove(url);
      _completed[url] = cached;
      return cached;
    }
    final existing = _pending[url];
    if (existing != null) return existing;
    final task = _limitedFetch(url);
    _pending[url] = task;
    try {
      final file = await task;
      _completed[url] = file;
      while (_completed.length > 16) {
        _completed.remove(_completed.keys.first);
      }
      return file;
    } finally {
      if (identical(_pending[url], task)) _pending.remove(url);
    }
  }

  static Future<File> _limitedFetch(String url) async {
    if (_active >= 2) {
      final waiter = Completer<void>();
      _waiters.add(waiter);
      await waiter.future;
    } else {
      _active++;
    }
    try {
      return await _fetch(url);
    } finally {
      if (_waiters.isNotEmpty) {
        _waiters.removeFirst().complete();
      } else {
        _active--;
      }
    }
  }

  static Future<void> _clean(Directory directory) async {
    if (_lastMaintenance != null &&
        DateTime.now().difference(_lastMaintenance!) <
            const Duration(seconds: 30)) {
      return;
    }
    _lastMaintenance = DateTime.now();
    final files = await directory
        .list()
        .where((f) => f is File && !_writing.contains(f.path))
        .cast<File>()
        .toList();
    final metadata = <File, FileStat>{};
    for (final f in files) {
      metadata[f] = await f.stat();
    }
    files.sort(
      (a, b) => metadata[a]!.modified.compareTo(metadata[b]!.modified),
    );
    var total = metadata.values.fold<int>(0, (a, b) => a + b.size);
    for (final f in files) {
      if (total < 128 * 1024 * 1024 &&
          DateTime.now().difference(metadata[f]!.modified) <
              const Duration(days: 1)) {
        break;
      }
      try {
        await f.delete();
        total -= metadata[f]!.size;
      } catch (_) {}
    }
  }

  static Future<File> _fetch(String source) async {
    final uri = Uri.parse(source);
    if (uri.scheme != 'https' || uri.host.isEmpty || uri.userInfo.isNotEmpty) {
      throw const FormatException('HTTPS media required');
    }
    final directory = Directory(
      '${(await getTemporaryDirectory()).path}/panchat-routed-media',
    );
    await directory.create(recursive: true);
    _maintenance = _maintenance
        .catchError((Object _) {})
        .then((_) => _clean(directory));
    await _maintenance;
    final random = Random.secure();
    final token = List.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    final file = File('${directory.path}/$token.media');
    _writing.add(file.path);
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    IOSink? output;
    try {
      final request = await client
          .getUrl(uri)
          .timeout(const Duration(seconds: 20));
      final response = await request.close().timeout(
        const Duration(seconds: 30),
      );
      if (response.statusCode != 200 || response.contentLength > maximumBytes) {
        throw const HttpException('Media unavailable or too large');
      }
      output = file.openWrite();
      var count = 0;
      await output.addStream(
        response.timeout(const Duration(seconds: 30)).map((bytes) {
          count += bytes.length;
          if (count > maximumBytes) {
            throw const HttpException('Media too large');
          }
          return bytes;
        }),
      );
      await output.close();
      output = null;
      return file;
    } catch (_) {
      await output?.close();
      if (await file.exists()) await file.delete();
      rethrow;
    } finally {
      _writing.remove(file.path);
      client.close(force: true);
    }
  }
}
