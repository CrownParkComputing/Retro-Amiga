import 'dart:async';

import 'package:flutter/material.dart';

import '../data/amiga_model.dart';
import '../data/app_prefs.dart';
import '../data/config_store.dart';
import '../data/emulator_settings.dart';
import '../data/file_category.dart';
import '../data/media_library.dart';
import '../data/music_player.dart';
import '../widgets/alphabet_filter.dart';
import '../emulator.dart';
import '../theme/amiga_theme.dart';
import 'guided_config_screen.dart';

/// Every Amiga file the scan found, listed by what it is.
///
/// A list rather than a wall of cards: these are files, and what tells them
/// apart is the name, where it came from and whether it is set up - three
/// things a row shows at a glance and a cover-art-shaped card with no cover
/// art does not.
///
/// Nothing here launches straight into the emulator. A game runs from a setup,
/// because the file alone does not say which machine, how much memory or which
/// Kickstart it wants, and guessing produces a black screen rather than an
/// error. So a file with a setup offers Play, and a file without offers Set up.
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
  /// or a CD32 needs a different ROM from an A500.
  ///
  /// Music is included here too: Music is the player, Files is the place to
  /// manage local files.
  static const List<FileCategory> _tabs = <FileCategory>[
    FileCategory.floppies,
    FileCategory.whdloadGames,
    FileCategory.hardDrives,
    FileCategory.cdImages,
    FileCategory.roms,
    FileCategory.music,
  ];

  /// null means "All".
  FileCategory? _selected;
  String _search = '';

  /// The chosen initial from the letter strip, or null for everything.
  String? _initial;

  bool _loading = true;
  String? _error;
  List<MediaFile> _files = <MediaFile>[];
  List<SavedConfig> _configs = <SavedConfig>[];
  StreamSubscription<MediaIndex>? _mediaChanges;

  @override
  void initState() {
    super.initState();
    _mediaChanges = MediaLibrary.changes.listen((MediaIndex index) {
      if (!mounted) return;
      setState(() => _files = index.files);
    });
    _load();
  }

  @override
  void dispose() {
    _mediaChanges?.cancel();
    super.dispose();
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
      MediaIndex index = rescan
          ? await MediaLibrary.scan()
          : await MediaLibrary.cached();
      if (!rescan && index.files.isEmpty) {
        index = await MediaLibrary.scan();
      }
      final List<SavedConfig> configs = await ConfigStore.list();
      if (!mounted) return;
      setState(() {
        _files = index.files;
        _configs = configs;
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

  /// The setup that already uses [file], if there is one.
  SavedConfig? _setupFor(MediaFile file) {
    for (final SavedConfig config in _configs) {
      if (config.uses(file.path)) return config;
    }
    return null;
  }

  int _countOf(FileCategory category) =>
      _files.where((MediaFile f) => f.category == category).length;

  /// The initials present in what the tabs and the search have left, so the
  /// strip only ever offers letters that lead somewhere.
  List<String> get _initials =>
      AlphabetFilter.from(_matching.map((MediaFile f) => f.title));

  List<MediaFile> get _visible {
    final String? initial = _initials.contains(_initial) ? _initial : null;
    final List<MediaFile> matching = _matching;
    if (initial == null) return matching;
    return matching
        .where((MediaFile f) => AlphabetFilter.initialOf(f.title) == initial)
        .toList();
  }

  /// Everything the tabs and the search box allow, before the letter strip.
  List<MediaFile> get _matching {
    final String needle = _search.trim().toLowerCase();
    return _files.where((MediaFile file) {
      // Archives are not listed at all. A zip is not Amiga media until
      // something opens it, and on a handheld the great majority are other
      // machines' games - 1800 of them here, against 115 Amiga files. They
      // are still offered inside the wizard, where the folder they sit in
      // says whether they belong.
      if (file.category == FileCategory.archives) return false;
      // Kickstarts appear only on their own tab: a ROM is not a game.
      if (file.category == FileCategory.roms &&
          _selected != FileCategory.roms) {
        return false;
      }
      if (_selected != null && file.category != _selected) return false;
      if (needle.isEmpty) return true;
      return file.name.toLowerCase().contains(needle);
    }).toList()..sort(
      (MediaFile a, MediaFile b) =>
          a.title.toLowerCase().compareTo(b.title.toLowerCase()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        // Letters first, as on the C64 shelf: the jump-to strip is the thing
        // you reach for most, so it sits at the top where it is easiest to hit.
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 2),
          child: AlphabetFilter(
            initials: _initials,
            selected: _initial,
            onSelected: (String? value) => setState(() => _initial = value),
          ),
        ),
        _tabRow(),
        _searchRow(),
        const Divider(height: 1, color: AmigaColors.panelBorder),
        Expanded(child: _body()),
      ],
    );
  }

  Widget _tabRow() {
    // Matches what "All" actually shows, which is Amiga media only.
    final int total = _files
        .where(
          (MediaFile f) =>
              f.category != FileCategory.roms &&
              f.category != FileCategory.archives,
        )
        .length;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(10, 4, 10, 4),
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

    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: visible.length,
      separatorBuilder: (BuildContext context, int index) =>
          const Divider(height: 1, indent: 60, color: Color(0x14FFFFFF)),
      itemBuilder: (BuildContext context, int i) {
        final MediaFile file = visible[i];
        return _FileRow(
          file: file,
          setup: _setupFor(file),
          onPlay: _play,
          onSetUp: () => _setUp(file),
          onPlayMusic: file.category == FileCategory.music
              ? () => _playMusic(file)
              : null,
          onRename: () => _rename(file),
          onDelete: () => _delete(file),
        );
      },
    );
  }

  Future<void> _play(SavedConfig config) async {
    // Heals paths written by a previous install before the core is handed the
    // file; see ConfigStore.repairConfigFile.
    await ConfigStore.repairConfigFile(config.path);
    await Emulator.launchConfig(
      config.path,
      whdloadArchive: config.whdloadArchive,
    );
  }

  /// Opens the wizard with the file already in the right drive. The wizard is
  /// where the machine, memory and Kickstart get decided, which is what turns
  /// a file into something that can run.
  Future<void> _setUp(MediaFile file) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => GuidedConfigScreen(
          mode: _modeFor(file.category),
          initialSettings: _settingsFor(file),
          initialName: file.title,
        ),
      ),
    );
    // The wizard may have saved a setup, which changes this row's action.
    if (mounted) _load();
  }

  Future<void> _playMusic(MediaFile file) async {
    final bool ok = await MusicPlayer.play(file.path);
    if (!mounted || ok) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('${file.name} would not play.')));
  }

  Future<void> _rename(MediaFile file) async {
    if (_setupFor(file) != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Remove this file from its setup before renaming it.'),
        ),
      );
      return;
    }
    final TextEditingController controller = TextEditingController(
      text: file.name,
    );
    final String? name = await showDialog<String>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Rename file'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'File name'),
          onSubmitted: (String value) => Navigator.of(context).pop(value),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('Rename'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.trim() == file.name) return;
    try {
      await MediaLibrary.rename(file, name);
      await _load(rescan: true);
    } on Object catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not rename file: $error')),
        );
      }
    }
  }

  Future<void> _delete(MediaFile file) async {
    if (_setupFor(file) != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Remove this file from its setup before deleting it.'),
        ),
      );
      return;
    }
    final bool confirmDelete = await AppPrefs.confirmFileDelete();
    if (!mounted) return;
    if (confirmDelete) {
      final bool? confirmed = await showDialog<bool>(
        context: context,
        builder: (BuildContext context) => AlertDialog(
          title: const Text('Delete file?'),
          content: Text('Delete “${file.name}”? This cannot be undone.'),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AmigaColors.tickRed,
              ),
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Delete'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }
    try {
      await MediaLibrary.delete(file);
      await _load(rescan: true);
    } on Object catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not delete file: $error')),
        );
      }
    }
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
    // A file with RTG in its name wants a graphics card, and an A1200 with a
    // Zorro III card is what those builds are made for. Without it they run
    // and draw nothing.
    final EmulatorSettings base = EmulatorSettings.looksLikeRtg(file.name)
        ? EmulatorSettings.fromModel(
            AmigaModel.a1200,
          ).copyWith(useRtg: true, z3Ram: 64, fastRam: 8)
        : const EmulatorSettings();
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

/// One file: what it is, what it is called, and what can be done with it.
class _FileRow extends StatelessWidget {
  const _FileRow({
    required this.file,
    required this.setup,
    required this.onPlay,
    required this.onSetUp,
    required this.onPlayMusic,
    required this.onRename,
    required this.onDelete,
  });

  final MediaFile file;
  final SavedConfig? setup;
  final void Function(SavedConfig) onPlay;
  final VoidCallback onSetUp;
  final VoidCallback? onPlayMusic;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  static const Map<FileCategory, String> _badges = <FileCategory, String>{
    FileCategory.floppies: 'ADF',
    FileCategory.whdloadGames: 'LHA',
    FileCategory.hardDrives: 'HDF',
    FileCategory.cdImages: 'CD',
    FileCategory.roms: 'ROM',
    FileCategory.archives: 'ZIP',
    FileCategory.music: 'MOD',
  };

  static Color _colour(FileCategory category) {
    switch (category) {
      case FileCategory.floppies:
        return AmigaColors.workbenchBlue;
      case FileCategory.whdloadGames:
        return const Color(0xFF7C3AED);
      case FileCategory.hardDrives:
        return const Color(0xFF0E7C66);
      case FileCategory.cdImages:
        return const Color(0xFFB45309);
      case FileCategory.roms:
        return AmigaColors.tickRed;
      case FileCategory.archives:
        return const Color(0xFF4B5563);
      case FileCategory.music:
        return const Color(0xFF9D174D);
    }
  }

  String get _size {
    final int bytes = file.size;
    if (bytes <= 0) return '';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).round()} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final SavedConfig? config = setup;
    final bool ready = config != null;
    final bool isMusic = file.category == FileCategory.music;

    return ListTile(
      dense: true,
      // Music starts directly; everything else either plays its saved setup
      // or opens the wizard rather than failing quietly.
      onTap: isMusic && onPlayMusic != null
          ? onPlayMusic
          : ready
          ? () => onPlay(config)
          : onSetUp,
      leading: Container(
        width: 42,
        height: 26,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: _colour(file.category),
          borderRadius: BorderRadius.circular(5),
        ),
        child: Text(
          _badges[file.category] ?? '',
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w800,
            color: Colors.white,
          ),
        ),
      ),
      title: Text(
        file.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: AmigaColors.text,
        ),
      ),
      subtitle: Text(
        <String>[
          if (ready) 'Set up as ${config.name}' else 'No setup yet',
          if (file.folder.isNotEmpty) file.folder,
          if (_size.isNotEmpty) _size,
        ].join('  ·  '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 11,
          color: ready ? AmigaColors.tickGreen : AmigaColors.textDim,
        ),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (isMusic && onPlayMusic != null)
            IconButton(
              tooltip: 'Play',
              onPressed: onPlayMusic,
              icon: const Icon(Icons.play_arrow),
              visualDensity: VisualDensity.compact,
            )
          else if (!isMusic && ready)
            IconButton(
              tooltip: 'Play',
              onPressed: () => onPlay(config),
              icon: const Icon(Icons.play_arrow),
              visualDensity: VisualDensity.compact,
            )
          else if (!isMusic)
            IconButton(
              tooltip: 'Set up',
              onPressed: onSetUp,
              icon: const Icon(Icons.tune),
              visualDensity: VisualDensity.compact,
            ),
          IconButton(
            tooltip: 'Rename',
            onPressed: onRename,
            icon: const Icon(Icons.drive_file_rename_outline),
            visualDensity: VisualDensity.compact,
          ),
          IconButton(
            tooltip: 'Delete',
            onPressed: onDelete,
            icon: const Icon(Icons.delete_outline),
            color: AmigaColors.tickRed,
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
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
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 1,
                  ),
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
