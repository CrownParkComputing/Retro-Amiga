import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:uae4arm2026/data/config_store.dart';
import 'package:uae4arm2026/emulator.dart';

void main() {
  test('a config names its WHDLoad archive where the repair can reach it', () {
    // The launch reads whdload_filename back out of the file after repairing
    // it, so the repair has to see that line as a media path. iOS hands the
    // app a new container on every install; a path the repair misses is a
    // black screen, because the booter is given an archive that is not there.
    const String config = '''
kickstart_rom_file=/var/mobile/Containers/Data/Application/OLD/Documents/kick.rom
whdload_filename=/var/mobile/Containers/Data/Application/OLD/Documents/LHA/Game.lha
fastmem_size=8
''';
    final List<String> paths = ConfigStore.mediaPathsIn(config);
    expect(
      paths,
      contains(
        '/var/mobile/Containers/Data/Application/OLD/Documents/LHA/Game.lha',
      ),
    );
  });

  test('the archive comes from the file, not from a stale record', () async {
    final Directory dir = Directory.systemTemp.createTempSync('launch');
    final File file = File('${dir.path}/game.uae')
      ..writeAsStringSync('whdload_filename=${dir.path}/Current.lha\n');

    // What the launcher would have believed before the repair.
    const String stale = '/var/mobile/Containers/Data/Application/OLD/x.lha';
    expect(await Emulator.archiveFor(file.path, stale), '${dir.path}/Current.lha');

    // A config with no archive falls back to what the caller passed.
    final File plain = File('${dir.path}/plain.uae')
      ..writeAsStringSync('chipmem_size=4\n');
    expect(await Emulator.archiveFor(plain.path, stale), stale);

    dir.deleteSync(recursive: true);
  });
}
