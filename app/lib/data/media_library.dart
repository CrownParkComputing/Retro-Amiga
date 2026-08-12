import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:path_provider/path_provider.dart';

import 'package:flutter/services.dart';

import 'file_category.dart';

/// One file the scan found.
class MediaFile {
  const MediaFile({
    required this.path,
    required this.category,
    required this.size,
  });

  final String path;
  final FileCategory category;
  final int size;

  String get name {
    final int slash = path.lastIndexOf(RegExp(r'[/\\]'));
    return slash < 0 ? path : path.substring(slash + 1);
  }

  /// The folder it sits in, shown to tell two files of the same name apart.
  String get folder {
    final int slash = path.lastIndexOf(RegExp(r'[/\\]'));
    if (slash <= 0) return '';
    final String dir = path.substring(0, slash);
    final int parent = dir.lastIndexOf(RegExp(r'[/\\]'));
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

  List<MediaFile> of(FileCategory category) {
    // Archives are offered alongside whatever was asked for: only a zip's
    // contents say what it holds, so hiding them would hide zipped disks.
    return files
        .where(
          (MediaFile f) =>
              f.category == category || f.category == FileCategory.archives,
        )
        .toList();
  }

  int countOf(FileCategory category) =>
      files.where((MediaFile f) => f.category == category).length;

  bool get isEmpty => files.isEmpty;
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

  /// Directories worth trying before the user points anywhere. Android keeps
  /// shared storage under /sdcard; iOS has only the app's own Documents, which
  /// is where files dropped in through the Files app land.
  static Future<List<String>> defaultRoots() async {
    if (Platform.isAndroid) {
      return <String>['/sdcard'];
    }
    final Directory documents = await getApplicationDocumentsDirectory();
    return <String>[documents.path];
  }

  /// Asked of the host rather than a plugin: this is two Android calls, and
  /// permission_handler's Android module does not build against this AGP.
  static const MethodChannel _channel = MethodChannel('uae4arm2026/emulator');

  /// Whether a scan can actually read folders. On Android that needs all-files
  /// access, because scoped storage deliberately cannot enumerate.
  static Future<bool> hasScanPermission() async {
    if (!Platform.isAndroid) return true;
    try {
      return await _channel.invokeMethod<bool>('hasAllFilesAccess') ?? false;
    } on PlatformException {
      return false;
    }
  }

  /// Opens the system screen where all-files access is granted. There is no
  /// in-app dialog for this one, so this returns once the user is sent there
  /// rather than once they have decided.
  static Future<bool> requestScanPermission() async {
    if (!Platform.isAndroid) return true;
    try {
      return await _channel.invokeMethod<bool>('requestAllFilesAccess') ??
          false;
    } on PlatformException {
      return false;
    }
  }

  /// Folders never worth walking: caches, other apps' data, and the noisy
  /// media trees. Skipping them turns a minute-long scan into a few seconds.
  static const List<String> _skip = <String>[
    '/Android/data',
    '/Android/obb',
    '/DCIM',
    '/Pictures',
    '/Movies',
    '/Music',
    '/WhatsApp',
    '/.thumbnails',
    '/.trash',
  ];

  static bool _shouldSkip(String path) {
    final String lower = path.toLowerCase();
    return _skip.any((String s) => lower.contains(s.toLowerCase()));
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

    // Only sendable values cross the isolate boundary, so the walk returns
    // plain maps and they are turned back into MediaFiles here.
    final List<Map<String, Object>> raw = await Isolate.run(
      () => _walk(scanRoots, maxDepth, fileLimit),
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
    await _persist(index);
    return index;
  }

  /// Runs inside the scan isolate. Top-level work only: no plugins, no UI.
  static List<Map<String, Object>> _walk(
    List<String> roots,
    int maxDepth,
    int fileLimit,
  ) {
    final List<Map<String, Object>> found = <Map<String, Object>>[];

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
        if (_shouldSkip(entry.path)) continue;
        if (entry is Directory) {
          walkDir(entry, depth + 1);
        } else if (entry is File) {
          final FileCategory? category = FileCategory.fromPath(entry.path);
          if (category == null) continue;
          int size = 0;
          try {
            size = entry.lengthSync();
          } on FileSystemException {
            continue;
          }
          found.add(<String, Object>{
            'path': entry.path,
            'category': category.name,
            'size': size,
          });
        }
      }
    }

    for (final String root in roots) {
      final Directory dir = Directory(root);
      if (dir.existsSync()) walkDir(dir, 0);
    }
    return found;
  }

  static Future<File> _indexPath() async {
    final Directory base = await getApplicationSupportDirectory();
    return File('${base.path}/$_indexFile');
  }

  static Future<void> _persist(MediaIndex index) async {
    try {
      final File file = await _indexPath();
      file.writeAsStringSync(
        jsonEncode(<String, Object>{
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
}
