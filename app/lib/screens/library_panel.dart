import 'package:flutter/material.dart';

import '../data/file_category.dart';
import '../data/emulator_settings.dart';
import '../data/media_library.dart';
import '../theme/amiga_theme.dart';
import '../widgets/media_card.dart';
import 'guided_config_screen.dart';

/// Everything the scan found, split by what it is.
///
/// The tabs are the media types the core actually loads, not a curated subset:
/// floppies, hard drives, WHDLoad archives, CD images. They are pills across
/// the top rather than rail entries because the rail is for places, and these
/// are filters on one place - and because a count next to each is the fastest
/// way to see that a scan worked.
class LibraryPanel extends StatefulWidget {
  const LibraryPanel({super.key});

  @override
  State<LibraryPanel> createState() => _LibraryPanelState();
}

class _LibraryPanelState extends State<LibraryPanel> {
  /// Which categories get a tab, in order.
  ///
  /// Kickstarts are here even though a ROM is not something you launch: which
  /// ones you have decides which machines you can set up at all, and an A1200
  /// or a CD32 needs a different ROM from an A500. Tapping one starts a setup
  /// with that ROM already chosen.
  ///
  /// Music is not here - it has its own panel with a player.
  static const List<FileCategory> _tabs = <FileCategory>[
    FileCategory.floppies,
    FileCategory.whdloadGames,
    FileCategory.hardDrives,
    FileCategory.cdImages,
    FileCategory.roms,
    FileCategory.archives,
  ];

  /// null means "All".
  FileCategory? _selected;
  String _search = '';

  bool _loading = true;
  String? _error;
  List<MediaFile> _files = <MediaFile>[];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool rescan = false}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // The cached index is what makes opening this panel instant; a rescan is
      // an explicit act, from the button. An empty cache means the scan never
      // ran, so fall through to one rather than showing a bare panel.
      MediaIndex index =
          rescan ? await MediaLibrary.scan() : await MediaLibrary.cached();
      if (!rescan && index.files.isEmpty) {
        index = await MediaLibrary.scan();
      }
      if (!mounted) return;
      setState(() {
        _files = index.files;
        _loading = false;
      });
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  int _countOf(FileCategory category) =>
      _files.where((MediaFile f) => f.category == category).length;

  List<MediaFile> get _visible {
    final String needle = _search.trim().toLowerCase();
    return _files.where((MediaFile file) {
      // Music has its own panel, so it never appears here.
      if (file.category == FileCategory.music) return false;
      // Archives only on their own tab. A zip is not Amiga media until
      // something opens it, and a device with a few thousand zips of other
      // machines' games - which is normal on a handheld - buries the disks
      // that are.
      if (file.category == FileCategory.archives &&
          _selected != FileCategory.archives) {
        return false;
      }
      // Kickstarts are shown only on their own tab: mixed into "All" they
      // would bury the games, and they are not games.
      if (file.category == FileCategory.roms && _selected != FileCategory.roms) {
        return false;
      }
      if (_selected != null && file.category != _selected) return false;
      if (needle.isEmpty) return true;
      return file.name.toLowerCase().contains(needle);
    }).toList()
      ..sort((MediaFile a, MediaFile b) =>
          a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _tabRow(),
        _searchRow(),
        const Divider(height: 1, color: AmigaColors.panelBorder),
        Expanded(child: _body()),
      ],
    );
  }

  Widget _tabRow() {
    // Total excludes Kickstarts for the same reason the grid does.
    // Matches what "All" actually shows, which is Amiga media only.
    final int total = _files
        .where((MediaFile f) =>
            f.category != FileCategory.roms &&
            f.category != FileCategory.music &&
            f.category != FileCategory.archives)
        .length;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 4),
      child: Row(
        children: <Widget>[
          _TabPill(
            label: 'All',
            count: total,
            selected: _selected == null,
            onTap: () => setState(() => _selected = null),
          ),
          for (final FileCategory category in _tabs)
            _TabPill(
              label: category.displayName,
              count: _countOf(category),
              selected: _selected == category,
              onTap: () => setState(() => _selected = category),
            ),
        ],
      ),
    );
  }

  Widget _searchRow() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
      child: Row(
        children: <Widget>[
          Expanded(
            child: SizedBox(
              height: 38,
              child: TextField(
                onChanged: (String value) => setState(() => _search = value),
                style: const TextStyle(fontSize: 14),
                decoration: const InputDecoration(
                  isDense: true,
                  prefixIcon: Icon(Icons.search, size: 18),
                  hintText: 'Search',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            tooltip: 'Scan again',
            onPressed: _loading ? null : () => _load(rescan: true),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
    );
  }

  Widget _body() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return _Message(
        icon: Icons.error_outline,
        title: 'The scan failed',
        detail: _error!,
      );
    }

    final List<MediaFile> visible = _visible;
    if (visible.isEmpty) {
      return _Message(
        icon: Icons.folder_off_outlined,
        title: _search.isEmpty ? 'Nothing here yet' : 'No match',
        detail: _search.isEmpty
            ? 'Scan again once there are disk images on the device.'
            : 'Nothing matches "$_search".',
      );
    }

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final int columns =
            (constraints.maxWidth / AmigaMetrics.cardCell).floor().clamp(2, 100);
        return GridView.builder(
          padding: const EdgeInsets.all(10),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            childAspectRatio: AmigaMetrics.cardWidth / AmigaMetrics.cardHeight,
            crossAxisSpacing: 6,
            mainAxisSpacing: 6,
          ),
          itemCount: visible.length,
          itemBuilder: (BuildContext context, int i) => MediaCard(
            file: visible[i],
            onTap: () => _launch(visible[i]),
          ),
        );
      },
    );
  }

  /// Tapping a game opens the wizard with that media already in place, rather
  /// than booting blind: the file alone does not say which machine it wants,
  /// and getting that wrong is the difference between a game running and a
  /// black screen. The wizard starts on the machine step because the one thing
  /// the tap did settle is the media.
  Future<void> _launch(MediaFile file) async {
    final WizardMode mode = _modeFor(file.category);
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => GuidedConfigScreen(
          mode: mode,
          initialSettings: _settingsFor(file),
          initialName: file.title,
        ),
      ),
    );
    if (mounted) _load();
  }

  static WizardMode _modeFor(FileCategory category) {
    switch (category) {
      case FileCategory.floppies:
        return WizardMode.floppy;
      case FileCategory.whdloadGames:
        return WizardMode.whdload;
      case FileCategory.hardDrives:
        return WizardMode.hardDrive;
      case FileCategory.cdImages:
        return WizardMode.cd;
      case FileCategory.archives:
      case FileCategory.roms:
      case FileCategory.music:
        return WizardMode.custom;
    }
  }

  /// Puts the file in the drive its type belongs in. An archive could be any
  /// of them, so it goes nowhere and the wizard asks.
  static EmulatorSettings _settingsFor(MediaFile file) {
    const EmulatorSettings base = EmulatorSettings();
    switch (file.category) {
      case FileCategory.floppies:
        return base.copyWith(floppy0: file.path);
      case FileCategory.cdImages:
        return base.copyWith(cdImage: file.path);
      case FileCategory.hardDrives:
      case FileCategory.whdloadGames:
        return base.copyWith(hardDrives: <String>[file.path]);
      case FileCategory.roms:
        return base.copyWith(romFile: file.path);
      case FileCategory.archives:
      case FileCategory.music:
        return base;
    }
  }
}

class _TabPill extends StatelessWidget {
  const _TabPill({
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: Material(
        color: selected ? AmigaColors.workbenchBlue : AmigaColors.card,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: <Widget>[
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: selected ? Colors.white : AmigaColors.text,
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: selected
                        ? Colors.white.withValues(alpha: 0.22)
                        : Colors.white.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Text(
                    '$count',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: selected ? Colors.white : AmigaColors.textDim,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({
    required this.icon,
    required this.title,
    required this.detail,
  });

  final IconData icon;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 40, color: AmigaColors.textDim),
            const SizedBox(height: 12),
            Text(
              title,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AmigaColors.text,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              detail,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AmigaColors.textDim),
            ),
          ],
        ),
      ),
    );
  }
}
