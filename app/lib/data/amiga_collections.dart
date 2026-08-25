import 'file_category.dart';
import 'media_library.dart';

/// The big pre-built Amiga collections, and whether this device has one.
///
/// These are what most people actually run: nobody assembles a WHDLoad set by
/// hand any more, they download AGS or AmigaVision and point an emulator at
/// it. The wizard used to say nothing about them at all -- it reported file
/// counts per category, so a 40GB AmigaVision drive appeared as "Hard Drives:
/// 1" and a PiMiga image as nothing recognisable. Someone who had just copied
/// one across had no way to tell whether the app had understood it.
///
/// So each known collection is reported by name, found or not. "Not found" is
/// as much of an answer as "found": it is the difference between "the app
/// cannot see my card" and "the app can see my card and that pack is not on
/// it".
enum AmigaCollection {
  /// AGS / AGS_UAE -- the menu-driven front end, usually a set of HDFs with a
  /// shared games directory beside them.
  ags(
    'AGS',
    'Menu-driven game launcher, usually several hard-drive images.',
    <String>['ags_uae', 'ags-uae', 'agsuae', 'ags'],
  ),

  /// The dated full-disk WHDLoad pack, commonly called Zeb's.
  ///
  /// Its name almost never contains "zeb". What it is actually distributed as
  /// is a folder and image named for the build date -- "A1200 WHDLoad
  /// (15-Feb-2026).hdf" beside a partition calculator and a couple of PDFs --
  /// so matching on "zeb" found a 25GB pack sitting in plain sight exactly
  /// never. The date in brackets after the word is the signature.
  zebWhdload(
    'WHDLoad pack',
    'Dated full-disk WHDLoad image, usually called Zeb\'s.',
    <String>['zeb'],
    alsoNeeds: <String>['whd'],
    patterns: <String>[r'whdload\s*\('],
  ),

  /// AmigaVision, which the Amiga Vision spelling still turns up as.
  amigaVision(
    'AmigaVision',
    'Curated WHDLoad collection on one large drive image.',
    <String>['amigavision', 'amiga vision', 'amiga-vision', 'amigavision'],
  ),

  /// PiMiga, built for the Raspberry Pi and commonly moved onto a handheld.
  pimiga(
    'PiMiga',
    'Raspberry Pi Amiga build, one large drive image.',
    <String>['pimiga', 'pi-miga', 'pi miga'],
  );

  const AmigaCollection(
    this.displayName,
    this.description,
    this.fragments, {
    this.alsoNeeds = const <String>[],
    this.patterns = const <String>[],
  });

  final String displayName;
  final String description;

  /// Any one of these in a path is a match.
  final List<String> fragments;

  /// ...but every one of these must be there too. Zeb needs both halves:
  /// "zeb" alone matches a folder called Zebra.
  final List<String> alsoNeeds;

  /// Where a substring is not enough. Any one of these matching is a match on
  /// its own, without [alsoNeeds] -- these are already specific.
  final List<String> patterns;

  bool _matches(String lowerPath) {
    for (final String pattern in patterns) {
      if (RegExp(pattern).hasMatch(lowerPath)) return true;
    }
    if (!fragments.any(lowerPath.contains)) return false;
    return alsoNeeds.every(lowerPath.contains);
  }

  /// Where this collection was found, or null.
  ///
  /// Hard drives, WHDLoad archives and CD images are searched, because that
  /// is what these ship as. Floppies are not: a single ADF named after a pack
  /// is not the pack.
  static Map<AmigaCollection, String> findIn(MediaIndex index) {
    const List<FileCategory> searched = <FileCategory>[
      FileCategory.hardDrives,
      FileCategory.whdloadGames,
      FileCategory.cdImages,
      FileCategory.archives,
    ];

    final Map<AmigaCollection, String> found = <AmigaCollection, String>{};
    for (final FileCategory category in searched) {
      for (final MediaFile file in index.of(category)) {
        final String lower = file.path.toLowerCase().replaceAll(r'\', '/');
        for (final AmigaCollection collection in AmigaCollection.values) {
          // First hit wins: the point is to name the folder, and the first
          // one is as good as any for that.
          if (!found.containsKey(collection) && collection._matches(lower)) {
            found[collection] = file.directory.isEmpty
                ? file.path
                : file.directory;
          }
        }
      }
    }
    return found;
  }
}
