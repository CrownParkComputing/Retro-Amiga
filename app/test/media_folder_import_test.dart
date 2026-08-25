import 'package:flutter_test/flutter_test.dart';
import 'package:uae4arm2026/data/file_category.dart';
import 'package:uae4arm2026/data/media_folder.dart';

FolderEntry entry(String name, {String directory = ''}) => FolderEntry(
  documentId: '$directory/$name',
  name: name,
  directory: directory,
  size: 1,
);

void main() {
  test('archives are imported for the startup extractor', () {
    final FolderEntry archive = entry('floppies.zip');
    expect(
      MediaFolderImporter.categoryFor(archive, <FolderEntry>[archive]),
      FileCategory.archives,
    );
  });

  test('CUE companion tracks stay with their CD image', () {
    final List<FolderEntry> files = <FolderEntry>[
      entry('game.cue', directory: 'CD32/Game'),
      entry('track01.bin', directory: 'CD32/Game'),
      entry('track02.wav', directory: 'CD32/Game'),
    ];

    for (final FolderEntry file in files) {
      expect(
        MediaFolderImporter.categoryFor(file, files),
        FileCategory.cdImages,
      );
    }
  });

  test('a BIN without a neighbouring CUE remains a ROM', () {
    final FolderEntry rom = entry('kick31.bin', directory: 'Kickstarts');
    expect(
      MediaFolderImporter.categoryFor(rom, <FolderEntry>[rom]),
      FileCategory.roms,
    );
  });

  test(
    'nested folders are retained and traversal components are discarded',
    () {
      expect(
        MediaFolderImporter.safeRelativeDirectory('../AGS/./Games\\Arcade'),
        'AGS/Games/Arcade',
      );
    },
  );
}
