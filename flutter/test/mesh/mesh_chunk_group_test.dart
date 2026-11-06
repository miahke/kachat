import 'package:flutter_test/flutter_test.dart';
import 'package:nym_bar/features/mesh/mesh_outbox.dart';

void main() {
  test('more than 200 fragments survive as one queued message', () {
    final parts = List.generate(
      205,
      (i) => MeshOutboxPart(
        localId: 'local-$i',
        messageId: 'id-$i',
        content: 'chunk-$i',
      ),
    );
    final entry = MeshOutboxEntry(
      kind: MeshOutboxKind.pm,
      target: 'peer',
      content: 'full text',
      createdAtSec: 100,
      localId: 'local-0',
      parts: parts,
    ).ownedBy('owner');
    final queue = MeshOutbox()..add(entry);
    final restored = MeshOutbox()..decode(queue.encode());
    expect(restored.length, 1);
    expect(restored.entries.single.parts!.length, 205);
    expect(restored.entries.single.owner, 'owner');
    expect(
      restored.entries.single.parts!.map((p) => p.messageId),
      parts.map((p) => p.messageId),
    );
  });
  test('dropping a grouped message reports every fragment', () {
    final dropped = <String>[];
    final queue = MeshOutbox(onDropped: dropped.add);
    queue.add(
      MeshOutboxEntry(
        kind: MeshOutboxKind.pm,
        target: 'peer',
        content: 'whole',
        createdAtSec: 1,
        localId: 'a',
        parts: [
          const MeshOutboxPart(localId: 'a', messageId: 'one', content: 'x'),
          const MeshOutboxPart(localId: 'b', messageId: 'two', content: 'y'),
        ],
      ),
    );
    queue.prune(MeshOutbox.ttlMs + 1000);
    expect(dropped, ['a', 'b']);
  });
}
