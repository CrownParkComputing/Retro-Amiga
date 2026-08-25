import 'package:flutter/material.dart';

import '../data/amiga_model.dart';
import '../data/config_store.dart';
import '../data/emulator_settings.dart';
import '../data/file_category.dart';
import '../data/hard_drive_set.dart';
import '../data/media_library.dart';
import '../data/zeb_whdload_support.dart';
import '../emulator.dart';
import '../widgets/amiga_logo.dart';
import '../widgets/media_chooser.dart';

/// What the user said they were setting up. It decides which machines are
/// offered, where the wizard starts, and which steps it skips.
enum WizardMode {
  floppy('Floppy disk', 'ADF, ADZ, IPF and the rest'),
  hardDrive('Hard drive', 'HDF, AGS_UAE or a dated WHDLoad setup'),
  cd('CD game', 'CD32 or CDTV disc'),
  whdload('WHDLoad', 'An .lha archive'),
  custom('Something else', 'Pick everything yourself'),
  edit('Edit', 'Change an existing setup');

  const WizardMode(this.title, this.blurb);
  final String title;
  final String blurb;

  /// The uae4arm artwork for this kind of media. A picture of a floppy says
  /// "floppy" faster than the word does, and it is the same art the rest of
  /// the app uses for the same things.
  String get artworkPath {
    switch (this) {
      case WizardMode.floppy:
        return 'assets/machines/floppy_inserted.png';
      case WizardMode.hardDrive:
        return 'assets/machines/drive_dh0.png';
      case WizardMode.cd:
        return 'assets/machines/cd32.png';
      case WizardMode.whdload:
        return 'assets/machines/a1200.png';
      case WizardMode.custom:
      case WizardMode.edit:
        return 'assets/machines/default.png';
    }
  }

  /// Machines worth offering. WHDLoad wants a fast AGA machine; a CD game
  /// only runs on the console.
  List<AmigaModel> get models {
    switch (this) {
      case WizardMode.cd:
        return <AmigaModel>[AmigaModel.cd32, AmigaModel.cdtv];
      case WizardMode.whdload:
        return <AmigaModel>[
          AmigaModel.a1200,
          AmigaModel.a4000,
          AmigaModel.a600,
        ];
      case WizardMode.hardDrive:
        return <AmigaModel>[
          AmigaModel.a1200,
          AmigaModel.a4000,
          AmigaModel.a3000,
          AmigaModel.a600,
        ];
      default:
        return AmigaModel.values;
    }
  }

  /// The machine this kind of setup starts from, with what the kind needs on
  /// top of it.
  ///
  /// WHDLoad gets 8MB of Z2 fast RAM. Almost every slave expects it - it is
  /// what an expanded A1200 had and what WHDLoad's own install notes assume -
  /// and an A1200 out of the box has none, so a game that wants it either
  /// refuses to start or runs from chip RAM and crawls.
  EmulatorSettings settingsFor(AmigaModel model) {
    final EmulatorSettings base = EmulatorSettings.fromModel(model);
    return this == WizardMode.whdload ? base.copyWith(fastRam: 8) : base;
  }

  AmigaModel get initialModel {
    switch (this) {
      case WizardMode.cd:
        return AmigaModel.cd32;
      case WizardMode.whdload:
      case WizardMode.hardDrive:
        return AmigaModel.a1200;
      default:
        return AmigaModel.a500;
    }
  }
}

enum WizardStep { machine, rom, mediaPrimary, mediaOptional, tailor, save }

class GuidedConfigScreen extends StatefulWidget {
  const GuidedConfigScreen({
    super.key,
    required this.mode,
    this.initialSettings,
    this.initialName,
  });

  final WizardMode mode;
  final EmulatorSettings? initialSettings;
  final String? initialName;

  @override
  State<GuidedConfigScreen> createState() => _GuidedConfigScreenState();
}

class _GuidedConfigScreenState extends State<GuidedConfigScreen> {
  late EmulatorSettings _settings;
  late WizardStep _step;
  final TextEditingController _name = TextEditingController();

  /// True while the name is still the one we suggested, so that changing the
  /// machine or the disk updates it - and false the moment the user edits it,
  /// so we never overwrite their words.
  bool _nameIsAutomatic = true;

  /// Whether the second-drive question has been answered with yes. Reset per
  /// wizard, not persisted: it is an answer about this setup, not a setting.
  bool _wantsSecondDrive = false;
  String _selectedDriveSetName = '';

  /// `<media> (<machine>)`, from whatever media the setup has.
  String get _suggestedName {
    String basename(String path) {
      if (path.isEmpty) return '';
      final int slash = path.lastIndexOf('/');
      final String name = slash < 0 ? path : path.substring(slash + 1);
      final int dot = name.lastIndexOf('.');
      return dot <= 0 ? name : name.substring(0, dot);
    }

    final String media = _selectedDriveSetName.isNotEmpty
        ? _selectedDriveSetName
        : <String>[
                _settings.floppy0,
                _settings.cdImage,
                _settings.whdloadFilename,
                ..._settings.hardDrives,
              ]
              .map(basename)
              .firstWhere((String s) => s.isNotEmpty, orElse: () => '');

    final String machine = _settings.baseModel.displayName;
    if (media.isEmpty) return machine;
    return '$media ($machine)';
  }

  void _refreshSuggestedName() {
    if (!_nameIsAutomatic) return;
    final String suggestion = _suggestedName;
    if (_name.text != suggestion) _name.text = suggestion;
  }

  String? _error;

  /// The scan, for picking ROMs without asking. Empty until it loads, which is
  /// why _autoPickRoms runs from build rather than once at startup.
  MediaIndex _index = const MediaIndex.empty();

  /// Chooses the ROMs the machine needs, where the user has not.
  ///
  /// A CD console needs two - its Kickstart and an extended ROM with the CD
  /// firmware - and picking them by hand from a list of eight means knowing
  /// which of them is which. Anything already chosen is left alone.
  void _autoPickRoms() {
    if (_index.files.isEmpty) return;
    final List<MediaFile> roms = _index.of(FileCategory.roms);
    if (roms.isEmpty) return;

    EmulatorSettings updated = _settings;
    if (updated.romFile.isEmpty) {
      final MediaFile? rom = RomPicker.kickstartFor(updated.baseModel, roms);
      if (rom != null) updated = updated.copyWith(romFile: rom.path);
    }
    if (updated.baseModel.needsExtendedRom && updated.romExtFile.isEmpty) {
      final MediaFile? ext = RomPicker.extendedRomFor(updated.baseModel, roms);
      if (ext != null) updated = updated.copyWith(romExtFile: ext.path);
    }
    if (!identical(updated, _settings) && updated != _settings) {
      // Assigned directly: this runs during build, and setState there is an
      // error. The frame being built already reads the new value.
      _settings = updated;
    }
  }

  @override
  void initState() {
    super.initState();
    MediaLibrary.cached().then((MediaIndex index) {
      if (mounted) setState(() => _index = index);
    });
    _settings =
        widget.initialSettings ??
        widget.mode.settingsFor(widget.mode.initialModel);
    _name.text = widget.initialName ?? '';
    // Whatever the user has not typed themselves follows the media and the
    // machine, so a shelf of setups reads "Lotus Turbo Challenge (A500)"
    // rather than a column of "Untitled". Recomputed as they go, until they
    // type something of their own.
    _nameIsAutomatic = true;
    // An existing setup already has a machine, so re-asking is a pointless tap
    // and risks resetting CPU and chipset if a model is tapped again.
    _step = widget.mode == WizardMode.edit
        ? WizardStep.tailor
        : WizardStep.machine;
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  /// The steps this run will actually visit, so the dots and Back match what
  /// Next does.
  List<WizardStep> get _route {
    final List<WizardStep> steps = <WizardStep>[WizardStep.machine];
    // Every machine needs its ROM chosen, consoles included. They were skipped
    // here on the assumption that a console carries its own, which is wrong in
    // the way that matters: a CD32 needs both a Kickstart and an extended ROM
    // holding the CD firmware, and with neither set the core starts and shows
    // nothing at all.
    steps.add(WizardStep.rom);
    steps.add(WizardStep.mediaPrimary);
    if (widget.mode == WizardMode.floppy ||
        widget.mode == WizardMode.hardDrive) {
      steps.add(WizardStep.mediaOptional);
    }
    steps.add(WizardStep.tailor);
    steps.add(WizardStep.save);
    return steps;
  }

  bool get _canAdvance {
    switch (_step) {
      case WizardStep.rom:
        if (_settings.romFile.isEmpty) return false;
        // Without the extended ROM a CD console boots to nothing, so this is
        // a requirement rather than an option.
        if (_settings.baseModel.needsExtendedRom &&
            _settings.romExtFile.isEmpty) {
          return false;
        }
        return true;
      case WizardStep.mediaPrimary:
        switch (widget.mode) {
          case WizardMode.floppy:
            return _settings.floppy0.isNotEmpty;
          case WizardMode.hardDrive:
            return _settings.hardDrives.any((String d) => d.isNotEmpty);
          case WizardMode.cd:
            return _settings.cdImage.isNotEmpty;
          case WizardMode.whdload:
            return _settings.whdloadFilename.isNotEmpty;
          default:
            return true;
        }
      case WizardStep.save:
        return _name.text.trim().isNotEmpty;
      default:
        return true;
    }
  }

  void _go(int delta) {
    final List<WizardStep> route = _route;
    final int index = route.indexOf(_step);
    final int next = index + delta;
    if (next < 0) {
      Navigator.of(context).pop();
      return;
    }
    if (next >= route.length) return;
    setState(() => _step = route[next]);
  }

  Future<void> _finish({required bool launch}) async {
    try {
      final EmulatorSettings prepared = await ZebWhdloadSupport.prepare(
        _settings,
        _index,
      );
      _settings = prepared;
      await ConfigStore.save(prepared, _name.text);
      if (launch) {
        final String path = (await ConfigStore.saveCurrent(prepared)).path;
        await Emulator.launchConfig(
          path,
          whdloadArchive: prepared.whdloadFilename,
        );
      }
      if (mounted) Navigator.of(context).pop(true);
    } on Exception catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    _autoPickRoms();
    _refreshSuggestedName();
    final List<WizardStep> route = _route;
    final int index = route.indexOf(_step);
    final bool last = _step == WizardStep.save;

    // No app bar and no step headings. A title saying "New floppy disk" over
    // a list of floppy disks, and "Which Amiga?" over a list of Amigas, is a
    // line of chrome telling you what you can already see - and on a landscape
    // handheld each one costs a row of the things you actually came to pick.
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: <Widget>[
            Row(
              children: <Widget>[
                IconButton(
                  onPressed: () => _go(-1),
                  icon: const Icon(Icons.arrow_back),
                  visualDensity: VisualDensity.compact,
                ),
                Expanded(
                  child: _StepDots(count: route.length, index: index),
                ),
                const SizedBox(width: 48),
              ],
            ),
            if (_error != null)
              Container(
                width: double.infinity,
                color: Theme.of(context).colorScheme.errorContainer,
                padding: const EdgeInsets.all(12),
                child: Text(
                  _error!,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onErrorContainer,
                  ),
                ),
              ),
            Expanded(child: _buildStep()),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: <Widget>[
                    OutlinedButton(
                      onPressed: () => _go(-1),
                      child: Text(index == 0 ? 'Cancel' : 'Back'),
                    ),
                    const Spacer(),
                    if (last)
                      OutlinedButton(
                        onPressed: _canAdvance
                            ? () => _finish(launch: false)
                            : null,
                        child: const Text('Save'),
                      ),
                    if (last) const SizedBox(width: 12),
                    FilledButton(
                      onPressed: _canAdvance
                          ? () => last ? _finish(launch: true) : _go(1)
                          : null,
                      child: Text(last ? 'Save and play' : 'Next'),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStep() {
    switch (_step) {
      case WizardStep.machine:
        return _MachineStep(
          models: widget.mode.models,
          selected: _settings.baseModel,
          onSelected: (AmigaModel model) => setState(() {
            // Take the machine's defaults wholesale: chipset, RAM and CPU all
            // move together, and mixing them is how you get a config that
            // boots to a grey screen.
            _settings = widget.mode
                .settingsFor(model)
                .copyWith(
                  romFile: _settings.romFile,
                  floppy0: _settings.floppy0,
                  cdImage: _settings.cdImage,
                  hardDrives: _settings.hardDrives,
                  whdloadFilename: _settings.whdloadFilename,
                );
          }),
        );

      case WizardStep.rom:
        if (_settings.baseModel.needsExtendedRom) {
          return _CdRomStep(
            settings: _settings,
            onKickstart: (String p) =>
                setState(() => _settings = _settings.copyWith(romFile: p)),
            onExtended: (String p) =>
                setState(() => _settings = _settings.copyWith(romExtFile: p)),
          );
        }
        return _ChooseStep(
          title: 'Kickstart ROM',
          blurb:
              'Firmware for the ${_settings.baseModel.displayName}. You supply your own.',
          category: FileCategory.roms,
          selected: _settings.romFile,
          onSelected: (String p) =>
              setState(() => _settings = _settings.copyWith(romFile: p)),
        );

      case WizardStep.mediaPrimary:
        switch (widget.mode) {
          case WizardMode.cd:
            return _ChooseStep(
              title: 'CD image',
              blurb: 'ISO, CUE, CCD, MDS, NRG or CHD.',
              category: FileCategory.cdImages,
              selected: _settings.cdImage,
              onSelected: (String p) =>
                  setState(() => _settings = _settings.copyWith(cdImage: p)),
            );
          case WizardMode.hardDrive:
            return _HardDriveStep(
              selected: _settings.hardDrives,
              onFileSelected: (String path) => setState(() {
                _selectedDriveSetName = '';
                _settings = _settings.copyWith(hardDrives: <String>[path]);
              }),
              onSetSelected: (HardDriveSet set) => setState(() {
                _selectedDriveSetName = set.name;
                if (set.looksLikeAgs) {
                  // AGS runs its selector on RTG and expects a quick A1200.
                  // Preserve the ROM already chosen by this wizard.
                  _settings = EmulatorSettings.fromModel(AmigaModel.a1200)
                      .copyWith(
                        cpuSpeed: 'max',
                        fpuModel: 68882,
                        jitCacheSize: 16384,
                        chipRam: 4,
                        z3Ram: 512,
                        useRtg: true,
                        romFile: _settings.romFile,
                        hardDrives: set.allMounts,
                      );
                } else {
                  _settings = _settings.copyWith(hardDrives: set.allMounts);
                }
              }),
            );
          case WizardMode.whdload:
            return _ChooseStep(
              title: 'WHDLoad archive',
              blurb: 'The .lha the game ships in.',
              category: FileCategory.whdloadGames,
              selected: _settings.whdloadFilename,
              onSelected: (String p) => setState(
                () => _settings = _settings.copyWith(whdloadFilename: p),
              ),
            );
          default:
            return _ChooseStep(
              title: 'Floppy in DF0',
              blurb: 'ADF, ADZ, IPF, DMS and the rest.',
              category: FileCategory.floppies,
              selected: _settings.floppy0,
              onSelected: (String p) =>
                  setState(() => _settings = _settings.copyWith(floppy0: p)),
            );
        }

      case WizardStep.mediaOptional:
        // The question comes before the list. A full file chooser for a drive
        // most setups do not want reads as a demand for a second disk; a
        // yes/no first makes skipping the default rather than the escape.
        if (!_wantsSecondDrive && _settings.floppy1.isEmpty) {
          return _AskStep(
            question: 'Add another floppy drive?',
            blurb: 'Many games ask for disk 2. One-disk games need only DF0.',
            onYes: () => setState(() => _wantsSecondDrive = true),
            onNo: () => _go(1),
          );
        }
        return _ChooseStep(
          title: 'Floppy in DF1',
          blurb: 'ADF, ADZ, IPF, DMS and the rest.',
          category: FileCategory.floppies,
          selected: _settings.floppy1,
          onSelected: (String p) => setState(
            () => _settings = _settings.copyWith(floppy1: p, floppy1Type: 0),
          ),
        );

      case WizardStep.tailor:
        return _TailorStep(
          settings: _settings,
          onChanged: (EmulatorSettings s) => setState(() => _settings = s),
        );

      case WizardStep.save:
        return _SaveStep(
          controller: _name,
          settings: _settings,
          onChanged: () => setState(() => _nameIsAutomatic = false),
        );
    }
  }
}

class _StepDots extends StatelessWidget {
  const _StepDots({required this.count, required this.index});

  final int count;
  final int index;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List<Widget>.generate(count, (int i) {
          final bool done = i <= index;
          return Container(
            width: i == index ? 24 : 8,
            height: 8,
            margin: const EdgeInsets.symmetric(horizontal: 4),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(4),
              color: done
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).colorScheme.surfaceContainerHighest,
            ),
          );
        }),
      ),
    );
  }
}

class _MachineStep extends StatelessWidget {
  const _MachineStep({
    required this.models,
    required this.selected,
    required this.onSelected,
  });

  final List<AmigaModel> models;
  final AmigaModel selected;
  final ValueChanged<AmigaModel> onSelected;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        // Two columns on a landscape screen puts every machine in view at
        // once, which is the difference between choosing and scrolling.
        final int columns = (constraints.maxWidth / 420).floor().clamp(1, 3);
        return GridView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisExtent: 72,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
          ),
          itemCount: models.length,
          itemBuilder: (BuildContext context, int i) {
            final AmigaModel model = models[i];
            final bool isSelected = model == selected;
            return Material(
              color: isSelected
                  ? Theme.of(context).colorScheme.primaryContainer
                  : Theme.of(context).colorScheme.surfaceContainerHighest
                        .withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(10),
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () => onSelected(model),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Row(
                    children: <Widget>[
                      SizedBox(
                        width: 64,
                        height: 44,
                        child: Image.asset(
                          model.artworkPath,
                          fit: BoxFit.contain,
                          errorBuilder:
                              (BuildContext c, Object e, StackTrace? s) =>
                                  const AmigaLogo(height: 24),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              model.displayName,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              model.description,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                      if (isSelected) const Icon(Icons.check_circle, size: 20),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

/// A step that offers what the scan found, with the title above it.
/// A yes/no question standing where a list would otherwise be.
class _AskStep extends StatelessWidget {
  const _AskStep({
    required this.question,
    required this.blurb,
    required this.onYes,
    required this.onNo,
  });

  final String question;
  final String blurb;
  final VoidCallback onYes;
  final VoidCallback onNo;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(question, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(blurb, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 20),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              FilledButton(onPressed: onYes, child: const Text('Add a drive')),
              const SizedBox(width: 16),
              OutlinedButton(onPressed: onNo, child: const Text('Just DF0')),
            ],
          ),
        ],
      ),
    );
  }
}

class _ChooseStep extends StatelessWidget {
  const _ChooseStep({
    required this.title,
    required this.blurb,
    required this.category,
    required this.selected,
    required this.onSelected,
  });

  final String title;
  final String blurb;
  final FileCategory category;
  final String selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: MediaChooser(
        category: category,
        selected: selected,
        onSelected: onSelected,
        // Only shown when there is nothing to list, which is the one moment
        // when saying what was wanted actually helps.
        emptyHint: 'No $title found. $blurb',
      ),
    );
  }
}

/// Chooses loose hard-drive images and complete setups from the one canonical
/// `HardDrives` folder. AGS and Zeb's dated WHDLoad packs are not separate
/// setup modes: putting each in its own child folder is enough to detect it.
class _HardDriveStep extends StatefulWidget {
  const _HardDriveStep({
    required this.selected,
    required this.onFileSelected,
    required this.onSetSelected,
  });

  final List<String> selected;
  final ValueChanged<String> onFileSelected;
  final ValueChanged<HardDriveSet> onSetSelected;

  @override
  State<_HardDriveStep> createState() => _HardDriveStepState();
}

class _HardDriveStepState extends State<_HardDriveStep> {
  MediaIndex _index = const MediaIndex.empty();

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final MediaIndex index = await MediaLibrary.cached();
    if (mounted) setState(() => _index = index);
  }

  List<HardDriveSet> get _sets {
    final List<MediaFile> drives = _index.of(FileCategory.hardDrives);
    if (drives.isEmpty) return const <HardDriveSet>[];
    final String firstPath = drives.first.path;
    final String marker = '/HardDrives/';
    final int at = firstPath.replaceAll(r'\', '/').indexOf(marker);
    if (at < 0) return const <HardDriveSet>[];
    return HardDriveSet.discoverIn(
      _index,
      firstPath.substring(0, at + marker.length - 1),
    );
  }

  bool _selected(HardDriveSet set) {
    if (set.allMounts.length != widget.selected.length) return false;
    for (int i = 0; i < set.allMounts.length; i++) {
      if (set.allMounts[i] != widget.selected[i]) return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final List<HardDriveSet> sets = _sets;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Expanded(
                child: Text(
                  'HardDrives is scanned automatically. Keep AGS_UAE and each '
                  'dated WHDLoad setup in its own folder.',
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (sets.isNotEmpty) ...<Widget>[
            SizedBox(
              height: (sets.length * 78.0).clamp(78.0, 220.0),
              child: ListView(
                children: <Widget>[
                  for (final HardDriveSet set in sets)
                    Card(
                      child: ListTile(
                        leading: Icon(
                          set.looksLikeAgs ? Icons.grid_view : Icons.storage,
                        ),
                        title: Text(set.name),
                        subtitle: Text(
                          '${set.driveCount} drive(s) · boots '
                          '${set.bootDrive.split(RegExp(r'[/\\]')).last}'
                          '${set.looksLikeAgs ? ' · AGS/RTG' : ''}'
                          '${set.looksLikeZebWhdload ? ' · Zeb WHDLoad' : ''}',
                        ),
                        trailing: _selected(set)
                            ? const Icon(Icons.check_circle)
                            : const Icon(Icons.chevron_right),
                        selected: _selected(set),
                        onTap: () => widget.onSetSelected(set),
                      ),
                    ),
                ],
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(4, 8, 4, 4),
              child: Text('Individual hard-drive images'),
            ),
          ],
          Expanded(
            child: MediaChooser(
              category: FileCategory.hardDrives,
              selected: widget.selected.length == 1
                  ? widget.selected.first
                  : '',
              onSelected: widget.onFileSelected,
              emptyHint: 'Nothing was found in HardDrives.',
            ),
          ),
        ],
      ),
    );
  }
}

class _TailorStep extends StatelessWidget {
  const _TailorStep({required this.settings, required this.onChanged});

  final EmulatorSettings settings;
  final ValueChanged<EmulatorSettings> onChanged;

  @override
  Widget build(BuildContext context) {
    // What the machine can actually use. A console has no Zorro bus, so RTG is
    // not an option however fast its CPU; and the JIT has nothing to translate
    // below a 68020. Showing either would be a switch that does nothing.
    final bool canJit = settings.cpuModel >= 68020 && settings.baseModel.canJit;
    final bool canRtg = settings.baseModel.canRtg;
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      children: <Widget>[
        // The machine, because this is the one step where what is on offer
        // depends on it. Not a heading: a line of fact.
        Text(
          '${settings.baseModel.displayName} · ${settings.baseModel.description}',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        if (canJit)
          SwitchListTile(
            title: const Text('JIT acceleration'),
            subtitle: const Text(
              'Much faster on 68020 and above. Some timing-sensitive games dislike it.',
            ),
            value: settings.jitCacheSize > 0,
            onChanged: (bool on) => onChanged(
              settings.copyWith(jitCacheSize: on ? 16384 : 0, jitFpu: on),
            ),
          ),
        if (canRtg)
          SwitchListTile(
            title: const Text('RTG graphics (uaegfx)'),
            subtitle: const Text('A Zorro III graphics card for Workbench.'),
            value: settings.useRtg,
            onChanged: (bool on) => onChanged(settings.copyWith(useRtg: on)),
          ),
        SwitchListTile(
          title: const Text('NTSC'),
          subtitle: const Text('60Hz, for software that expects a US machine.'),
          value: settings.ntsc,
          onChanged: (bool on) => onChanged(settings.copyWith(ntsc: on)),
        ),
        if (settings.baseModel == AmigaModel.cd32)
          SwitchListTile(
            title: const Text('FMV cartridge'),
            subtitle: const Text(
              'The MPEG video add-on a few CD32 titles need.',
            ),
            value: settings.cd32Fmv,
            onChanged: (bool on) => onChanged(settings.copyWith(cd32Fmv: on)),
          ),
        SwitchListTile(
          title: const Text('Correct aspect ratio'),
          subtitle: const Text('4:3, the shape the games were drawn for.'),
          value: settings.correctAspect,
          onChanged: (bool on) =>
              onChanged(settings.copyWith(correctAspect: on)),
        ),
      ],
    );
  }
}

class _SaveStep extends StatelessWidget {
  const _SaveStep({
    required this.controller,
    required this.settings,
    required this.onChanged,
  });

  final TextEditingController controller;
  final EmulatorSettings settings;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      children: <Widget>[
        // The field's own label says what this is; a heading over it would
        // say it twice.
        TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            labelText: 'Setup name',
            hintText: 'Lemmings',
          ),
          onChanged: (_) => onChanged(),
        ),
        const SizedBox(height: 24),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    SizedBox(
                      width: 72,
                      height: 48,
                      child: Image.asset(
                        settings.baseModel.artworkPath,
                        fit: BoxFit.contain,
                        errorBuilder:
                            (BuildContext c, Object e, StackTrace? s) =>
                                const AmigaLogo(height: 24),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        settings.baseModel.displayName,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (settings.romFile.isNotEmpty)
                  Text('ROM: ${settings.romFile.split(RegExp(r'[/\\]')).last}'),
                if (settings.floppy0.isNotEmpty)
                  Text('DF0: ${settings.floppy0.split(RegExp(r'[/\\]')).last}'),
                if (settings.floppy1.isNotEmpty)
                  Text('DF1: ${settings.floppy1.split(RegExp(r'[/\\]')).last}'),
                if (settings.cdImage.isNotEmpty)
                  Text('CD: ${settings.cdImage.split(RegExp(r'[/\\]')).last}'),
                if (settings.whdloadFilename.isNotEmpty)
                  Text(
                    'WHDLoad: ${settings.whdloadFilename.split(RegExp(r'[/\\]')).last}',
                  ),
                if (settings.jitCacheSize > 0) const Text('JIT on'),
                if (settings.useRtg) const Text('RTG on'),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Both ROMs a CD console needs, on one step.
///
/// The Kickstart and the extended ROM are two files with almost the same name
/// in most ROM sets, and getting them the wrong way round produces a machine
/// that starts and shows nothing. Both are pre-selected from the scan; this is
/// where that guess can be corrected.
class _CdRomStep extends StatelessWidget {
  const _CdRomStep({
    required this.settings,
    required this.onKickstart,
    required this.onExtended,
  });

  final EmulatorSettings settings;
  final ValueChanged<String> onKickstart;
  final ValueChanged<String> onExtended;

  static String _name(String path) {
    if (path.isEmpty) return 'not chosen';
    final int slash = path.lastIndexOf('/');
    return slash < 0 ? path : path.substring(slash + 1);
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      children: <Widget>[
        // Kept, because this one is not obvious: a console needs a SECOND
        // ROM, and without it the machine starts and shows nothing.
        Text(
          'A ${settings.baseModel.displayName} needs its Kickstart and an '
          'extended ROM holding the CD firmware.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        _RomRow(
          label: 'Kickstart',
          value: _name(settings.romFile),
          selected: settings.romFile,
          onSelected: onKickstart,
        ),
        const SizedBox(height: 8),
        _RomRow(
          label: 'Extended ROM',
          value: _name(settings.romExtFile),
          selected: settings.romExtFile,
          onSelected: onExtended,
        ),
      ],
    );
  }
}

class _RomRow extends StatelessWidget {
  const _RomRow({
    required this.label,
    required this.value,
    required this.selected,
    required this.onSelected,
  });

  final String label;
  final String value;
  final String selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final bool chosen = selected.isNotEmpty;
    return Card(
      child: ListTile(
        leading: Icon(
          chosen ? Icons.check_circle : Icons.error_outline,
          color: chosen ? Theme.of(context).colorScheme.primary : null,
        ),
        title: Text(label),
        subtitle: Text(value, maxLines: 2, overflow: TextOverflow.ellipsis),
        trailing: TextButton(
          onPressed: () async {
            final String? picked = await showModalBottomSheet<String>(
              context: context,
              isScrollControlled: true,
              showDragHandle: true,
              builder: (BuildContext sheet) => SafeArea(
                child: SizedBox(
                  height: MediaQuery.of(sheet).size.height * 0.7,
                  child: MediaChooser(
                    category: FileCategory.roms,
                    selected: selected,
                    onSelected: (String path) => Navigator.of(sheet).pop(path),
                  ),
                ),
              ),
            );
            if (picked != null) onSelected(picked);
          },
          child: const Text('Change'),
        ),
      ),
    );
  }
}
