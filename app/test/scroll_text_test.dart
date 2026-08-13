import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uae4arm2026/screens/workbench_screen.dart';

void main() {
  testWidgets('the scroller reports what is on the device', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: WorkbenchScreen()));
    await tester.pump();

    final _ScrollProbe probe = _ScrollProbe(tester);
    // Nothing scanned yet: the scroller still says something rather than
    // sitting there empty, and it does not claim counts it does not have.
    expect(probe.text, contains('AMIGA-RETRO'));
    expect(probe.text, isNot(contains('0 FLOPPY')));
  });
}

/// Reaches the private state's scroller text through the element tree, so the
/// string can be checked without exporting it.
class _ScrollProbe {
  _ScrollProbe(this.tester);

  final WidgetTester tester;

  String get text {
    final dynamic state = tester.state(find.byType(WorkbenchScreen));
    // ignore: avoid_dynamic_calls
    return state.scrollTextForTest as String;
  }
}
