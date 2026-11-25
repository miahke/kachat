import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nym_bar/features/layout/pointer_input.dart';
import 'package:nym_bar/models/settings.dart';
import 'package:nym_bar/widgets/chat/message_row.dart';

void main() {
  testWidgets('child tap fires immediately on touch release', (tester) async {
    var taps = 0;
    await tester.pumpWidget(MaterialApp(
      home: PointerInputScope(child: Scaffold(body: MessageGestureSurface(
        settings: const Settings(gesturesEnabled: false),
        applies: (_) => true,
        onAction: (_) {},
        onDoubleClick: (_) {},
        onDoubleTap: (_) {},
        onLongPressStart: (_) {},
        onSecondaryTap: () {},
        onSecondaryClick: (_) {},
        child: GestureDetector(
          onTap: () => taps++,
          child: const SizedBox(width: 200, height: 100, child: Text('tap child')),
        ),
      ))),
    ));
    await tester.tap(find.text('tap child'));
    await tester.pump();
    expect(taps, 1);
  });

  testWidgets('two touch taps reach quick reaction even with swipes disabled', (tester) async {
    var reactions = 0;
    PointerInput.instance.resetForTest(mouse: true);
    await tester.pumpWidget(MaterialApp(
      home: PointerInputScope(child: Scaffold(body: MessageGestureSurface(
        settings: const Settings(gesturesEnabled: false),
        applies: (_) => true,
        onAction: (_) {},
        onDoubleClick: (_) {},
        onDoubleTap: (_) => reactions++,
        onLongPressStart: (_) {},
        onSecondaryTap: () {},
        onSecondaryClick: (_) {},
        child: const SizedBox(width: 200, height: 100, child: Text('message')),
      ))),
    ));
    await tester.tap(find.text('message'));
    await tester.pump(const Duration(milliseconds: 40));
    await tester.tap(find.text('message'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(reactions, 1);
  });

  testWidgets('interactive child keeps its own double-tap action', (tester) async {
    var reactions = 0;
    var childActions = 0;
    await tester.pumpWidget(MaterialApp(
      home: PointerInputScope(child: Scaffold(body: MessageGestureSurface(
        settings: const Settings(gesturesEnabled: false),
        applies: (_) => true,
        onAction: (_) {},
        onDoubleClick: (_) {},
        onDoubleTap: (_) => reactions++,
        onLongPressStart: (_) {},
        onSecondaryTap: () {},
        onSecondaryClick: (_) {},
        child: GestureDetector(
          onDoubleTap: () => childActions++,
          child: const SizedBox(width: 200, height: 100, child: Text('interactive')),
        ),
      ))),
    ));
    await tester.tap(find.text('interactive'));
    await tester.pump(const Duration(milliseconds: 40));
    await tester.tap(find.text('interactive'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(childActions, 1);
    expect(reactions, 0);
  });
  testWidgets('scrolling does not trigger a reaction', (tester) async {
    var reactions = 0;
    final controller = ScrollController();
    await tester.pumpWidget(MaterialApp(
      home: PointerInputScope(child: Scaffold(body: ListView(
        controller: controller,
        children: [MessageGestureSurface(
          settings: const Settings(gesturesEnabled: true),
          applies: (_) => true,
          onAction: (_) {}, onDoubleClick: (_) {},
          onDoubleTap: (_) => reactions++, onLongPressStart: (_) {},
          onSecondaryTap: () {}, onSecondaryClick: (_) {},
          child: const SizedBox(height: 1200, child: Text('scroll me')),
        )],
      ))),
    ));
    await tester.dragFrom(const Offset(400, 400), const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(controller.offset, greaterThan(0));
    expect(reactions, 0);
    controller.dispose();
  });

  testWidgets('mouse double click does not trigger touch reaction', (tester) async {
    var reactions = 0;
    var clicks = 0;
    PointerInput.instance.resetForTest(mouse: true);
    await tester.pumpWidget(MaterialApp(
      home: PointerInputScope(child: Scaffold(body: MessageGestureSurface(
        settings: const Settings(gesturesEnabled: false),
        applies: (_) => true, onAction: (_) {},
        onDoubleClick: (_) => clicks++, onDoubleTap: (_) => reactions++,
        onLongPressStart: (_) {}, onSecondaryTap: () {},
        onSecondaryClick: (_) {},
        child: const SizedBox(width: 200, height: 100, child: Text('mouse')),
      ))),
    ));
    await tester.tap(find.text('mouse'), kind: PointerDeviceKind.mouse);
    await tester.pump(const Duration(milliseconds: 40));
    await tester.tap(find.text('mouse'), kind: PointerDeviceKind.mouse);
    await tester.pump();
    expect(clicks, 1);
    expect(reactions, 0);
  });

}
