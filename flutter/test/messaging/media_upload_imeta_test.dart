import 'package:flutter_test/flutter_test.dart';
import 'package:nym_bar/features/messages/media_fallbacks.dart';
import 'package:nym_bar/features/media_notes/media_notes.dart' as notes;

void main() {
  test('uploaded extensionless media carries MIME and mirrors in imeta', () {
    final registry = MediaFallbacksRegistry();
    const url = 'https://blossom.example/abc123';
    registry.recordUpload(url, 'image/jpeg');
    registry.recordPredictedMirrors(url, ['https://mirror.example/abc123']);
    expect(registry.imetaTagsForContent('photo $url'), [
      [
        'imeta',
        'url $url',
        'm image/jpeg',
        'fallback https://mirror.example/abc123',
      ],
    ]);
    expect(registry.imetaTagsForContent('${url}extra'), isEmpty);
    expect(registry.imetaTagsForContent('$url#nym:once'), isEmpty);
  });

  test('combining note and uploaded tags does not repeat a URL', () {
    final combined = mergeImetaTags([
      ['imeta', 'url https://example.org/a#nym:voice', 'm audio/ogg'],
      ['imeta', 'url https://example.org/a', 'm audio/ogg'],
    ]);
    expect(combined.length, 1);
    expect(notes.imetaTagsForContent('ordinary text'), isEmpty);
  });

  test('combining tags preserves metadata and deduplicates repeated fields', () {
    final combined = mergeImetaTags([
      ['imeta', 'url https://example.org/a#nym:voice', 'duration 3', 'fallback https://mirror/a'],
      ['imeta', 'url https://example.org/a', 'm audio/ogg', 'fallback https://mirror/a', 'dim 50x50'],
    ]);
    expect(combined, [
      ['imeta', 'url https://example.org/a#nym:voice', 'duration 3', 'fallback https://mirror/a', 'm audio/ogg', 'dim 50x50'],
    ]);
  });
}
