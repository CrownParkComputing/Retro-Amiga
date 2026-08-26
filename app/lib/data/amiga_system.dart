import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' show Size;

import 'amiga_collections.dart';
import 'amiga_model.dart';
import 'app_log.dart';
import 'config_store.dart';
import 'emulator_settings.dart';
import 'file_category.dart';
import 'hard_drive_set.dart';
import 'media_library.dart';
import 'media_root.dart';
import 'zeb_whdload_support.dart';

/// A whole Amiga system found on this device, ready to run.
///
/// Not a disk and not a config: a curated setup — AGS, AmigaVision, PiMiga, a
/// WHDLoad pack, or simply a folder of Amiga files someone copied off a real
/// machine — together with the hardware it needs.
///
/// These are what most people actually run, and until now getting into one
/// took the full wizard: choose a mode, pick a folder, answer questions about
/// a machine you have no way to reason about, save a config, then find it in
/// a list. Every answer was already knowable from the folder. So they are
/// configured on startup and put on the rail, and running one is one tap.
class AmigaSystem {
  const AmigaSystem({
    required this.name,
    required this.set,
    required this.collection,
    required this.configPath,
  });

  /// What to call it on the rail. The collection's name where it is one of
  /// the known packs, otherwise the folder's.
  final String name;

  final HardDriveSet set;

  /// Which known distribution this is, or null for a plain folder.
  final AmigaCollection? collection;

  /// The generated config, ready to launch.
  final String configPath;

  /// A folder of Amiga files rather than a set of drive images.
  bool get isFolder => set.directoryMount;

  /// One line describing the machine it runs as.
  String get machineSummary =>
      collection?.machineBlurb ?? (isFolder ? 'A1200, folder as DH0' : 'A1200');

  /// The rail's icon for this system.
  String get icon {
    switch (collection) {
      case AmigaCollection.pimiga:
        return '🍓';
      case AmigaCollection.amigaVision:
        return '🎬';
      case AmigaCollection.ags:
        return '🎯';
      case AmigaCollection.zebWhdload:
        return '📦';
      case null:
        return isFolder ? '📁' : '💽';
    }
  }
}

/// Finds the systems on this device and keeps a config for each.
class AmigaSystems {
  const AmigaSystems._();

  /// The folder of arcade RTG collections PiMiga mounts alongside itself.
  ///
  /// A sibling of the PiMiga folder under HardDrives, holding the MANX
  /// conversions -- 1943, S16, R-Type and the rest -- each as a directory,
  /// plus the shared MANX volume their launchers expect. Kept OUTSIDE the
  /// PiMiga drive images so the collections can be updated by copying files,
  /// without rebuilding a 13GB HDF.
  static const String arcadeFolderName = 'PimigaArcade';

  /// The name a generated config gets, kept stable so a system is configured
  /// once rather than once per startup.
  static String configName(HardDriveSet set) =>
      '${ConfigStore.collectionNamePrefix}${set.name}';

  /// Every hard-drive setup under the library's HardDrives folder.
  ///
  /// Includes the plain folders as well as the image-based packs: a directory
  /// mount is exactly as runnable as an HDF, and a shared folder someone
  /// dropped in is the case the app was worst at before.
  static List<HardDriveSet> discover(MediaIndex index, String libraryRoot) {
    final String root = libraryRoot.replaceAll(r'\', '/').replaceAll(
      RegExp(r'/+$'),
      '',
    );
    for (final String name in const <String>['HardDrives', 'harddrives']) {
      final Directory dir = Directory('$root/$name');
      if (!dir.existsSync()) continue;
      final List<HardDriveSet> found = HardDriveSet.discoverIn(index, dir.path);
      if (found.isNotEmpty) {
        // The arcade folder is an ADDON, not a system: it holds the RTG
        // collections PiMiga mounts alongside itself, and has no OS of its
        // own -- a config generated for it alone would boot to nothing.
        return found
            .where(
              (HardDriveSet set) =>
                  set.name.toLowerCase() != arcadeFolderName.toLowerCase(),
            )
            .toList();
      }
    }
    return const <HardDriveSet>[];
  }

  /// The widest RTG screen a collection is set up with by default.
  ///
  /// The device's own resolution, up to 1080p. An RTG Workbench exists to use
  /// the screen it is on, and a collection that opens at half the panel's
  /// resolution looks like a mistake even when it is a deliberate one.
  ///
  /// This was capped at 720p for a while after a full-resolution screen made
  /// the app stop responding. Three separate things caused that and all three
  /// are fixed: the emulation thread was raised above the launcher's own
  /// threads and starved them; the machine committed 640MB of Zorro III and
  /// graphics memory and was killed reallocating buffers; and every published
  /// frame was walked pixel by pixel to force the alpha byte opaque, which at
  /// 1920x1080 is two million read-modify-writes fifty times a second. The
  /// last of those is why this cap can be lifted rather than merely raised --
  /// see host_framebuffer.cpp.
  ///
  /// Past 1080p there is nothing to gain: no Amiga software expects it, and
  /// the emulated chipset draws every one of those pixels.
  static const int maxRtgWidth = 1920;
  static const int maxRtgHeight = 1080;

  static int _rtgWidthFor(Size screen) => math
      .min(math.max(screen.width, screen.height).round(), maxRtgWidth);

  static int _rtgHeightFor(Size screen) => math
      .min(math.min(screen.width, screen.height).round(), maxRtgHeight);

  /// Whether [path] was written by the recipe this build carries.
  static Future<bool> _isCurrentRecipe(String path) async {
    try {
      final String text = await File(path).readAsString();
      return text.contains(
        ConfigStore.collectionStamp(ConfigStore.collectionRecipeVersion),
      );
    } on FileSystemException {
      return false;
    }
  }

  /// Configures every system found, writing a config only where one is
  /// missing, and returns them.
  ///
  /// Deliberately does not overwrite: a user who has edited the machine for
  /// their AGS install should not have it reset on the next launch because
  /// the app thinks it knows better. New systems get the recipe; existing
  /// ones are left exactly as they are.
  /// [screen] is the device's real resolution in pixels. The RTG screen is
  /// sized from it, but CAPPED -- see [maxRtgWidth].
  ///
  /// A Workbench on a graphics card should suit the display it is shown on,
  /// but "as many pixels as the panel has" is not the same as "as many pixels
  /// as the machine can drive". Every one of them is emulated.
  static Future<List<AmigaSystem>> configure({
    required MediaIndex index,
    EmulatorSettings? base,
    Size? screen,
  }) async {
    final String root = await MediaRoot.path();
    final List<HardDriveSet> sets = discover(index, root);
    final List<MediaFile> roms = index.of(FileCategory.roms);
    // Said every time, not only when something is written. "No collections"
    // and "collections already configured" look identical on screen, and
    // telling them apart afterwards is the whole job of this line.
    AppLog.info(
      'systems',
      '${sets.length} setup(s) under $root, ${roms.length} ROM(s) indexed',
    );
    if (sets.isEmpty) return const <AmigaSystem>[];

    // The machine every recipe starts from, and the ROM it will keep.
    //
    // Every collection here is an A1200-class system, so the Kickstart is
    // chosen for that rather than for whatever the user's default model
    // happens to be -- an AGS install given a 1.3 ROM is as dead as one given
    // none. AROS is accepted as a last resort: it boots, which is worth more
    // than a black screen, and the log says which was used.
    final EmulatorSettings start =
        (base ?? const EmulatorSettings()).copyWith(
      romFile:
          RomPicker.kickstartFor(AmigaModel.a1200, roms)?.path ?? '',
      // Landscape, whichever way the device is being held -- and capped.
      rtgWidth: screen == null ? null : _rtgWidthFor(screen),
      rtgHeight: screen == null ? null : _rtgHeightFor(screen),
    );
    AppLog.info(
      'systems',
      start.romFile.isEmpty
          ? 'no A1200 Kickstart found; collections will not boot'
          : 'using Kickstart ${start.romFile.split('/').last}',
    );

    final List<SavedConfig> existing = await ConfigStore.list();
    final Map<String, SavedConfig> byName = <String, SavedConfig>{
      for (final SavedConfig config in existing) config.name: config,
    };

    final List<AmigaSystem> systems = <AmigaSystem>[];
    for (final HardDriveSet set in sets) {
      final AmigaCollection? known = AmigaCollection.detect(set);
      final String name = configName(set);
      final SavedConfig? adopted = byName[name];
      String? path = adopted?.path;

      // Rebuild one written by an older recipe. See collectionRecipeVersion.
      if (adopted != null && !await _isCurrentRecipe(adopted.path)) {
        AppLog.info('systems', 'rebuilding $name from the current recipe');
        path = null;
      }

      // Mark one this app wrote before the marker existed.
      //
      // Without this an early build's configs stay in Games for good: the
      // filter reads the marker, and the only configs that ever got one were
      // the ones written after it was added. They are unambiguously ours --
      // matched by the generated name, against a set found in the library --
      // so the file is repaired in place rather than rewritten, which leaves
      // any tuning the user has done alone.
      if (adopted != null && !adopted.isCollection) {
        try {
          await File(adopted.path).writeAsString(
            '\n${ConfigStore.collectionMarker}\n',
            mode: FileMode.append,
          );
          AppLog.info('systems', 'marked $name as a collection');
        } on FileSystemException catch (e) {
          AppLog.warn('systems', 'could not mark $name: ${e.message}');
        }
      }

      if (path == null) {
        List<String> mounts = set.allMounts;
        if (known == AmigaCollection.pimiga) {
          // PiMiga gets the arcade collections as extra drives, when the
          // folder is there. MANX is mounted as its own volume because that
          // is the name the collection launchers look for.
          final String arcade =
              '${Directory(set.folder).parent.path}/$arcadeFolderName';
          if (Directory(arcade).existsSync()) {
            mounts = <String>[...mounts, arcade, '$arcade/MANX'];
            AppLog.info('systems', 'PiMiga: arcade collections mounted');
          }
        }
        EmulatorSettings settings = known == null
            ? start.copyWith(hardDrives: mounts)
            : known.machine(start, mounts);
        // Without a Kickstart the machine has no ROM, and a machine with no
        // ROM does not fail -- it boots to a black screen and sits there,
        // which is indistinguishable from the emulator being broken. The
        // recipes carry `romFile: current.romFile` precisely so this is the
        // one thing the caller must supply, and the first version of this
        // supplied nothing.
        if (settings.romFile.isEmpty) {
          AppLog.warn(
            'systems',
            'no Kickstart for ${known?.displayName ?? set.name}; '
                'it will not boot until one is present',
          );
        }
        // A WHDLoad pack needs its Kickstart plumbing before it can boot, and
        // that is not something a machine recipe can express.
        settings = await ZebWhdloadSupport.prepare(settings, index);
        try {
          final File file = await ConfigStore.save(settings, name);
          // Marked as generated, so Games can leave it out. Appended rather
          // than written into the config body: it is a comment, so the file
          // stays an ordinary .uae that opens and launches like any other.
          await file.writeAsString(
            '\n${ConfigStore.collectionStamp(ConfigStore.collectionRecipeVersion)}\n',
            mode: FileMode.append,
          );
          path = file.path;
          AppLog.info(
            'systems',
            'configured ${known?.displayName ?? set.name} '
                '(${known?.machineBlurb ?? 'default machine'})',
          );
        } on FileSystemException catch (e) {
          AppLog.warn('systems', 'could not configure $name: ${e.message}');
          continue;
        }
      }

      AppLog.info(
        'systems',
        '${known?.displayName ?? set.name}: '
            '${set.directoryMount ? 'folder' : 'boot ${set.bootDrive.split('/').last}'}'
            ', mounts ${set.allMounts.length}',
      );
      systems.add(
        AmigaSystem(
          name: known?.displayName ?? set.name,
          set: set,
          collection: known,
          configPath: path,
        ),
      );
    }
    return systems;
  }
}
