import 'package:flutter_test/flutter_test.dart';
import 'package:uae4arm2026/data/core_kind.dart';

void main() {
  group('CoreKind.fromConfigText', () {
    test('a config with no marker is Amiberry', () {
      // Every .uae written before core selection existed looks like this;
      // the answer must never change or old setups silently switch core.
      const String text = 'config_description=Old Game\n'
          'amiga_model=A1200\n'
          'chipset=aga\n';
      expect(CoreKind.fromConfigText(text), CoreKind.amiberry);
    });

    test('the copperline marker selects Copperline', () {
      const String text = 'amiga_model=A1200\n'
          '; retro-amiga: core=copperline\n';
      expect(CoreKind.fromConfigText(text), CoreKind.copperline);
    });

    test('an unknown core name falls back to Amiberry', () {
      // The file is still a .uae; the conservative core is the one the
      // format was written for.
      const String text = '; retro-amiga: core=hypothetical\n';
      expect(CoreKind.fromConfigText(text), CoreKind.amiberry);
    });

    test('marker spacing is tolerated the way collection markers are', () {
      const String text = '; retro-amiga: core= copperline  \n';
      expect(CoreKind.fromConfigText(text), CoreKind.copperline);
    });
  });

  group('CoreKind.markerLine', () {
    test('Amiberry writes no marker', () {
      // Not writing one keeps old files byte-for-byte what they were.
      expect(CoreKind.amiberry.markerLine, isNull);
    });

    test('Copperline writes the marker fromConfigText reads back', () {
      final String line = CoreKind.copperline.markerLine!;
      expect(CoreKind.fromConfigText(line), CoreKind.copperline);
    });
  });

  group('state extensions', () {
    test('each core resumes through its own format', () {
      expect(CoreKind.amiberry.stateExtension, '.uss');
      expect(CoreKind.copperline.stateExtension, '.clstate');
      // The formats are not interchangeable: a state only ever resumes
      // through the core that wrote it.
      expect(
        CoreKind.amiberry.stateExtension,
        isNot(CoreKind.copperline.stateExtension),
      );
    });
  });
}
