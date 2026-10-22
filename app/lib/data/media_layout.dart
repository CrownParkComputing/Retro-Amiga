import 'dart:io';

import 'file_category.dart';
import 'media_folder.dart';
import 'media_root.dart';

/// What a picked folder looks like before anything is copied, and what the
/// import found when it landed.
///
/// Three failure shapes this exists to catch, all silent until now:
///
/// 1. The wrong level - the user grants the folder ABOVE their collection,
///    so every file arrives nested under a single extra directory the app
///    files whole anyway.
/// 2. No layout at all - loose files at the top with none of the standard
///    per-kind subfolders. Import still works, but the user learns the
///    layout exists at all only by reading the result.
/// 3. Encrypted Kickstarts - Cloanto/Amiga Forever ROMs carry an
///    AMIROMTYPE1 magic and are only readable with the rom.key they ship
///    beside, which nothing here can use. They index as ROMs and every
///    config that picks one fails the same opaque way.
class MediaLayoutReport {
  const MediaLayoutReport({
    required this.recognizedMedia,
    required this.presentSubfolders,
    required this.looseMediaFiles,
    required this.readableInPlace,
    this.umbrellaFolder,
    this.cloantoKeys = 0,
    this.encryptedRoms = 0,
  });

  /// Files in the picked tree the app knows what to do with.
  final int recognizedMedia;

  /// Expected per-kind subfolders found at the top of the picked folder.
  final Set<String> presentSubfolders;

  /// Recognised media sitting at the top level rather than in a subfolder.
  final int looseMediaFiles;

  /// True when the granted folder can be read directly by this process -
  /// older Android and the handheld ROMs that allow it - rather than having
  /// every file copied through the resolver.
  final bool readableInPlace;

  /// Set when every recognised file sits under ONE top-level subfolder with
  /// a name that is not a standard media folder - the signature of having
  /// picked the parent of the collection instead of the collection.
  final String? umbrellaFolder;

  /// rom.key files seen: Cloanto ships one beside every encrypted ROM.
  final int cloantoKeys;

  /// ROM files carrying the AMIROMTYPE1 encryption magic.
  final int encryptedRoms;

  /// Expected subfolder names that were NOT present. Informational: an
  /// empty Kickstarts folder is worth saying, a missing Music is not.
  List<String> get missingSubfolders {
    final Set<String> lower = <String>{
      for (final String name in presentSubfolders) name.toLowerCase(),
    };
    return <String>[
      for (final String name in MediaRoot.folders.values)
        if (!lower.contains(name.toLowerCase())) name,
    ];
  }

  /// Problems worth telling the user about, in the order to show them.
  List<String> get warnings => <String>[
        if (recognizedMedia == 0)
          'Nothing in that folder is a file the app recognises. The media '
              'folder holds Kickstarts, Floppies, HardDrives, CDROMs, LHA '
              'and Music subfolders - point it at a folder that has them.',
        if (umbrellaFolder != null)
          'Everything sits inside "$umbrellaFolder" - you picked the folder '
              'above the collection. Re-pick "$umbrellaFolder" itself so its '
              'subfolders land at the top.',
        if (recognizedMedia > 0 &&
            presentSubfolders.isEmpty &&
            umbrellaFolder == null)
          'The files sit loose at the top of the folder rather than in '
              'subfolders. They will still be filed by type on import, but '
              'the layout the app expects is Kickstarts, Floppies, '
              'HardDrives, CDROMs, LHA and Music.',
        if (!readableInPlace && recognizedMedia > 0)
          'This Android version does not let the app read the folder where '
              'it is, so recognised files are copied into the app\'s own '
              'storage. Keep enough free space for a second copy.',
        if (cloantoKeys > 0 || encryptedRoms > 0)
          'Amiga Forever (Cloanto) Kickstarts are encrypted and cannot be '
              'used - the rom.key they ship beside only unlocks them for '
              'Cloanto\'s own emulators. Use an unencrypted Kickstart dump '
              'instead.',
      ];
}

class MediaLayoutCheck {
  const MediaLayoutCheck._();

  /// The magic bytes of a Cloanto-encrypted Kickstart, as the core itself
  /// keys off them (src/memory.cpp). Eleven bytes at offset zero.
  static const String encryptedRomMagic = 'AMIROMTYPE1';

  /// Expected subfolder names, compared case-insensitively: collections
  /// arrive as "floppies" and "KICKSTARTS" as often as the canonical case.
  static final Set<String> _expected = <String>{
    for (final String name in MediaRoot.folders.values) name.toLowerCase(),
  };

  /// Reads the header of [file] and says whether it is a Cloanto-encrypted
  /// ROM. Reads eleven bytes, not the file - safe on a 512KB Kickstart.
  static Future<bool> isEncryptedRom(File file) async {
    try {
      final RandomAccessFile handle = await file.open();
      try {
        final List<int> head =
            await handle.read(encryptedRomMagic.length);
        return String.fromCharCodes(head) == encryptedRomMagic;
      } finally {
        await handle.close();
      }
    } on Object {
      return false;
    }
  }

  /// Counts encrypted ROMs under a Kickstarts folder, post-import.
  static Future<int> countEncryptedRoms(Directory kickstarts) async {
    if (!kickstarts.existsSync()) return 0;
    int found = 0;
    await for (final FileSystemEntity entity in kickstarts.list(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is! File) continue;
      if (!entity.path.toLowerCase().endsWith('.rom')) continue;
      if (await isEncryptedRom(entity)) found++;
    }
    return found;
  }

  /// Analyses a granted folder from its entry list - the SAF path, where
  /// content bytes are not available but names and folders are.
  static MediaLayoutReport fromEntries(
    List<FolderEntry> entries, {
    required bool readableInPlace,
  }) {
    final Set<String> present = <String>{};
    final Set<String> umbrellaCandidates = <String>{};
    int loose = 0;
    int recognised = 0;
    int keys = 0;

    for (final FolderEntry entry in entries) {
      final String directory = entry.directory.replaceAll(r'\', '/');
      final List<String> parts = directory
          .split('/')
          .where((String part) => part.isNotEmpty)
          .toList();
      final String top = parts.isEmpty ? '' : parts.first;
      if (top.isNotEmpty && _expected.contains(top.toLowerCase())) {
        present.add(top);
      }
      if (entry.name.toLowerCase() == 'rom.key') keys++;

      final FileCategory? category = FileCategory.fromPath(entry.name);
      if (category == null) continue;
      recognised++;
      if (top.isEmpty) {
        loose++;
      } else if (!_expected.contains(top.toLowerCase())) {
        umbrellaCandidates.add(top);
      }
    }

    // Every recognised file under one non-standard folder = the user handed
    // over the collection's parent. Two or more top folders is a layout,
    // one is a mistake.
    final String? umbrella = recognised > 0 &&
            loose == 0 &&
            umbrellaCandidates.length == 1
        ? umbrellaCandidates.first
        : null;

    return MediaLayoutReport(
      recognizedMedia: recognised,
      presentSubfolders: present,
      looseMediaFiles: loose,
      readableInPlace: readableInPlace,
      umbrellaFolder: umbrella,
      cloantoKeys: keys,
    );
  }

  /// The same analysis for a folder on real storage - the in-place path,
  /// where a POSIX listing worked and nothing will be copied.
  static Future<MediaLayoutReport> fromPath(String path) async {
    final Directory dir = Directory(path);
    final Set<String> present = <String>{};
    int loose = 0;
    int recognised = 0;
    int keys = 0;
    try {
      await for (final FileSystemEntity entity in dir.list(
        followLinks: false,
      )) {
        final String name = entity.path.split('/').last;
        if (entity is Directory &&
            _expected.contains(name.toLowerCase())) {
          present.add(name);
        } else if (entity is File) {
          if (name.toLowerCase() == 'rom.key') keys++;
          if (FileCategory.fromPath(name) != null) {
            recognised++;
            loose++;
          }
        }
      }
    } on FileSystemException {
      // Barely-readable root: report what little was learned rather than
      // pretend the folder was empty.
    }
    return MediaLayoutReport(
      recognizedMedia: recognised,
      presentSubfolders: present,
      looseMediaFiles: loose,
      readableInPlace: true,
      cloantoKeys: keys,
    );
  }
}
