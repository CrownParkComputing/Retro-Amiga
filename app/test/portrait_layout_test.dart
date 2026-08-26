// Portrait layout guard: renders every workbench panel at iPhone portrait
// widths and fails on any layout overflow.
//
// This exists because the app shipped as iPad-only (TARGETED_DEVICE_FAMILY
// "2") and was widened to "1,2". Every panel here had therefore only ever
// been laid out at 834pt or wider, and a phone in portrait gives them barely
// half that.
//
// The failure mode is nasty in release: there is no red error screen, the
// widget simply does not paint, so it reaches a tester as "white screen" or
// "it just shows nothing". The sibling app hit exactly this -- a settings row
// whose action button could not shrink overflowed on EVERY iPhone width.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:uae4arm2026/screens/about_panel.dart';
import 'package:uae4arm2026/screens/av_panel.dart';
import 'package:uae4arm2026/screens/getting_started.dart';
import 'package:uae4arm2026/screens/input_panel.dart';
import 'package:uae4arm2026/screens/library_panel.dart';
import 'package:uae4arm2026/screens/settings_panel.dart';

/// Portrait geometries, smallest first. The rail is not in the picture here:
/// each panel is pumped at the full width, which is the *kindest* case, so an
/// overflow found at this width is one the real layout has too.
const _sizes = <String, Size>{
  'iPhone SE 375x667': Size(375, 667),
  'iPhone 15 Pro 393x852': Size(393, 852),
  'iPhone 17 Pro Max 440x956': Size(440, 956),
};

Widget _named(String name) => switch (name) {
      'Library' => const LibraryPanel(),
      'Settings' => const SettingsPanel(),
      'A/V' => const AvPanel(),
      // The guide is read on a phone more than anywhere else, and its cards
      // carry the longest strings in the app.
      'Help' => GettingStartedGuide(
          steps: <GuideStep>[
            GettingStartedSteps.whatYouNeed(),
            GettingStartedSteps.whereFilesGo(),
            GettingStartedSteps.firstGame(),
          ],
        ),
      'Input' => const InputPanel(),
      'About' => const AboutPanel(),
      _ => throw ArgumentError('no such panel: $name'),
    };

// NOT COVERED HERE, so that a green run is not read as covering them:
//
//  - OnboardingScreen starts a media scan and a WhdloadSupport probe from
//    initState, neither of which completes under the test binding. Pumping it
//    hangs the run rather than reporting anything.
//  - MusicPanel and ResumePanel both return a bare CircularProgressIndicator
//    while _loading, and their loads never finish here either. They render,
//    so a naive check passes -- but it is the spinner being measured, not the
//    panel, which is worse than no check at all.
//
// All three are covered on a real simulator instead.
const _panels = ['Library', 'Settings', 'A/V', 'Input', 'Help', 'About'];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final report = <String>[];

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    // Panels that read the app's directories throw MissingPluginException
    // otherwise, which would end the sweep before the later ones are seen.
    final tmp = Directory.systemTemp.createTempSync('amiga_portrait');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => tmp.path,
    );
  });

  tearDownAll(() {
    stderr.writeln('\n==== AMIGA PORTRAIT REPORT ====');
    stderr.writeln(report.isEmpty ? 'no overflows' : report.join('\n'));
    stderr.writeln('==== END ====\n');
  });

  for (final entry in _sizes.entries) {
    for (final panel in _panels) {
      testWidgets('$panel at ${entry.key}', (tester) async {
        tester.view.physicalSize = entry.value;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        // Collected rather than thrown, so one panel's missing service does
        // not hide the layout of every panel after it.
        final collected = <FlutterErrorDetails>[];
        final previous = FlutterError.onError;
        FlutterError.onError = collected.add;

        await tester.pumpWidget(MaterialApp(
          home: Scaffold(body: _named(panel)),
        ));
        for (var i = 0; i < 4; i++) {
          await tester.pump(const Duration(milliseconds: 32));
        }

        // Restored BEFORE any expect(): the binding asserts if a test calls
        // expect() while FlutterError.onError is still overridden, and that
        // assertion masks whatever the test was actually reporting.
        FlutterError.onError = previous;

        final messages = collected
            .map((d) => d.exception.toString().split('\n').first)
            .toList();
        final overflows =
            messages.where((e) => e.contains('overflowed')).toList();
        final others =
            messages.where((e) => !e.contains('overflowed')).toList();
        for (final o in overflows) {
          report.add('[${entry.key}] $panel\n    $o');
        }

        // A panel that threw before laying out would report no overflow and
        // pass, which is the one result this guard cannot afford to give.
        // Require that it actually drew something first.
        expect(find.byType(Text), findsWidgets,
            reason: '$panel rendered no text at ${entry.key}, so an overflow '
                'check on it proves nothing. Other errors: $others');

        addTearDown(() => tester.pumpWidget(const SizedBox()));
        expect(overflows, isEmpty,
            reason: '$panel overflows at ${entry.key}:\n'
                '${overflows.join("\n")}');
      });
    }
  }
}
