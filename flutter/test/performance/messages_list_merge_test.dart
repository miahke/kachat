import 'package:flutter_test/flutter_test.dart';
import 'package:nym_bar/widgets/chat/messages_list.dart';

void main() {
  test('merges chronological entries stably with linear comparisons', () {
    final messages = List.generate(
      1000,
      (i) => (time: i ~/ 2, kind: 'm', id: i),
    );
    final polls = List.generate(1000, (i) => (time: i ~/ 2, kind: 'p', id: i));
    var comparisons = 0;
    final merged = mergeOrderedEntries(messages, polls, (a, b) {
      comparisons++;
      return a.time.compareTo(b.time);
    });
    expect(merged.length, 2000);
    for (var i = 1; i < merged.length; i++) {
      expect(merged[i - 1].time <= merged[i].time, isTrue);
      if (merged[i - 1].time == merged[i].time) {
        expect(merged[i - 1].kind == 'p' && merged[i].kind == 'm', isFalse);
      }
    }
    expect(
      merged.where((e) => e.kind == 'm').map((e) => e.id),
      messages.map((e) => e.id),
    );
    expect(
      merged.where((e) => e.kind == 'p').map((e) => e.id),
      polls.map((e) => e.id),
    );
    expect(comparisons, lessThan(4000));
  });
  test('falls back to stable sorting for non-chronological inputs', () {
    final first = [(time: 2, id: 'a'), (time: 1, id: 'b'), (time: 2, id: 'c')];
    final second = [(time: 2, id: 'd'), (time: 0, id: 'e')];
    final result = mergeOrderedEntries(
      first,
      second,
      (a, b) => a.time.compareTo(b.time),
    );
    expect(result.map((e) => e.id), ['e', 'b', 'a', 'c', 'd']);
  });
  test('matches the previous comparator for reordered and tied entries', () {
    for (var seed = 0; seed < 100; seed++) {
      final first = List.generate(30, (i) => (time: (i * 7 + seed) % 9, id: i));
      final second = List.generate(20, (i) => (time: (i * 5 + seed) % 9, id: i + 30));
      if (seed.isEven) {
        first.sort((a, b) => a.time.compareTo(b.time));
        second.sort((a, b) => a.time.compareTo(b.time));
      }
      final raw = [...first, ...second];
      final indices = List.generate(raw.length, (i) => i)
        ..sort((a, b) {
          final difference = raw[a].time.compareTo(raw[b].time);
          return difference != 0 ? difference : a - b;
        });
      expect(mergeOrderedEntries(first, second, (a, b) => a.time.compareTo(b.time)),
          [for (final i in indices) raw[i]]);
    }
  });

}
