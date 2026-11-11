import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:nym_bar/features/messages/media_fallbacks.dart';

void main() {
  test('timeout cancels the attempt before retry', () async {
    final uploader = BlossomUploader(hostTimeout: const Duration(milliseconds: 10));
    var cancelled = false, attempts = 0;
    final result = await uploader.upload(['a', 'b'], 'image/png', (server, type) {
      attempts++;
      if (attempts == 1) return Completer<String?>().future;
      expect(cancelled, isTrue);
      return Future.value('https://example.org/file');
    }, onTimeout: () { cancelled = true; });
    expect(result?.server, 'b');
  });
  test('route invalidation stops all later retries', () async {
    final uploader = BlossomUploader();
    var active = true, attempts = 0;
    final result = await uploader.upload(['a', 'b'], 'image/png', (server, type) async {
      attempts++; active = false; throw StateError('route changed');
    }, canContinue: () => active);
    expect(result, isNull); expect(attempts, 1);
    expect(uploader.lastFailure, 'Network route changed');
  });
  test('invalid route before first attempt reports route change', () async {
    final uploader = BlossomUploader();
    final result = await uploader.upload(['a'], 'image/png', (server, type) async {
      fail('attempt must not start');
    }, canContinue: () => false);
    expect(result, isNull);
    expect(uploader.lastFailure, 'Network route changed');
  });
}
