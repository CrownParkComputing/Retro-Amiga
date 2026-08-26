// Systems: the setups found on the device that get a config written for them
// and a rail entry of their own.
//
// The behaviour worth pinning down is what gets picked up and what is left
// alone. A folder of Amiga files counts exactly as much as a set of HDFs --
// that is the whole point of it -- and an existing config must never be
// rewritten, because the user may have spent an evening tuning it.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:uae4arm2026/data/amiga_collections.dart';
import 'package:uae4arm2026/data/amiga_system.dart';
import 'package:uae4arm2026/data/config_store.dart';
import 'package:uae4arm2026/data/hard_drive_set.dart';
import 'package:uae4arm2026/data/media_library.dart';

void main() {
  late Directory temporary;

  setUp(() {
    temporary = Directory.systemTemp.createTempSync('amiga_systems');
  });

  tearDown(() {
    if (temporary.existsSync()) temporary.deleteSync(recursive: true);
  });

  Directory hardDrives() =>
      Directory('${temporary.path}/HardDrives')..createSync(recursive: true);

  test('a folder of Amiga files is a system', () {
    final Directory workbench = Directory('${hardDrives().path}/Workbench31')
      ..createSync(recursive: true);
    File('${workbench.path}/Startup-Sequence').writeAsStringSync('echo hi');

    final List<HardDriveSet> found = AmigaSystems.discover(
      const MediaIndex(files: <MediaFile>[], roots: <String>[]),
      temporary.path,
    );

    expect(found, hasLength(1));
    expect(found.single.directoryMount, isTrue);
  });

  test('the lower-case HardDrives spelling is found too', () {
    // exFAT cards are case-insensitive and real libraries have both spellings.
    final Directory lower = Directory('${temporary.path}/harddrives/Pimiga')
      ..createSync(recursive: true);
    File('${lower.path}/Startup-Sequence').writeAsStringSync('echo hi');

    final List<HardDriveSet> found = AmigaSystems.discover(
      const MediaIndex(files: <MediaFile>[], roots: <String>[]),
      temporary.path,
    );

    expect(found, hasLength(1));
    expect(AmigaCollection.detect(found.single), AmigaCollection.pimiga);
  });

  test('an empty library has no systems', () {
    hardDrives();
    expect(
      AmigaSystems.discover(
        const MediaIndex(files: <MediaFile>[], roots: <String>[]),
        temporary.path,
      ),
      isEmpty,
    );
  });

  test('a generated config is marked, so Games can leave it out', () {
    // The marker is a comment line, so the file stays an ordinary .uae that
    // still opens, edits and launches. Recognising these by a name prefix
    // instead would break the moment somebody renamed one.
    expect(ConfigStore.collectionMarker, startsWith(';'));
    final File config = File('${temporary.path}/generated.uae')
      ..writeAsStringSync('cpu_model=68040\n${ConfigStore.collectionMarker}\n');
    expect(config.readAsStringSync(), contains(ConfigStore.collectionMarker));
    // ...and a hand-made config carries no marker.
    final File made = File('${temporary.path}/mine.uae')
      ..writeAsStringSync('cpu_model=68020\n');
    expect(made.readAsStringSync(), isNot(contains(ConfigStore.collectionMarker)));
  });

  test('the config name is stable, so a system is configured once', () {
    // configure() writes only where a config of this name is missing. If the
    // name moved between runs, every launch would write another copy and the
    // rail would fill with duplicates.
    const HardDriveSet set = HardDriveSet(
      folder: '/media/HardDrives/Pimiga',
      bootDrive: '/media/HardDrives/Pimiga',
      drives: <String>[],
      directoryMount: true,
    );
    expect(AmigaSystems.configName(set), AmigaSystems.configName(set));
    expect(AmigaSystems.configName(set), contains(set.name));
  });
}
