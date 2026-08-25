import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'amiga_model.dart';
import 'app_log.dart';
import 'app_prefs.dart';
import 'compliance_demo.dart';
import 'file_category.dart';
import 'host_paths.dart';
import 'media_root.dart';
import '../widgets/alphabet_filter.dart';

/// One file the scan found.
class MediaFile {
  MediaFile({required this.path, required this.category, required this.size})
    : name = _basename(path),
      title = _titleOf(_basename(path)) {
    // Held rather than derived on demand, because the shelf's filter compares
    // against it once per file per keystroke and `toLowerCase` allocates. On
    // a device holding a few thousand files that was several megabytes of
    // string churn per typed character.
    titleLower = title.toLowerCase();
    initial = AlphabetFilter.initialOf(title);
  }

  final String path;
  final FileCategory category;
  final int size;

  /// The file's own name, extension and all.
  final String name;

  /// The name without its extension, which is what a setup should be called:
  /// "Lotus Turbo Challenge", not "Lotus Turbo Challenge.adf".
  final String title;

  /// [title] folded for comparison, and the letter it files under. Both are
  /// worked out once here rather than per build; see the constructor.
  late final String titleLower;
  late final String initial;

  /// Compiled once for the whole class.
  ///
  /// These were `RegExp(r'[/\\]')` written inline in four getters, so every
  /// read of a name or a folder compiled a pattern -- and a list row reads
  /// three of them. A separator does not need a regular expression at all,
  /// but while there is one it should be built once.
  static final RegExp _separator = RegExp(r'[/\\]');

  static String _basename(String path) {
    final int slash = path.lastIndexOf(_separator);
    return slash < 0 ? path : path.substring(slash + 1);
  }

  static String _titleOf(String base) {
    // Amiga names put the type first - mod.axel_f - so the title is what
    // follows the prefix, not what precedes the last dot. Stripping the
    // extension the usual way would leave every module called "mod".
    final String lower = base.toLowerCase();
    for (final String prefix in const <String>['mod.', 'med.']) {
      if (lower.startsWith(prefix) && base.length > prefix.length) {
        return base.substring(prefix.length);
      }
    }

    final int dot = base.lastIndexOf('.');
    return dot <= 0 ? base : base.substring(0, dot);
  }

  /// The full path of the directory holding it.
  String get directory {
    final int slash = path.lastIndexOf(_separator);
    return slash <= 0 ? '' : path.substring(0, slash);
  }

  /// The folder it sits in, shown to tell two files of the same name apart.
  String get folder {
    final int slash = path.lastIndexOf(_separator);
    if (slash <= 0) return '';
    final String dir = path.substring(0, slash);
    final int parent = dir.lastIndexOf(_separator);
    return parent < 0 ? dir : dir.substring(parent + 1);
  }

  Map<String, Object> toJson() => <String, Object>{
    'path': path,
    'category': category.name,
    'size': size,
  };

  static MediaFile? fromJson(Map<String, Object?> json) {
    final String? path = json['path'] as String?;
    final String? categoryName = json['category'] as String?;
    if (path == null || categoryName == null) return null;
    final FileCategory? category = FileCategory.values
        .cast<FileCategory?>()
        .firstWhere(
          (FileCategory? c) => c?.name == categoryName,
          orElse: () => null,
        );
    if (category == null) return null;
    return MediaFile(
      path: path,
      category: category,
      size: (json['size'] as num?)?.toInt() ?? 0,
    );
  }
}

/// The result of a scan, grouped so a wizard step can ask for one category.
class MediaIndex {
  const MediaIndex({required this.roots, required this.files});

  const MediaIndex.empty()
    : roots = const <String>[],
      files = const <MediaFile>[];

  final List<String> roots;
  final List<MediaFile> files;

  /// Only files of that kind. Archives are never offered.
  ///
  /// They used to be, on the reasoning that only a zip's contents say what it
  /// holds. On a real device that reasoning collapses: this handheld has 1800
  /// zips of Spectrum and C64 games, so "pick a WHDLoad archive" listed 1849
  /// entries of which 49 were WHDLoad archives. A zip is not Amiga media until
  /// something opens it, and nothing here opens it.
  List<MediaFile> of(FileCategory category) {
    return files.where((MediaFile f) => f.category == category).toList();
  }

  int countOf(FileCategory category) =>
      files.where((MediaFile f) => f.category == category).length;

  bool get isEmpty => files.isEmpty;
}

/// Picks the ROMs a machine needs out of what the scan found.
///
/// A CD console needs two: its own Kickstart and an extended ROM holding the
/// CD firmware. Amiberry will not boot one without both, and it does not
/// complain - it starts and shows nothing, which is what "CD32 does not boot"
/// looks like from outside.
///
/// Matching is on the filename, because that is what ROM sets carry: TOSEC
/// names them "Kickstart v3.1 r40.060 (1993-05)(Commodore)(CD32)[!].rom" and
/// "CD32 Extended-ROM r40.60 (1993)(Commodore)(CD32).rom", and both say what
/// they are.
class RomPicker {
  const RomPicker._();

  static bool _isExtended(String name) {
    final String lower = name.toLowerCase();
    return lower.contains('ext');
  }

  static bool _mentions(String name, List<String> needles) {
    final String lower = name.toLowerCase();
    return needles.any(lower.contains);
  }

  /// The main Kickstart for [model], or null.
  ///
  /// [preferAros] forces the bundled AROS ROM. That is compliance mode, and
  /// it must be a hard preference rather than a nudge: the point of the mode
  /// is that the machine demonstrably runs on a ROM nobody had to supply, so
  /// quietly picking up a Kickstart the user happens to have imported would
  /// defeat it -- and would do so invisibly, since both boot.
  static MediaFile? kickstartFor(
    AmigaModel model,
    List<MediaFile> roms, {
    bool preferAros = false,
  }) {
    final List<MediaFile> candidates = roms
        .where((MediaFile r) => !_isExtended(r.name))
        .toList();
    if (candidates.isEmpty) return null;

    if (preferAros) {
      for (final MediaFile rom in candidates) {
        if (rom.name.toLowerCase() == 'aros-rom.bin') return rom;
      }
      // No AROS present is a real problem in this mode, and returning some
      // other ROM would hide it behind a machine that boots.
      return null;
    }

    final List<String> wanted = switch (model) {
      AmigaModel.cd32 => <String>['cd32'],
      AmigaModel.cdtv => <String>['cdtv'],
      AmigaModel.a1200 => <String>['a1200', '40.068'],
      AmigaModel.a4000 => <String>['a4000', '40.068'],
      AmigaModel.a600 => <String>['a600', '37.300', '40.063'],
      AmigaModel.a500Plus => <String>['a500+', '37.', '2.04'],
      _ => <String>['1.3', '34.005', 'a500'],
    };

    for (final String needle in wanted) {
      for (final MediaFile rom in candidates) {
        if (_mentions(rom.name, <String>[needle])) return rom;
      }
    }
    return candidates.first;
  }

  /// The extended ROM for [model], or null when it needs none.
  static MediaFile? extendedRomFor(
    AmigaModel model,
    List<MediaFile> roms, {
    bool preferAros = false,
  }) {
    if (preferAros) {
      for (final MediaFile rom in roms) {
        if (rom.name.toLowerCase() == 'aros-ext.bin') return rom;
      }
      return null;
    }
    if (!model.needsExtendedRom) return null;
    final String machine = model == AmigaModel.cd32 ? 'cd32' : 'cdtv';
    for (final MediaFile rom in roms) {
      if (_isExtended(rom.name) && _mentions(rom.name, <String>[machine])) {
        return rom;
      }
    }
    // An extended ROM with no machine in its name is still better than none.
    for (final MediaFile rom in roms) {
      if (_isExtended(rom.name)) return rom;
    }
    return null;
  }
}

/// Finds Amiga media by walking folders, rather than making the user pick
/// files one at a time.
///
/// A picker returns a single file and no context. A scan is what lets the
/// wizard offer "here are your seven Kickstarts, which one" - which is how the
/// launcher this replaces behaved, and what the browser-based first pass got
/// wrong.
class MediaLibrary {
  const MediaLibrary._();

  static const String _indexFile = 'media_index.json';

  /// A scan is the commit point for media changes. Screens subscribe here so
  /// renaming or deleting a file in Files immediately updates Music,
  /// Workbench counts and Settings without each panel inventing its own cache.
  static final StreamController<MediaIndex> _changes =
      StreamController<MediaIndex>.broadcast();

  static Stream<MediaIndex> get changes => _changes.stream;

  /// Directories worth trying before the user points anywhere. Android keeps
  /// shared storage under /sdcard; iOS has only the app's own Documents, which
  /// is where files dropped in through the Files app land.
  static Future<List<String>> defaultRoots() async {
    // Compliance mode looks in ONE folder, and it is not the user's.
    //
    // Everything the demo runs on -- the AROS ROMs and the demo disk -- is
    // written into that folder, so this is the whole search path while the
    // mode is on. It is what makes the mode's claim true rather than merely
    // stated: the library cannot list the user's games because it is not
    // looking at them, and the ROM picker cannot reach their Kickstart
    // because it is not in the path. Filtering results afterwards would have
    // left both one missed code path away from being wrong.
    if (await AppPrefs.complianceMode()) {
      return <String>[(await ComplianceDemo.folder()).path];
    }
    if (Platform.isAndroid) {
      // The app's own media root, not the whole of /sdcard. Scoped storage
      // will not let this app list shared storage at all, so walking /sdcard
      // returns nothing but a permission error per folder. What the user has
      // elsewhere reaches the library through the folder picker instead: see
      // MediaFolder.
      return <String>[await MediaRoot.path()];
    }
    if (Platform.isIOS) {
      return <String>[await HostPaths.documents()];
    }
    // The app's own folder and Documents, not the whole of home. A desktop
    // home directory holds every other emulator on the machine, and walking
    // it turns their libraries into this one's.
    final String root = await MediaRoot.path();
    final String documents = await HostPaths.documents();
    final String home = Platform.environment['HOME'] ?? '';
    return <String>[
      root,
      // Documents, but never home itself. A home directory is every project
      // and every other emulator on the machine, and walking it is how qemu's
      // boot floppies and a PS2 disc ended up in an Amiga library.
      if (documents != root &&
          documents != home &&
          Directory(documents).existsSync())
        documents,
    ];
  }

  /// Folders never worth walking wherever they appear: caches and other
  /// apps' data. Skipping them turns a minute-long scan into a few seconds.
  static const List<String> _skipAnywhere = <String>[
    '/android/data',
    '/android/obb',
    '/.thumbnails',
    '/.trash',
  ];

  /// The phone's own media folders, skipped only at the top of a scan root.
  ///
  /// Matched by name at depth 1, not anywhere in the path: matching anywhere
  /// meant the media folder's own Music directory - /sdcard/UAE4Arm/Music -
  /// was skipped along with /sdcard/Music, so a collection of modules filed
  /// exactly where the app puts them was invisible to the app.
  static const List<String> _skipAtRoot = <String>[
    'dcim',
    'pictures',
    'movies',
    'music',
    'whatsapp',
  ];

  /// Directories that hold copies of things rather than things.
  ///
  /// A desktop scan walks source trees, and a build directory is the same
  /// files again: this machine's home held five copies of one tune, in
  /// assets/, build/flutter_assets/ and build/unit_test_assets/. Matched as a
  /// whole path element so a game called "Target" is not skipped for being
  /// spelt like a Rust build folder.
  static const List<String> _skipDirectories = <String>[
    'build',
    'out',
    'target',
    'node_modules',
    '.git',
    '.dart_tool',
    '.gradle',
    '.cache',
    // The canonical reference-zip store in Documents. Never scanned, never
    // imported: adopting it would relocate the masters into this app's
    // library, and on a desktop that is one user-dirs edit away.
    'retro-zips',
  ];

  static bool _shouldSkip(
    String path, {
    required bool atRoot,
    required String mediaRoot,
  }) {
    // Nothing inside the media folder is ever skipped. Everything there is
    // there because the user or the import put it there, and the phone-media
    // names below would otherwise eat the app's own Music directory - which
    // is exactly what happened on the desktop, where the media folder is
    // itself a scan root and its Music sits one level down.
    if (mediaRoot.isNotEmpty && path.startsWith('$mediaRoot/')) return false;
    final String lower = path.toLowerCase();
    if (_skipAnywhere.any(lower.contains)) return true;
    final int lastSlash = lower.lastIndexOf('/');
    final String element = lastSlash < 0
        ? lower
        : lower.substring(lastSlash + 1);
    if (_skipDirectories.contains(element)) return true;
    if (!atRoot) return false;
    final int slash = lower.lastIndexOf('/');
    final String name = slash < 0 ? lower : lower.substring(slash + 1);
    return _skipAtRoot.contains(name);
  }

  /// Walks [roots] and returns everything recognisable.
  ///
  /// The walk runs in its own isolate. It is deliberately synchronous inside
  /// there - listSync is far quicker than the async variant for a deep tree -
  /// and on the UI isolate that combination freezes the app mid-scan, which
  /// looks exactly like a spinner that never stops.
  ///
  /// [maxDepth] keeps a stray symlink or a deep collection from turning this
  /// into a full-disk crawl. Unreadable directories are skipped rather than
  /// aborting the scan: on Android plenty of them are unreadable by design.
  static Future<MediaIndex> scan({
    List<String>? roots,
    int maxDepth = 6,
    int fileLimit = 5000,
  }) async {
    final List<String> scanRoots = roots ?? await defaultRoots();
    // Archives are only worth indexing inside the media folder - see _walk.
    final String mediaRoot = await MediaRoot.path();

    // Only sendable values cross the isolate boundary, so the walk returns
    // plain maps and they are turned back into MediaFiles here.
    final List<Map<String, Object>> raw = await Isolate.run(
      () => _walk(scanRoots, maxDepth, fileLimit, mediaRoot),
    );

    final List<MediaFile> found = <MediaFile>[];
    for (final Map<String, Object> entry in raw) {
      final MediaFile? file = MediaFile.fromJson(entry);
      if (file != null) found.add(file);
    }

    found.sort(
      (MediaFile a, MediaFile b) =>
          a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    );

    final MediaIndex index = MediaIndex(roots: scanRoots, files: found);
    AppLog.info('scan', '${found.length} files under ${scanRoots.join(", ")}');
    await _persist(index);
    if (!_changes.isClosed) _changes.add(index);
    return index;
  }

  /// Whether a file categorised as a ROM is actually an Amiga Kickstart.
  ///
  /// Needed because `bin` is a Kickstart extension and also every other
  /// emulator's ROM extension: without this the ROM list on a shared device is
  /// mostly other machines' files. A Kickstart opens with the ROM identifier
  /// word - 0x1111 for 256K, 0x1114 for 512K, which is the word memory.cpp
  /// itself tests - followed by the 68k reset jump, 0x4EF9. Cloanto's encrypted
  /// ROMs carry a text header instead and are accepted on that, since the core
  /// decrypts them given a rom.key.
  static bool looksLikeKickstart(File file) {
    try {
      final RandomAccessFile handle = file.openSync();
      try {
        final List<int> head = handle.readSync(11);
        if (head.length < 4) return false;

        final int identifier = (head[0] << 8) | head[1];
        final int resetJump = (head[2] << 8) | head[3];
        if ((identifier == 0x1111 || identifier == 0x1114) &&
            resetJump == 0x4EF9) {
          return true;
        }

        // "AMIROMTYPE1", Cloanto's encrypted ROM header.
        const List<int> amiromtype1 = <int>[
          0x41,
          0x4D,
          0x49,
          0x52,
          0x4F,
          0x4D,
          0x54,
          0x59,
          0x50,
          0x45,
          0x31,
        ];
        if (head.length >= amiromtype1.length) {
          bool matched = true;
          for (int i = 0; i < amiromtype1.length; i++) {
            if (head[i] != amiromtype1[i]) {
              matched = false;
              break;
            }
          }
          if (matched) return true;
        }
        return false;
      } finally {
        handle.closeSync();
      }
    } on FileSystemException {
      return false;
    }
  }

  /// Extensions that belong to the Amiga and to half the other machines in
  /// the room. Everything not listed here - adf, hdf, lha, rom - names an
  /// Amiga file wherever it is found.
  static const Set<String> _ambiguous = <String>{
    'img',
    'st',
    'dsk',
    'ima',
    'bin',
    'iso',
    'chd',
    'cue',
    'ccd',
    'mds',
    'nrg',
    'vhd',
    'hdi',
  };

  static bool _isAmbiguousExtension(String path) {
    final int dot = path.lastIndexOf('.');
    if (dot < 0) return false;
    return _ambiguous.contains(path.substring(dot + 1).toLowerCase());
  }

  /// Whether this file is only music because of the Amiga's "mod.name" way
  /// round, rather than because of its extension.
  static bool _isPrefixNamed(String path) {
    final int slash = path.lastIndexOf('/');
    final String name = (slash < 0 ? path : path.substring(slash + 1))
        .toLowerCase();
    return name.startsWith('mod.') || name.startsWith('med.');
  }

  /// Suffixes that mean "this mod. is somebody's source file".
  static const Set<String> _codeSuffixes = <String>{
    'rs',
    'js',
    'ts',
    'py',
    'c',
    'h',
    'cc',
    'cpp',
    'hpp',
    'go',
    'rb',
    'php',
    'java',
    'kt',
    'dart',
    'swift',
    'sh',
    'md',
    'txt',
    'json',
    'yaml',
    'yml',
    'toml',
    'lock',
    'info',
    'html',
    'css',
    'xml',
    'cmake',
    'am',
    'in',
  };

  /// Whether a file named the Amiga way round - mod.axel_f - is really a tune.
  ///
  /// The magic at offset 1080 settles it when it is there, but it is not
  /// always: the fifteen-sample modules that came before M.K. have no tag at
  /// all, and Modland is full of them. So a file is also taken as a tune when
  /// it is big enough to be one and its suffix is not a programming language -
  /// which is what mod.rs, mod.js and mod.ts are, and they were being indexed
  /// as music.
  static bool isNamedModule(String path, int size) {
    final int dot = path.lastIndexOf('.');
    final String suffix = dot < 0 ? '' : path.substring(dot + 1).toLowerCase();
    if (_codeSuffixes.contains(suffix)) return false;
    if (size < 1084) return false;
    return true;
  }

  /// Whether a file is a tracker module.
  ///
  /// A ProTracker module names its format at offset 1080 - M.K. for the
  /// four-channel original, and a handful of others for the variants that
  /// followed. Anything shorter than that is not a module whatever it is
  /// called.
  static bool looksLikeModule(File file) {
    const List<String> tags = <String>[
      'M.K.',
      'M!K!',
      'M&K!',
      'FLT4',
      'FLT8',
      '4CHN',
      '6CHN',
      '8CHN',
      'CD81',
      'OKTA',
      '16CN',
      '32CN',
    ];
    try {
      final RandomAccessFile handle = file.openSync();
      try {
        if (handle.lengthSync() < 1084) return false;
        handle.setPositionSync(1080);
        final List<int> tag = handle.readSync(4);
        if (tag.length < 4) return false;
        final String text = String.fromCharCodes(tag);
        if (tags.contains(text)) return true;
        // OctaMED and the 15-sample originals say so at the very start
        // instead.
        handle.setPositionSync(0);
        final List<int> head = handle.readSync(4);
        return head.length == 4 && String.fromCharCodes(head) == 'MMD0' ||
            String.fromCharCodes(head) == 'MMD1';
      } finally {
        handle.closeSync();
      }
    } on FileSystemException {
      return false;
    }
  }

  /// Runs inside the scan isolate. Top-level work only: no plugins, no UI.
  static List<Map<String, Object>> _walk(
    List<String> roots,
    int maxDepth,
    int fileLimit,
    String mediaRoot,
  ) {
    final List<Map<String, Object>> found = <Map<String, Object>>[];
    // One entry per file. Roots can contain one another - the media folder
    // lives inside home on a desktop - and without this every file under the
    // inner one was indexed twice, which is why the counts read high.
    final Set<String> seen = <String>{};

    void walkDir(Directory dir, int depth) {
      if (depth > maxDepth || found.length >= fileLimit) return;
      List<FileSystemEntity> entries;
      try {
        entries = dir.listSync(followLinks: false);
      } on FileSystemException {
        return; // unreadable, which is normal and not worth reporting
      }
      for (final FileSystemEntity entry in entries) {
        if (found.length >= fileLimit) return;
        if (_shouldSkip(entry.path, atRoot: depth == 0, mediaRoot: mediaRoot)) {
          continue;
        }
        if (entry is Directory) {
          // AGS shared/game/save trees can contain tens of thousands of Amiga
          // files that are contents of a mounted drive, not library entries.
          // HDF images sit alongside them and are still indexed; skipping the
          // payload directories turns a minutes-long scan into seconds.
          final String lowerPath = entry.path.toLowerCase();
          final String hardDriveRoot = '$mediaRoot/harddrives/'.toLowerCase();
          final String directoryName = entry.path
              .replaceAll(r'\', '/')
              .split('/')
              .last
              .toLowerCase();
          if (lowerPath.startsWith(hardDriveRoot) &&
              const <String>{
                'shared',
                'share',
                'games',
                'game-data',
                'save-data',
                'savedata',
                'saves',
              }.contains(directoryName)) {
            continue;
          }
          walkDir(entry, depth + 1);
        } else if (entry is File) {
          FileCategory? category = FileCategory.fromPath(entry.path);
          // A raw .img is usually a floppy, except when the user deliberately
          // placed it under HardDrives. Zeb's 16GB WHDLoad images use exactly
          // that extension and contain an RDB with several partitions.
          final String normalPath = entry.path.replaceAll(r'\', '/');
          final String normalHardDriveRoot = '$mediaRoot/HardDrives/'
              .replaceAll(r'\', '/');
          if (normalPath.toLowerCase().startsWith(
                normalHardDriveRoot.toLowerCase(),
              ) &&
              FileCategory.isHardDriveImage(entry.path, allowRawImage: true)) {
            category = FileCategory.hardDrives;
          }
          if (category == null) continue;

          // A zip is not Amiga media until something opens it, and a handheld
          // holds thousands of them for other machines: this device indexed
          // 1800 zips of Spectrum and C64 games against 115 Amiga files.
          // Inside the media folder they are worth keeping, because import
          // unpacks those and the WHDLoad boot archive lives there. Anywhere
          // else they are noise that slows every scan and every load of the
          // index.
          if (category == FileCategory.archives &&
              !entry.path.startsWith('$mediaRoot/')) {
            continue;
          }

          // Extensions the Amiga shares with everything else. A desktop is
          // full of them - qemu's .img and .st boot floppies, PS2 .chd discs,
          // a DOSBox .lha - and outside the media folder none of them is an
          // Amiga disk. Inside it they are, because that is where import puts
          // what the user said was Amiga media.
          if (_isAmbiguousExtension(entry.path) &&
              !entry.path.startsWith('$mediaRoot/')) {
            continue;
          }
          int size = 0;
          try {
            size = entry.lengthSync();
          } on FileSystemException {
            continue;
          }
          // Checked by content, because the name lies for both of these.
          if (category == FileCategory.roms && !looksLikeKickstart(entry)) {
            continue;
          }
          // "mod.name" is the Amiga's way round, and it is also how Rust
          // names a module: this scan indexed fifty mod.rs files, eleven
          // mod.js and nine mod.ts as tunes. A module says what it is at
          // offset 1080, so ask it.
          if (category == FileCategory.music &&
              _isPrefixNamed(entry.path) &&
              !isNamedModule(entry.path, size)) {
            continue;
          }
          if (!seen.add(entry.path)) continue;
          found.add(<String, Object>{
            'path': entry.path,
            'category': category.name,
            'size': size,
          });
        }
      }
    }

    // Shortest first, so an outer root is walked before anything nested in
    // it and the nested one then finds nothing left to add.
    final List<String> ordered = roots.toList()
      ..sort((String a, String b) => a.length.compareTo(b.length));
    for (final String root in ordered) {
      final Directory dir = Directory(root);
      if (dir.existsSync()) walkDir(dir, 0);
    }
    return found;
  }

  static Future<File> _indexPath() async {
    return File('${await HostPaths.appSupport()}/$_indexFile');
  }

  static Future<void> _persist(MediaIndex index) async {
    try {
      final File file = await _indexPath();
      file.writeAsStringSync(
        jsonEncode(<String, Object>{
          // Which mode wrote this. A cache written in one mode must not be
          // served in the other: the whole point of compliance mode is that
          // the user's files are not in the picture, and a stale index would
          // put them back on screen without anything having scanned them.
          'complianceMode': await AppPrefs.complianceMode(),
          'roots': index.roots,
          'files': index.files.map((MediaFile f) => f.toJson()).toList(),
        }),
      );
    } on Exception {
      // A lost cache costs a rescan, nothing more.
    }
  }

  /// The last scan, so the wizard opens instantly instead of walking storage
  /// again every time.
  static Future<MediaIndex> cached() async {
    try {
      final File file = await _indexPath();
      if (!file.existsSync()) return const MediaIndex.empty();
      final Object? json = jsonDecode(file.readAsStringSync());
      if (json is! Map<String, Object?>) return const MediaIndex.empty();
      // Written in the other mode: treat as no cache at all, which costs a
      // rescan and is the only answer that cannot show the wrong files.
      if ((json['complianceMode'] as bool? ?? false) !=
          await AppPrefs.complianceMode()) {
        return const MediaIndex.empty();
      }
      final List<Object?> rawFiles =
          (json['files'] as List<Object?>?) ?? const <Object?>[];
      final List<MediaFile> files = <MediaFile>[];
      for (final Object? raw in rawFiles) {
        if (raw is Map<String, Object?>) {
          final MediaFile? parsed = MediaFile.fromJson(raw);
          // Drop entries whose file has since gone.
          if (parsed != null && File(parsed.path).existsSync()) {
            files.add(parsed);
          }
        }
      }
      final List<String> roots =
          ((json['roots'] as List<Object?>?) ?? const <Object?>[])
              .whereType<String>()
              .toList();
      return MediaIndex(roots: roots, files: files);
    } on Exception {
      return const MediaIndex.empty();
    }
  }

  /// Renames a user-owned media file in place. The extension is not forced or
  /// rewritten: module names such as `mod.title` are meaningful on Amiga and
  /// must remain usable. Callers supply only a basename so a Files action can
  /// never move a file outside its scanned directory.
  static Future<MediaFile> rename(MediaFile file, String newName) async {
    final String name = newName.trim();
    if (name.isEmpty ||
        name == '.' ||
        name == '..' ||
        name.contains('/') ||
        name.contains('\\')) {
      throw const FormatException('Enter a file name without folders.');
    }
    final File source = File(file.path);
    if (!source.existsSync()) {
      throw FileSystemException('File not found', file.path);
    }
    final String targetPath = '${file.directory}/$name';
    if (targetPath != file.path && File(targetPath).existsSync()) {
      throw const FileSystemException('A file with that name already exists.');
    }
    final File target = await source.rename(targetPath);
    return MediaFile(
      path: target.path,
      category: file.category,
      size: target.lengthSync(),
    );
  }

  /// Deletes one user media file. The UI confirms before calling this method.
  static Future<void> delete(MediaFile file) async {
    final File target = File(file.path);
    if (target.existsSync()) await target.delete();
  }
}
