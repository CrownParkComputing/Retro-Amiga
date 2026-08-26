// JIT is a platform capability, not a preference.
//
// Five different places in the app turn JIT on -- the config editor's switch,
// the wizard's switch, the AGS setup, and the collection recipes -- and none
// of them asked which platform they were configuring for. On iOS that is not a
// slow setup, it is one the core cannot honour: Apple does not allow memory to
// be both writable and executable, which is the entire mechanism.
//
// So the generator decides, and this pins that down. It is a host-side test,
// which means it runs as Linux -- JIT available -- so what it can prove is
// that the decision goes through one gate rather than being scattered, and
// that the gate is wired to every field JIT touches.
import 'package:flutter_test/flutter_test.dart';

import 'package:uae4arm2026/data/amiga_collections.dart';
import 'package:uae4arm2026/data/config_generator.dart';
import 'package:uae4arm2026/data/emulator_settings.dart';

String gen(EmulatorSettings settings) => ConfigGenerator.generate(
  settings,
  isDirectoryPath: (String path) => false,
  hasRdb: (String path) => true,
);

void main() {
  test('the generator, not the settings, decides whether JIT is written', () {
    const EmulatorSettings wants = EmulatorSettings(
      cpuModel: 68040,
      jitCacheSize: 16384,
      jitFpu: true,
    );
    final String config = gen(wants);

    if (jitAvailable) {
      expect(config, contains('cachesize=16384'));
      expect(config, contains('compfpu=true'));
    } else {
      // The iOS answer: no cachesize line at all, rather than one the core
      // will read and be unable to act on.
      expect(config, isNot(contains('cachesize=')));
      expect(config, isNot(contains('compfpu=')));
    }
  });

  test('cpu_compatible follows whether JIT was actually written', () {
    // The two are a known-bad pairing, so cpu_compatible is forced off when a
    // JIT is in play. Where there is no JIT the pairing cannot arise and the
    // user's choice stands -- which is what makes this depend on the written
    // config rather than on the requested settings.
    const EmulatorSettings wants = EmulatorSettings(
      cpuModel: 68040,
      cpuCompatible: true,
      jitCacheSize: 16384,
    );
    final String config = gen(wants);
    expect(
      config,
      contains('cpu_compatible=${jitAvailable ? 'false' : 'true'}'),
    );
  });

  test('every collection recipe survives a platform without a JIT', () {
    // The recipes ask for a JIT unconditionally, which is correct: they
    // describe the machine the distribution wants. What must not happen is a
    // config that names one on a platform that has none.
    for (final AmigaCollection collection in AmigaCollection.values) {
      final EmulatorSettings machine = collection.machine(
        const EmulatorSettings(romFile: 'kick40068.rom'),
        <String>['/hd/One'],
      );
      final String config = gen(machine);
      if (!jitAvailable) {
        expect(
          config,
          isNot(contains('cachesize=')),
          reason: collection.name,
        );
      }
      // The rest of the machine is unaffected either way.
      expect(config, contains('cpu_model=${machine.cpuModel}'),
          reason: collection.name);
    }
  });
}
