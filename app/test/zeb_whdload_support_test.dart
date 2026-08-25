import 'package:flutter_test/flutter_test.dart';
import 'package:uae4arm2026/data/zeb_whdload_support.dart';

void main() {
  test('only a named Zeb WHDLoad setup gets the bootstrap', () {
    expect(
      ZebWhdloadSupport.appliesTo(<String>[
        '/Amiga/HardDrives/Zeb WHDLoad 15 Feb/Zebs-WHDLoad.img',
      ]),
      isTrue,
    );
    expect(
      ZebWhdloadSupport.appliesTo(<String>[
        '/Amiga/HardDrives/AGS_UAE/Workbench.hdf',
      ]),
      isFalse,
    );
  });

  test('bootstrap populates Devs Kickstarts before Zeb starts', () {
    final String script = ZebWhdloadSupport.startupSequence;
    expect(script, contains('Workbench:Devs/Kickstarts'));
    expect(script, contains('save-data:Kickstarts/#?'));
    expect(
      script.indexOf('Copy save-data:'),
      lessThan(script.indexOf('Execute Workbench:S/Startup-Sequence')),
    );
  });
}
