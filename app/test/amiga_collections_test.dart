import 'package:flutter_test/flutter_test.dart';
import 'package:uae4arm2026/data/amiga_collections.dart';
import 'package:uae4arm2026/data/file_category.dart';
import 'package:uae4arm2026/data/media_library.dart';

MediaFile file(String path, FileCategory category) =>
    MediaFile(path: path, category: category, size: 1);

void main() {
  test('names the packs it recognises, and where', () {
    final MediaIndex index = MediaIndex(
      roots: const <String>['/sd/Amiga'],
      files: <MediaFile>[
        file('/sd/Amiga/HardDrives/AGS_UAE/System.hdf', FileCategory.hardDrives),
        file('/sd/Amiga/HardDrives/AmigaVision/AmigaVision.hdf',
            FileCategory.hardDrives),
        file('/sd/Amiga/lha/Zeb-WHDLoad-2024/boot.lha',
            FileCategory.whdloadGames),
      ],
    );

    final Map<AmigaCollection, String> found = AmigaCollection.findIn(index);

    expect(found[AmigaCollection.ags], '/sd/Amiga/HardDrives/AGS_UAE');
    expect(found[AmigaCollection.amigaVision],
        '/sd/Amiga/HardDrives/AmigaVision');
    expect(found[AmigaCollection.zebWhdload],
        '/sd/Amiga/lha/Zeb-WHDLoad-2024');
    // Reported as absent rather than omitted: "not found" is an answer.
    expect(found.containsKey(AmigaCollection.pimiga), isFalse);
  });

  test('a floppy named after a pack is not the pack', () {
    final MediaIndex index = MediaIndex(
      roots: const <String>['/sd/Amiga'],
      files: <MediaFile>[
        file('/sd/Amiga/Floppies/pimiga-intro.adf', FileCategory.floppies),
      ],
    );
    expect(AmigaCollection.findIn(index), isEmpty);
  });

  test('Zeb needs both halves of its name', () {
    final MediaIndex index = MediaIndex(
      roots: const <String>['/sd/Amiga'],
      files: <MediaFile>[
        file('/sd/Amiga/HardDrives/Zebra Games/games.hdf',
            FileCategory.hardDrives),
      ],
    );
    expect(AmigaCollection.findIn(index).containsKey(AmigaCollection.zebWhdload),
        isFalse);
  });
}
