import 'package:flutter_test/flutter_test.dart';
import 'package:uae4arm2026/data/amiga_model.dart';
import 'package:uae4arm2026/data/config_generator.dart';
import 'package:uae4arm2026/data/emulator_settings.dart';
import 'package:uae4arm2026/screens/guided_config_screen.dart';

void main() {
  test('a WHDLoad setup gets 8MB of Z2 fast RAM', () {
    // Almost every slave expects it; a stock A1200 has none.
    final EmulatorSettings whdload =
        WizardMode.whdload.settingsFor(AmigaModel.a1200);
    expect(whdload.fastRam, 8);

    // And it reaches the config as Z2 fast, not Z3.
    final String text = ConfigGenerator.generate(whdload);
    expect(text, contains('fastmem_size=8'));

    // Other kinds keep the machine's own memory.
    expect(WizardMode.floppy.settingsFor(AmigaModel.a500).fastRam, 0);
    expect(WizardMode.floppy.settingsFor(AmigaModel.a1200).fastRam, 0);
  });

  test('changing the machine inside a WHDLoad setup keeps the fast RAM', () {
    // The machine picker rebuilds the settings from the model, which is where
    // a mode-specific default is easiest to lose.
    expect(WizardMode.whdload.settingsFor(AmigaModel.a4000).fastRam, 8);
    expect(WizardMode.whdload.settingsFor(AmigaModel.a600).fastRam, 8);
  });
}
