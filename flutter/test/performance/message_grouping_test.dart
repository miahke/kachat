import 'package:flutter_test/flutter_test.dart';
import 'package:nym_bar/models/message.dart';
import 'package:nym_bar/widgets/chat/message_row.dart';

void main() {
  test('long single-author runs remain bounded without dropping or reordering messages', () {
    final messages = List.generate(
      1000,
      (i) => Message(
        id: 'synthetic-$i',
        author: 'Synthetic',
        pubkey: 'synthetic',
        content: 'Message $i',
        createdAt: 1700000000 + i,
      ),
    );
    final groups = buildMessageGroups(
      messages,
      reactions: {},
      useBubbles: true,
    );
    expect(groups.every((g) => g.length <= 24), true);
    expect(groups.length, 42);
    expect(
      groups.expand((g) => g).map((e) => e.message.id),
      messages.map((m) => m.id),
    );
    final withBreak = buildMessageGroups(
      messages,
      reactions: {},
      useBubbles: true,
      breakBefore: 'synthetic-10',
    );
    expect(withBreak.any((g) => g.first.message.id == 'synthetic-10'), true);
    expect(
      buildMessageGroups(messages, reactions: {}, useBubbles: false).length,
      1000,
    );
  });
}
