import 'package:billiard_poker/core/duel_ui.dart';
import 'package:billiard_poker/features/duel/home_portrait_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('PortraitCanvas columnWidthFor: phone uses full width', () {
    expect(PortraitCanvas.columnWidthFor(390), 390);
    expect(PortraitCanvas.columnWidthFor(430), 430);
    expect(PortraitCanvas.columnWidthFor(699), 699);
  });

  test('PortraitCanvas columnWidthFor: desktop caps phone column', () {
    expect(
      PortraitCanvas.columnWidthFor(700),
      PortraitCanvas.phoneColumnMaxWidth,
    );
    expect(
      PortraitCanvas.columnWidthFor(1280),
      PortraitCanvas.phoneColumnMaxWidth,
    );
    expect(
      PortraitCanvas.columnWidthFor(1920),
      PortraitCanvas.phoneColumnMaxWidth,
    );
  });

  testWidgets('PortraitCanvas centers column on 1280x800 desktop', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: PortraitCanvas(
          minHeight: 1800,
          builder: (_, height) => ColoredBox(
            color: Colors.red,
            child: Center(child: Text('h=${height.round()}')),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.textContaining('h='), findsOneWidget);

    final box = tester.renderObject<RenderBox>(find.byType(PortraitCanvas));
    expect(box.size.width, 1280);
    expect(box.size.height, greaterThan(0));
  });

  testWidgets('DuelDialogFrame stays phone-column on 1280 desktop', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DuelDialogFrame(
            child: Container(
              width: 990,
              height: 400,
              color: Colors.orange,
              alignment: Alignment.center,
              child: const Text('dlg'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('dlg'), findsOneWidget);

    // Constraining phone column must exist on wide desktop.
    final column = tester
        .widgetList<SizedBox>(find.byType(SizedBox))
        .where((s) => s.width == PortraitCanvas.phoneColumnMaxWidth)
        .toList();
    expect(column, isNotEmpty);
  });

  testWidgets('PortraitCanvas fills 390x844 phone', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: PortraitCanvas(
          minHeight: 1800,
          builder: (_, _) => const ColoredBox(color: Colors.blue),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
