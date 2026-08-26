import 'amiga_model.dart';
import 'emulator_settings.dart';
import 'file_category.dart';
import 'hard_drive_set.dart';
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
/// So each known collection is reported by name, and each one also carries
/// the machine it needs -- because knowing that a folder is PiMiga is only
/// useful if something then configures an 040 with a graphics card to run it.
/// Point any of these at the A500 a new setup starts as and none of them
/// fails in a way anyone can act on: it hangs on grey, or boots to a
/// Workbench with nothing runnable on it.
///
/// Declaration order is DETECTION order, most specific first. PiMiga ships an
/// AGS-style launcher of its own, so a folder that looks like both is PiMiga.
enum AmigaCollection {
  /// PiMiga, built for the Raspberry Pi and commonly moved onto a handheld.
  /// An 040 AGA machine with a big Zorro III card; the heaviest of the four.
  pimiga(
    'PiMiga',
    'Raspberry Pi Amiga build, one large drive image.',
    <String>['pimiga', 'pi-miga', 'pi miga'],
  ),

  /// AmigaVision, which the Amiga Vision spelling still turns up as.
  amigaVision(
    'AmigaVision',
    'Curated WHDLoad collection on one large drive image.',
    <String>['amigavision', 'amiga vision', 'amiga-vision'],
  ),

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

  ;

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

  /// Which collection this drive set is, or null for an ordinary hard drive.
  ///
  /// Matched against the whole set -- folder, boot drive and every image --
  /// because the giveaway is as often the image name as the folder's.
  static AmigaCollection? detect(HardDriveSet set) {
    final String identity = <String>[
      set.folder,
      set.bootDrive,
      ...set.drives,
    ].join('/').toLowerCase().replaceAll(r'\', '/');
    for (final AmigaCollection collection in AmigaCollection.values) {
      if (collection._matches(identity)) return collection;
    }
    return null;
  }

  /// The machine this collection needs, keeping the ROM already chosen and
  /// taking the drives it is about to mount.
  ///
  /// Built from defaults rather than from [current] so a collection is the
  /// same machine every time: a setup half-carried over from whatever the
  /// user picked before is the kind of thing that runs on one device and not
  /// on the next.
  ///
  /// The numbers come from the configurations these distributions ship or
  /// document -- PiMiga's from a working Amiberry Pimiga5.uae -- rather than
  /// from a guess at what "fast" means.
  EmulatorSettings machine(EmulatorSettings current, List<String> drives) {
    switch (this) {
      case AmigaCollection.pimiga:
        return EmulatorSettings.fromModel(AmigaModel.a1200).copyWith(
          chipset: 'aga',
          cpuModel: 68040,
          fpuModel: 68040,
          cpuSpeed: 'max',
          // 040 JIT wants the compatible/24-bit pair off and the FPU compiled
          // too; anything less runs, slowly, and hides the fact.
          cpuCompatible: false,
          address24Bit: false,
          jitCacheSize: 16384,
          jitFpu: true,
          chipRam: 16, // 8MB, as PiMiga's own config asks for
          z3Ram: 256,
          // RTG, which the collections here are built around.
          //
          // This was off for a while because an RTG screen came up black. The
          // cause turned out not to be the RTG path at all: the chipset's
          // drawing thread was dereferencing a null line pointer on any line
          // that fell outside the visible area and dying where it stood, so
          // the frame queue stopped being consumed and the picture froze or
          // never arrived. See draw_denise_line in drawing.cpp.
          //
          // An RTG frame does not reach show_screen() -- it goes through
          // amiberry_renderframe(), which needs a renderer headless does not
          // have -- so the tap that hands frames to the app is in the picasso
          // unlock instead. Worth remembering that the screen mode itself
          // lives in the Amiga's own prefs on the user's drive: once a
          // collection is switched to an RTG mode it boots into one every
          // time, so a mode that cannot be published is a machine that cannot
          // be recovered from its own settings.
          useRtg: true,
          rtgMemory: 32,
          rtgTrueColour: true,
          romFile: current.romFile,
          hardDrives: drives,
        );
      case AmigaCollection.amigaVision:
        return EmulatorSettings.fromModel(AmigaModel.a1200).copyWith(
          chipset: 'aga',
          cpuModel: 68040,
          fpuModel: 68040,
          cpuSpeed: 'max',
          cpuCompatible: false,
          address24Bit: false,
          jitCacheSize: 16384,
          jitFpu: true,
          chipRam: 4, // 2MB, a real A1200's maximum
          z3Ram: 256,
          // Off for the same reason as PiMiga's above: headless cannot
          // publish an RTG frame, so an RTG screen is a black panel.
          useRtg: false,
          rtgMemory: 32,
          rtgTrueColour: true,
          romFile: current.romFile,
          hardDrives: drives,
        );
      case AmigaCollection.ags:
        // AGS runs its selector on RTG and expects a quick A1200.
        return EmulatorSettings.fromModel(AmigaModel.a1200).copyWith(
          cpuSpeed: 'max',
          fpuModel: 68882,
          jitCacheSize: 16384,
          chipRam: 4,
          z3Ram: 256,
          // AGS runs its selector on a graphics-card screen and expects one.
          useRtg: true,
          rtgMemory: 32,
          rtgTrueColour: true,
          romFile: current.romFile,
          hardDrives: drives,
        );
      case AmigaCollection.zebWhdload:
        // A 68020 Workbench on its native screen. No RTG: the pack draws to
        // an AGA screen mode, and switching it to a graphics card is how it
        // ends up booting to nothing.
        return EmulatorSettings.fromModel(AmigaModel.a1200).copyWith(
          cpuSpeed: 'max',
          jitCacheSize: 8192,
          chipRam: 4,
          z3Ram: 64,
          romFile: current.romFile,
          hardDrives: drives,
        );
    }
  }

  /// The machine in one line, so the wizard can say what it is about to do
  /// instead of silently rewriting the user's choices.
  String get machineBlurb {
    switch (this) {
      case AmigaCollection.pimiga:
        return 'A1200/040, 8MB chip, 256MB Zorro III, RTG';
      case AmigaCollection.amigaVision:
        return 'A1200/040, 2MB chip, 256MB Zorro III, native screen';
      case AmigaCollection.ags:
        return 'A1200, 2MB chip, 256MB Zorro III, RTG';
      case AmigaCollection.zebWhdload:
        return 'A1200/020, native screen';
    }
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
