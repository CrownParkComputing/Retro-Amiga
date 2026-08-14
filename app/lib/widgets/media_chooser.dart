import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'alphabet_filter.dart';

import '../data/file_category.dart';
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
    if (!await MediaLibrary.hasScanPermission()) {
      final bool granted = await MediaLibrary.requestScanPermission();
      if (!granted) {
        if (mounted) {
          setState(
            () => _notice =
                'Without all-files access the app cannot scan folders. You can '
                'still choose files one at a time with Browse.',
          );
        }
        return;
      }
    }

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
    final List<String> initials =
        AlphabetFilter.from(all.map((MediaFile f) => f.name));
    // A filter that survives its own letter disappearing - a rescan can leave
    // a chosen letter with nothing behind it, and an empty list with no way
    // back reads as a broken screen.
    final String? initial = initials.contains(_initial) ? _initial : null;
    final List<MediaFile> files = initial == null
        ? all
        : all
            .where((MediaFile f) => AlphabetFilter.initialOf(f.name) == initial)
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
              IconButton(
                tooltip: 'Rescan',
                visualDensity: VisualDensity.compact,
                onPressed: _scanning ? null : _rescan,
                icon: const Icon(Icons.refresh, size: 20),
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
                    final int columns =
                        (constraints.maxWidth / 380).floor().clamp(1, 3);
                    // Kickstart names carry their identity in the tail -
                    // "(1993-12)(Commodore)(A1200)" - which is exactly what
                    // one ellipsized line cuts off. ROMs are a short list, so
                    // the taller two-line row costs nothing to scroll.
                    final bool tall = widget.category == FileCategory.roms;
                    return GridView.builder(
                      padding: EdgeInsets.zero,
                      gridDelegate:
                          SliverGridDelegateWithFixedCrossAxisCount(
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
