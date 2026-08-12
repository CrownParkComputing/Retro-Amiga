import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

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
  bool _scanning = false;
  bool _loaded = false;
  String? _notice;

  @override
  void initState() {
    super.initState();
    _loadCached();
  }

  Future<void> _loadCached() async {
    final MediaIndex index = await MediaLibrary.cached();
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
    } on Exception catch (e) {
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
    final List<MediaFile> files = _index.of(widget.category);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
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
            TextButton.icon(
              onPressed: _scanning ? null : _rescan,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Rescan'),
            ),
            TextButton.icon(
              onPressed: _browse,
              icon: const Icon(Icons.folder_open, size: 18),
              label: const Text('Browse'),
            ),
          ],
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
              : ListView.builder(
                  itemCount: files.length,
                  itemBuilder: (BuildContext context, int i) {
                    final MediaFile file = files[i];
                    final bool isSelected = file.path == widget.selected;
                    return ListTile(
                      selected: isSelected,
                      leading: Icon(
                        isSelected
                            ? Icons.radio_button_checked
                            : Icons.radio_button_unchecked,
                      ),
                      title: Text(file.name),
                      subtitle: Text('${file.folder} · ${_size(file.size)}'),
                      onTap: () => widget.onSelected(file.path),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
