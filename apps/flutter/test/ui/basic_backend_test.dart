import 'package:c001apk_flutter/components/basic_glass.dart';
import 'package:c001apk_flutter/constants/liquid_glass_level.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('basic navigation supports taps and ordinary drag selection',
      (tester) async {
    var selected = 0;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Center(
      child: SizedBox(
          width: 400,
          child: LiquidNavigationBar(
              selectedIndex: selected,
              onDestinationSelected: (value) => selected = value)),
    ))));
    await tester.tap(find.text('关注'));
    await tester.pumpAndSettle();
    expect(selected, 1);
    final surface = find.byKey(const ValueKey('liquid-drag-surface'));
    await tester.drag(surface, const Offset(120, 0));
    await tester.pumpAndSettle();
    expect(selected, 2);
  });

  testWidgets('basic lightweight panels keep content and do not blur',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
            body: LiquidGlassPanel(
      enabled: true,
      level: LiquidGlassLevel.low,
      child: Text('个人资料'),
    ))));
    expect(find.text('个人资料'), findsOneWidget);
    expect(find.byType(BackdropFilter), findsNothing);
  });
}
