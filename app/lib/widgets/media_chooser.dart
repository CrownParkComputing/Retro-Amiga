import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'alphabet_filter.dart';

import '../data/file_category.dart';
import '../data/media_folder.dart';
import '../data/media_root.dart';
import '../data/media_library.dart';

/// Offers what a scan found, rather than making the user go and find it.
///
/// The list is the point: a picker hands back one file with no context, so it
/// cannot tell you that you have three Kickstarts and which is which. Browsing
/// stays available underneath for anything outside the scanned folders.
class MediaChooser extends StatefulWidget {
  const MediaChooser({
    super.key,
    required this.category,
    required this.selected,
    required this.onSelected,
    this.emptyHint,
  });

  final FileCategory category;
  final String selected;
  final ValueChanged<String> onSelected;

  /// Shown when the scan found nothing of this kind.
  final String? emptyHint;

  @override
  State<MediaChooser> createState() => _MediaChooserState();
}

class _MediaChooserState extends State<MediaChooser> {
  MediaIndex _index = const MediaIndex.empty();
  String? _initial;
  bool _scanning = false;
  bool _loaded = false;
  String? _notice;

  @override
  void initState() {
    super.initState();
    _loadCached();
  }

  Future<void> _loadCached() async {
    MediaIndex index = const MediaIndex.empty();
    try {
      index = await MediaLibrary.cached();
    } on Object catch (e) {
      // Catching Object, not Exception: an Error here would otherwise leave
      // _loaded false and the spinner up for ever.
      if (mounted) {
        setState(() => _notice = 'Could not read the media index: $e');
      }
    }
    if (!mounted) return;
    setState(() {
      _index = index;
      _loaded = true;
    });
    // First run has nothing cached, so scan straight away rather than showing
    // an empty list the user has to work out how to fill.
    if (index.isEmpty) await _rescan();
  }

  Future<void> _rescan() async {
    // No permission gate: the library root is the app's own folder, which is
    // readable on every Android without asking for anything. A collection
    // somewhere else arrives through _importFolder.
    setState(() {
      _scanning = true;
      _notice = null;
    });
    try {
      final MediaIndex index = await MediaLibrary.scan();
      if (mounted) {
        setState(() {
          _index = index;
          _scanning = false;
          _notice = index.isEmpty
              ? 'Nothing found in the scanned folders.'
              : null;
        });
      }
    } on Object catch (e) {
      if (mounted) {
        setState(() {
          _scanning = false;
          _notice = 'Scan failed: $e';
        });
      }
    }
  }

  /// Points the library at a folder the user picks, and copies what it holds.
  ///
  /// The system picker rather than a path: scoped storage will not let this
  /// app open /sdcard/Amiga by name, but it will honour a folder the user
  /// hands over, and that grant survives restarts. Copied rather than read in
  /// place because the emulator core opens files with POSIX calls and cannot
  /// be given a document URI.
  Future<void> _importFolder() async {
    if (!MediaFolder.isSupported) return;

    // Always ask, even when a folder is already granted: picking the wrong
    // one is easy, and a button that silently reuses the previous choice
    // leaves no way to correct it. The system picker opens where it left off,
    // so re-confirming the same folder is two taps.
    final String? picked = await MediaFolder.pick();
    if (picked == null) return; // Backed out: not an error.

    setState(() {
      _scanning = true;
      _notice = 'Reading the folder…';
    });
    try {
      final ImportResult result = await MediaFolderImporter.importAll(
        onProgress: (int done, int total) {
          if (mounted && total > 0) {
            setState(() => _notice = 'Copying $done of $total…');
          }
        },
      );
      if (!mounted) return;
      setState(
        () => _notice = result.total == 0
            ? 'Nothing the app recognises in that folder.'
            : '${result.moved} copied, ${result.alreadyInPlace} already here'
                  '${result.failed > 0 ? ', ${result.failed} failed' : ''}.',
      );
    } on Exception catch (e) {
      if (mounted) setState(() => _notice = 'Import failed: $e');
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
    await _rescan();
  }

  Future<void> _browse() async {
    try {
      final FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        allowMultiple: false,
      );
      final String? path = result?.files.single.path;
      if (path != null) widget.onSelected(path);
    } on Exception catch (e) {
      if (mounted) setState(() => _notice = 'Could not open the picker: $e');
    }
  }

  String _size(int bytes) {
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / 1024).round()} KB';
  }

  @override
  Widget build(BuildContext context) {
    final List<MediaFile> all = _index.of(widget.category);
    final List<String> initials = AlphabetFilter.from(
      all.map((MediaFile f) => f.name),
    );
    // A filter that survives its own letter disappearing - a rescan can leave
    // a chosen letter with nothing behind it, and an empty list with no way
    // back reads as a broken screen.
    final String? initial = initials.contains(_initial) ? _initial : null;
    final List<MediaFile> files = initial == null
        ? all
        : all
              .where(
                (MediaFile f) => AlphabetFilter.initialOf(f.name) == initial,
              )
              .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        // One line, not a toolbar: every row this takes is a disk you cannot
        // see, and picking a disk is the entire job of this screen.
        SizedBox(
          height: 32,
          child: Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  _scanning
                      ? 'Scanning…'
                      : files.isEmpty
                      ? 'Nothing found'
                      : '${files.length} found',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              // No rescan on Android. Scoped storage limits a scan to the
              // app's own folder, so the button could only ever re-list what
              // the last import copied - it looks like a way to find media and
              // is not one. Importing a folder re-indexes on its way out.
              if (!MediaFolder.isSupported)
                IconButton(
                  tooltip: 'Rescan',
                  visualDensity: VisualDensity.compact,
                  onPressed: _scanning ? null : _rescan,
                  icon: const Icon(Icons.refresh, size: 20),
                ),
              if (MediaFolder.isSupported)
                IconButton(
                  tooltip: 'Import a folder',
                  visualDensity: VisualDensity.compact,
                  onPressed: _scanning ? null : _importFolder,
                  icon: const Icon(Icons.drive_folder_upload, size: 20),
                ),
              IconButton(
                tooltip: 'Browse',
                visualDensity: VisualDensity.compact,
                onPressed: _browse,
                icon: const Icon(Icons.folder_open, size: 20),
              ),
            ],
          ),
        ),
        if (_notice != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              _notice!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        if (_scanning) const LinearProgressIndicator(),
        AlphabetFilter(
          initials: initials,
          selected: initial,
          onSelected: (String? value) => setState(() => _initial = value),
        ),
        const SizedBox(height: 4),
        Expanded(
          child: !_loaded
              ? const Center(child: CircularProgressIndicator())
              : files.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      widget.emptyHint ??
                          'No ${widget.category.displayName.toLowerCase()} '
                              'found. Put some on the device and rescan, or '
                              'use Browse.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              // Columns on a wide screen. A landscape handheld is mostly
              // width, and a single column of tall rows shows five disks out
              // of a hundred - so the screen gets used across, not just down.
              : LayoutBuilder(
                  builder: (BuildContext context, BoxConstraints constraints) {
                    final int columns = (constraints.maxWidth / 380)
                        .floor()
                        .clamp(1, 3);
                    // Kickstart names carry their identity in the tail -
                    // "(1993-12)(Commodore)(A1200)" - which is exactly what
                    // one ellipsized line cuts off. ROMs are a short list, so
                    // the taller two-line row costs nothing to scroll.
                    final bool tall = widget.category == FileCategory.roms;
                    return GridView.builder(
                      padding: EdgeInsets.zero,
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: columns,
                        mainAxisExtent: tall ? 62 : 46,
                        crossAxisSpacing: 8,
                        mainAxisSpacing: 4,
                      ),
                      itemCount: files.length,
                      itemBuilder: (BuildContext context, int i) {
                        final MediaFile file = files[i];
                        final bool isSelected = file.path == widget.selected;
                        return _FileRow(
                          file: file,
                          size: _size(file.size),
                          selected: isSelected,
                          lines: tall ? 2 : 1,
                          onTap: () => widget.onSelected(file.path),
                        );
                      },
                    );
                  },
                ),
        ),
      ],
    );
  }
}

/// One file, one line: the name that identifies it, and the size to tell two
/// copies apart. The folder is the tooltip rather than a second line, because
/// a second line halves how many disks fit on the screen.
class _FileRow extends StatelessWidget {
  const _FileRow({
    required this.file,
    required this.size,
    required this.selected,
    required this.onTap,
    this.lines = 1,
  });

  final MediaFile file;
  final String size;
  final bool selected;
  final VoidCallback onTap;

  /// How many lines the name may take. ROM rows get two, because a Kickstart
  /// name ends in the part that distinguishes it.
  final int lines;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Material(
      color: selected
          ? theme.colorScheme.primaryContainer
          : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Tooltip(
          message: file.folder,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Row(
              children: <Widget>[
                Icon(
                  selected
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    file.name,
                    maxLines: lines,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  size,
                  style: theme.textTheme.bodySmall?.copyWith(fontSize: 11),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
