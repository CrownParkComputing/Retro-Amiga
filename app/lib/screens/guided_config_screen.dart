import 'package:flutter/material.dart';

import '../data/amiga_model.dart';
import '../data/config_store.dart';
import '../data/emulator_settings.dart';
import '../data/file_category.dart';
import '../emulator.dart';
import '../widgets/amiga_logo.dart';
import '../widgets/media_chooser.dart';

/// What the user said they were setting up. It decides which machines are
/// offered, where the wizard starts, and which steps it skips.
enum WizardMode {
  floppy('Floppy disk', 'ADF, ADZ, IPF and the rest'),
  hardDrive('Hard drive', 'HDF or a folder of files'),
  cd('CD game', 'CD32 or CDTV disc'),
  whdload('WHDLoad', 'An .lha archive'),
  custom('Something else', 'Pick everything yourself'),
  edit('Edit', 'Change an existing setup');

  const WizardMode(this.title, this.blurb);
  final String title;
  final String blurb;

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

  /// `<media> (<machine>)`, from whatever media the setup has.
  String get _suggestedName {
    String basename(String path) {
      if (path.isEmpty) return '';
      final int slash = path.lastIndexOf('/');
      final String name = slash < 0 ? path : path.substring(slash + 1);
      final int dot = name.lastIndexOf('.');
      return dot <= 0 ? name : name.substring(0, dot);
    }

    final String media = <String>[
      _settings.floppy0,
      _settings.cdImage,
      _settings.whdloadFilename,
      ..._settings.hardDrives,
    ].map(basename).firstWhere((String s) => s.isNotEmpty, orElse: () => '');

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

  @override
  void initState() {
    super.initState();
    _settings =
        widget.initialSettings ??
        EmulatorSettings.fromModel(widget.mode.initialModel);
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
    // The CD consoles carry their own ROMs, picked with the machine.
    if (!_settings.baseModel.hasCd) steps.add(WizardStep.rom);
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
        return _settings.romFile.isNotEmpty;
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
      await ConfigStore.save(_settings, _name.text);
      if (launch) {
        final String path = (await ConfigStore.saveCurrent(_settings)).path;
        await Emulator.launchConfig(path);
      }
      if (mounted) Navigator.of(context).pop(true);
    } on Exception catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    _refreshSuggestedName();
    final List<WizardStep> route = _route;
    final int index = route.indexOf(_step);
    final bool last = _step == WizardStep.save;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.mode == WizardMode.edit
              ? 'Edit setup'
              : 'New ${widget.mode.title.toLowerCase()}',
        ),
      ),
      body: Column(
        children: <Widget>[
          _StepDots(count: route.length, index: index),
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
            _settings = EmulatorSettings.fromModel(model).copyWith(
              romFile: _settings.romFile,
              floppy0: _settings.floppy0,
              cdImage: _settings.cdImage,
              hardDrives: _settings.hardDrives,
              whdloadFilename: _settings.whdloadFilename,
            );
          }),
        );

      case WizardStep.rom:
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
            return _ChooseStep(
              title: 'Hard drive',
              blurb: 'An HDF image to mount as a drive.',
              category: FileCategory.hardDrives,
              selected: _settings.hardDrives.firstWhere(
                (String d) => d.isNotEmpty,
                orElse: () => '',
              ),
              onSelected: (String p) => setState(
                () => _settings = _settings.copyWith(hardDrives: <String>[p]),
              ),
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
        return _ChooseStep(
          title: 'Second floppy (optional)',
          blurb: 'Many games ask for disk 2. Skip if there is only one.',
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
      padding: const EdgeInsets.symmetric(vertical: 16),
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
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      children: <Widget>[
        Text('Which Amiga?', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        const Text('The machine decides the chipset, CPU and memory.'),
        const SizedBox(height: 16),
        ...models.map((AmigaModel model) {
          final bool isSelected = model == selected;
          return Card(
            elevation: isSelected ? 3 : 0,
            color: isSelected
                ? Theme.of(context).colorScheme.primaryContainer
                : null,
            child: ListTile(
              leading: SizedBox(
                width: 88,
                height: 56,
                child: Image.asset(
                  model.artworkPath,
                  fit: BoxFit.contain,
                  errorBuilder: (BuildContext c, Object e, StackTrace? s) =>
                      const AmigaLogo(height: 28),
                ),
              ),
              title: Text(model.displayName),
              subtitle: Text(model.description),
              trailing: isSelected ? const Icon(Icons.check_circle) : null,
              onTap: () => onSelected(model),
            ),
          );
        }),
      ],
    );
  }
}

/// A step that offers what the scan found, with the title above it.
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
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(blurb, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 8),
          Expanded(
            child: MediaChooser(
              category: category,
              selected: selected,
              onSelected: onSelected,
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
    final bool canJit = settings.cpuModel >= 68020;
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      children: <Widget>[
        Text('Tailor it', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        Text(
          '${settings.baseModel.displayName} · ${settings.baseModel.description}',
        ),
        const SizedBox(height: 16),
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
        if (canJit)
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
      padding: const EdgeInsets.symmetric(horizontal: 24),
      children: <Widget>[
        Text('Name it', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        const Text('It goes on the shelf under this name.'),
        const SizedBox(height: 16),
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
