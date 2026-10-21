import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uae4arm2026/data/amiga_model.dart';
import 'package:uae4arm2026/data/emulator_settings.dart';
import 'package:uae4arm2026/screens/guided_config_screen.dart';

void main() {
  test('the WHDLoad preset is the A1200 profile for every archive', () {
    // No filename sniffing: every WHDLoad setup wants the A1200 profile -
    // AGA, 68020, 2M chip + 8M fast - whatever the package is called.
    final EmulatorSettings s =
        WizardMode.whdload.settingsFor(AmigaModel.a1200);
    expect(s.chipset, 'aga');
    expect(s.cpuModel, 68020);
    expect(s.chipRam, 4); // half-megabytes: 4 = 2MB
    expect(s.fastRam, 8); // megabytes
  });

  testWidgets(
    'a mounted WHDLoad archive with machine and ROM decided lands on tailor',
    (WidgetTester tester) async {
      final EmulatorSettings decided = WizardMode.whdload
          .settingsFor(AmigaModel.a1200)
          .copyWith(
            whdloadFilename: '/games/DK_AGA.lha',
            romFile: '/roms/kick31-a1200.rom',
          );
      await tester.pumpWidget(
        MaterialApp(
          home: GuidedConfigScreen(
            mode: WizardMode.whdload,
            initialSettings: decided,
            initialName: 'DK',
          ),
        ),
      );
      await tester.pump();
      // The tailor step leads with the machine fact line, not the model
      // picker the machine step would show.
      expect(find.text('Amiga 1200 · AGA, 68020, 2MB Chip'), findsOneWidget);
      expect(find.text('Amiga 600'), findsNothing);
    },
  );

  testWidgets('a WHDLoad wizard without a ROM stays on the machine step', (
    WidgetTester tester,
  ) async {
    final EmulatorSettings undecided = WizardMode.whdload
        .settingsFor(AmigaModel.a500)
        .copyWith(whdloadFilename: '/games/DigDug.lha');
    await tester.pumpWidget(
      MaterialApp(
        home: GuidedConfigScreen(
          mode: WizardMode.whdload,
          initialSettings: undecided,
          initialName: 'DigDug',
        ),
      ),
    );
    await tester.pump();
    // No ROM could be decided (the index is empty in tests), so the wizard
    // still walks every step: the model cards of the machine step show.
    expect(find.text('Amiga 600'), findsOneWidget);
    expect(find.text('Amiga 1200 · AGA, 68020, 2MB Chip'), findsNothing);
  });
}
