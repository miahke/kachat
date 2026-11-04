import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nym_bar/core/theme/nym_theme.dart';
import 'package:nym_bar/core/theme/nym_colors.dart';
import 'package:nym_bar/features/qwdtt/qwdtt_page.dart';

import 'qwdtt_page_test.dart' show FakeQwdtt;

void main() {
  const target = String.fromEnvironment('PANCHAT_PREVIEW');
  testWidgets('render synthetic qWDTT page in NYM theme', (tester) async {
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    await (FontLoader(
      'Roboto',
    )..addFont(rootBundle.load('assets/fonts/Roboto-Regular.ttf'))).load();
    await tester.binding.setSurfaceSize(const Size(420, 920));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final boundary = GlobalKey();
    final theme = buildNymThemeData(
      resolveNymColors(
        theme: NymThemeKey.hacker,
        brightness: Brightness.dark,
        solidUi: true,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: RepaintBoundary(
          key: boundary,
          child: QwdttPage(controller: FakeQwdtt()..ready = true),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      final image =
          await (boundary.currentContext!.findRenderObject()
                  as RenderRepaintBoundary)
              .toImage(pixelRatio: 2);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await File(target).writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
  }, skip: target.isEmpty);
}
