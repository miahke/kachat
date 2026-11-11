import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nym_bar/widgets/chat/message_row.dart';

void main() {
  testWidgets('message entrance approaches its final position without reversal', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: MessageBubbleEntrance(self: true, child: Text('message')),
    ));
    double? previousY;
    double? previousScale;
    for (var i = 0; i < 13; i++) {
      await tester.pump(const Duration(milliseconds: 20));
      final transforms = tester.widgetList<Transform>(find.byType(Transform)).toList();
      final translate = transforms.first.transform;
      final scale = transforms.last.transform;
      final y = translate.storage[13];
      final xScale = scale.storage[0];
      if (previousY != null) expect(y, greaterThanOrEqualTo(previousY - 0.00001));
      if (previousScale != null) expect(xScale, greaterThanOrEqualTo(previousScale - 0.00001));
      expect(xScale, lessThanOrEqualTo(1.0));
      previousY = y;
      previousScale = xScale;
    }
  });
}
