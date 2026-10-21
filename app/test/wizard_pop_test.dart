import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // The wizard saves, launches, then closes itself. launch() flips
  // Emulator.playing and the workbench pushes the session screen over the
  // wizard's route, so by the time the wizard's close runs a plain
  // Navigator.pop removes the session route -- and completes it with a bool
  // the EmulatorExit route cannot take. The route ends up half-removed and
  // every later pop on the stack throws, which left a running session with
  // no working exit. The fix is to remove the covered route by name.
  testWidgets('a covered route removes itself without touching the top route',
      (WidgetTester tester) async {
    bool? wizardResult;
    Object? topResult;
    BuildContext? wizardContext;
    final GlobalKey<NavigatorState> nav = GlobalKey<NavigatorState>();

    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: nav,
        home: const Scaffold(body: Text('shelf')),
      ),
    );

    // Pushed like the configurations screen pushes the wizard.
    unawaited(
      nav.currentState!
          .push<bool>(
            MaterialPageRoute<bool>(
              builder: (BuildContext context) {
                wizardContext = context;
                return const Scaffold(body: Text('wizard'));
              },
            ),
          )
          .then((bool? value) => wizardResult = value),
    );
    await tester.pumpAndSettle();

    // Then the session screen lands on top, like _openEmulator does when
    // Emulator.playing flips.
    unawaited(
      nav.currentState!
          .push<Object?>(
            MaterialPageRoute<Object?>(
              builder: (BuildContext context) =>
                  const Scaffold(body: Text('session')),
            ),
          )
          .then((Object? value) => topResult = value),
    );
    await tester.pumpAndSettle();
    expect(find.text('session'), findsOneWidget);

    final ModalRoute<dynamic>? route = ModalRoute.of(wizardContext!);
    expect(route!.isCurrent, isFalse);
    nav.currentState!.removeRoute(route, true);
    await tester.pumpAndSettle();

    // The wizard's caller still gets its saved flag, and the session stays.
    expect(wizardResult, true);
    expect(find.text('session'), findsOneWidget);
    expect(find.text('wizard'), findsNothing);

    // And the session route still completes with its own result type.
    nav.currentState!.pop('closed');
    await tester.pumpAndSettle();
    expect(topResult, 'closed');
  });
}
