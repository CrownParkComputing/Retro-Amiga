import 'package:flutter_test/flutter_test.dart';
import 'package:uae4arm2026/data/whdload_support.dart';

void main() {
  test('ready needs the loader, not just the boot drive', () {
    // The archive is the drive's shell; WHDLoad is a separate file the booter
    // copies into C:. With the archive alone the game starts and AmigaDOS
    // says "whdload: unknown command", so this must not read as ready.
    const WhdloadStatus archiveOnly = WhdloadStatus(
      bootArchiveInstalled: true,
      kickstartCount: 1,
    );
    expect(archiveOnly.ready, isFalse);

    const WhdloadStatus complete = WhdloadStatus(
      bootArchiveInstalled: true,
      loaderInstalled: true,
      kickstartCount: 1,
    );
    expect(complete.ready, isTrue);

    // A Kickstart is still the player's to supply.
    const WhdloadStatus noRom = WhdloadStatus(
      bootArchiveInstalled: true,
      loaderInstalled: true,
      kickstartCount: 0,
    );
    expect(noRom.ready, isFalse);
  });
}
