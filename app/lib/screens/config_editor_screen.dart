import 'package:flutter/material.dart';

import '../data/config_generator.dart';
import '../data/config_parser.dart';
import '../data/config_store.dart';
import '../data/core_kind.dart';
import '../data/amiga_model.dart';
import '../data/emulator_settings.dart';
import '../data/file_category.dart';
import '../ffi/amiga_core.dart';
import '../widgets/media_chooser.dart';

/// The whole machine, in the shape the core's own panels use.
///
/// One tab per group the original interface drew a panel for: the machine
/// and its chipset, memory, media in the drives, the picture, the sound and
/// the input ports. The wizard asks the few questions a setup cannot start
/// without; this is where everything it never asked lives.
///
/// It edits a config file that already exists, so it starts by reading one:
/// the wizard writes, this reads back and writes over. Every field the
/// parser reads is offered somewhere in the tabs -- a control the parser
/// cannot round-trip would write a value the next edit silently loses.
class ConfigEditorScreen extends StatefulWidget {
  const ConfigEditorScreen({super.key, required this.config});

  final SavedConfig config;

  @override
  State<ConfigEditorScreen> createState() => _ConfigEditorScreenState();
}

class _ConfigEditorScreenState extends State<ConfigEditorScreen> {
  EmulatorSettings? _settings;
  String? _error;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final String text = await ConfigStore.read(widget.config.path);
      if (!mounted) return;
      setState(
        () => _settings = ConfigParser.parse(text, model: widget.config.model),
      );
    } on Object catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  Future<void> _save() async {
    final EmulatorSettings? settings = _settings;
    if (settings == null) return;
    setState(() => _saving = true);
    try {
      await ConfigStore.saveOver(widget.config.path, settings);
      if (mounted) Navigator.of(context).pop(true);
    } on Object catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = '$e';
        });
      }
    }
  }

  void _update(EmulatorSettings next) => setState(() => _settings = next);

  /// Deleting lives here, with editing, rather than behind a menu on the
  /// shelf: this is the screen you are already on when you have decided a
  /// setup is not worth keeping, and a delete on the shelf itself sits one
  /// slip away from the tap that plays.
  Future<void> _delete() async {
    final bool confirmed =
        await showDialog<bool>(
          context: context,
          builder: (BuildContext context) => AlertDialog(
            title: Text('Delete ${widget.config.name}?'),
            content: const Text(
              'The config goes; the disks and hard drives it points at stay.',
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Keep'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Delete'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed) return;
    try {
      await ConfigStore.delete(widget.config.path);
      if (mounted) Navigator.of(context).pop(true);
    } on Object catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final EmulatorSettings? settings = _settings;

    return DefaultTabController(
      length: 6,
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.config.name),
          actions: <Widget>[
            IconButton(
              tooltip: 'Delete',
              onPressed: _saving ? null : _delete,
              icon: const Icon(Icons.delete_outline),
            ),
            TextButton(
              onPressed: _saving || settings == null ? null : _save,
              child: const Text('Save'),
            ),
          ],
          bottom: const TabBar(
            isScrollable: true,
            tabs: <Tab>[
              Tab(text: 'Machine'),
              Tab(text: 'Memory'),
              Tab(text: 'Media'),
              Tab(text: 'Display'),
              Tab(text: 'Sound'),
              Tab(text: 'Input'),
            ],
          ),
        ),
        body: settings == null
            ? Center(
                child: _error == null
                    ? const CircularProgressIndicator()
                    : Text(_error!),
              )
            : TabBarView(
                children: <Widget>[
                  _machineTab(settings),
                  _memoryTab(settings),
                  _mediaTab(settings),
                  _displayTab(settings),
                  _soundTab(settings),
                  _inputTab(settings),
                ],
              ),
      ),
    );
  }

  Widget _body(List<Widget> children) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: <Widget>[
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        ...children,
      ],
    );
  }

  Widget _machineTab(EmulatorSettings settings) {
    return _body(<Widget>[
      Text(
        '${settings.baseModel.displayName} · ${settings.baseModel.description}',
        style: Theme.of(context).textTheme.bodySmall,
      ),
      _Choice<AmigaModel>(
        label: 'Machine',
        value: settings.baseModel,
        options: <AmigaModel, String>{
          for (final AmigaModel m in AmigaModel.values) m: m.displayName,
        },
        help:
            'The whole machine changes together - chipset, RAM and CPU - '
            'because mixing them is how you get a config that boots to a '
            'grey screen. ROM and media stay where they are.',
        onChanged: (AmigaModel model) => _update(
          EmulatorSettings.fromModel(model).copyWith(
            core: settings.core,
            romFile: settings.romFile,
            romExtFile: settings.romExtFile,
            floppy0: settings.floppy0,
            floppy0Type: settings.floppy0Type,
            floppy1: settings.floppy1,
            floppy1Type: settings.floppy1Type,
            floppy2: settings.floppy2,
            floppy2Type: settings.floppy2Type,
            floppy3: settings.floppy3,
            floppy3Type: settings.floppy3Type,
            cdImage: settings.cdImage,
            whdloadFilename: settings.whdloadFilename,
            hardDrives: settings.hardDrives,
            onScreenKeyboard: settings.onScreenKeyboard,
          ),
        ),
      ),

      // Only offered when both cores shipped with this build: a picker whose
      // second option cannot launch is a trap. An Amiberry-only build looks
      // exactly as it always did.
      if (AmigaCore.isAvailable(CoreKind.copperline)) ...<Widget>[
        const _Section('Core'),
        _Choice<CoreKind>(
          label: 'Emulator',
          value: settings.core,
          options: const <CoreKind, String>{
            CoreKind.amiberry: 'Amiberry',
            CoreKind.copperline: 'Copperline',
          },
          help: settings.core == CoreKind.copperline
              ? 'Cycle exact, immediate blits, collisions and '
                    'interpolation are Amiberry settings; Copperline runs '
                    'one timing model and has no knobs for them. The setup '
                    'itself is shared.'
              : null,
          onChanged: (CoreKind v) => _update(settings.copyWith(core: v)),
        ),
      ],

      const _Section('Kickstart'),
      _FileField(
        label: 'Kickstart ROM',
        category: FileCategory.roms,
        value: settings.romFile,
        help: 'The machine firmware the setup boots.',
        onChanged: (String v) => _update(settings.copyWith(romFile: v)),
      ),
      _FileField(
        label: 'Extended ROM',
        category: FileCategory.roms,
        value: settings.romExtFile,
        help: 'The CD consoles want a second ROM beside the Kickstart.',
        onChanged: (String v) => _update(settings.copyWith(romExtFile: v)),
      ),

      const _Section('Processor'),
      _Choice<int>(
        label: 'CPU',
        value: settings.cpuModel,
        options: const <int, String>{
          68000: '68000',
          68010: '68010',
          68020: '68020',
          68030: '68030',
          68040: '68040',
          68060: '68060',
        },
        onChanged: (int v) => _update(settings.copyWith(cpuModel: v)),
      ),
      _Choice<int>(
        label: 'FPU',
        value: settings.fpuModel,
        options: const <int, String>{
          0: 'None',
          68881: '68881',
          68882: '68882',
          68040: '68040',
          68060: '68060',
        },
        help:
            'The 6888x chips sit beside a 68020/030; a 68040 or 68060 has '
            'the FPU built in.',
        onChanged: (int v) => _update(settings.copyWith(fpuModel: v)),
      ),
      _Choice<String>(
        label: 'Speed',
        value: settings.cpuSpeed,
        options: const <String, String>{
          'real': 'As the real machine',
          'max': 'Fastest possible',
        },
        help:
            'Fastest suits WHDLoad and Workbench. Games written for a stock '
            'machine often need the real speed, or they run too quickly to '
            'play.',
        onChanged: (String v) => _update(settings.copyWith(cpuSpeed: v)),
      ),
      _Switch(
        label: '24-bit addressing',
        help:
            'On for the machines that really had it: the A500, A600 and '
            'A1200 bus tops out at 16MB. Off lets a 68030+ see Zorro III '
            'space.',
        value: settings.address24Bit,
        onChanged: (bool v) => _update(settings.copyWith(address24Bit: v)),
      ),
      _Switch(
        label: 'Cycle exact',
        help: 'Slower, and the only way some demos and games behave.',
        value: settings.cycleExact,
        onChanged: (bool v) => _update(settings.copyWith(cycleExact: v)),
      ),
      _Switch(
        label: 'More compatible CPU',
        help: 'Prefetch and timing as the real chip. Off is faster.',
        value: settings.cpuCompatible,
        onChanged: (bool v) => _update(settings.copyWith(cpuCompatible: v)),
      ),
      // Not on iOS: see jitAvailable. A switch that is ignored is worse than
      // no switch, because the config then says JIT and the machine plainly
      // is not any faster.
      if (jitAvailable && settings.cpuModel >= 68020)
        _Switch(
          label: 'JIT',
          help:
              'Recompiles 68020 and later. Much faster; a few '
              'timing-sensitive titles dislike it.',
          value: settings.jitCacheSize > 0,
          onChanged: (bool v) => _update(
            settings.copyWith(jitCacheSize: v ? 16384 : 0, jitFpu: v),
          ),
        ),

      const _Section('Chipset'),
      _Choice<String>(
        label: 'Chipset',
        value: settings.chipset,
        options: const <String, String>{
          'ocs': 'OCS',
          'ecs_agnus': 'ECS Agnus',
          'ecs_denise': 'ECS Denise',
          'ecs': 'ECS',
          'aga': 'AGA',
        },
        help:
            'The partial ECS options are for the machines that shipped one '
            'new chip with one old - a 1MB-chip A500 is ECS Agnus with an '
            'OCS Denise.',
        onChanged: (String v) => _update(settings.copyWith(chipset: v)),
      ),
      _Switch(
        label: 'Immediate blits',
        help:
            'The blitter finishes at once. Faster, and wrong for anything '
            'that races it.',
        value: settings.immediateBlits,
        onChanged: (bool v) => _update(settings.copyWith(immediateBlits: v)),
      ),
      _Choice<String>(
        label: 'Collisions',
        value: settings.collisionLevel,
        options: const <String, String>{
          'none': 'None',
          'sprites': 'Sprites only',
          'playfields': 'Sprites and playfields',
          'full': 'Full',
        },
        onChanged: (String v) =>
            _update(settings.copyWith(collisionLevel: v)),
      ),
      _Switch(
        label: 'NTSC',
        help: '60Hz, for software that expects a US machine.',
        value: settings.ntsc,
        onChanged: (bool v) => _update(settings.copyWith(ntsc: v)),
      ),
    ]);
  }

  Widget _memoryTab(EmulatorSettings settings) {
    return _body(<Widget>[
      _Choice<int>(
        label: 'Chip',
        value: settings.chipRam,
        options: const <int, String>{
          1: '512 KB',
          2: '1 MB',
          4: '2 MB',
          8: '4 MB',
          16: '8 MB',
        },
        onChanged: (int v) => _update(settings.copyWith(chipRam: v)),
      ),
      _Choice<int>(
        label: 'Slow',
        value: settings.slowRam,
        options: const <int, String>{
          0: 'None',
          1: '512 KB',
          2: '1 MB',
          4: '1.8 MB',
        },
        help: 'The trapdoor RAM an A500 usually had.',
        onChanged: (int v) => _update(settings.copyWith(slowRam: v)),
      ),
      _Choice<int>(
        label: 'Fast',
        value: settings.fastRam,
        options: const <int, String>{
          0: 'None',
          1: '1 MB',
          2: '2 MB',
          4: '4 MB',
          8: '8 MB',
        },
        help:
            'WHDLoad wants some. A few floppy games refuse to run with any.',
        onChanged: (int v) => _update(settings.copyWith(fastRam: v)),
      ),
      _Choice<int>(
        label: 'Z3 fast',
        value: settings.z3Ram,
        options: const <int, String>{
          0: 'None',
          8: '8 MB',
          16: '16 MB',
          32: '32 MB',
          64: '64 MB',
          128: '128 MB',
          256: '256 MB',
          512: '512 MB',
          1024: '1 GB',
        },
        help:
            'Zorro III RAM needs a 32-bit CPU bus: a 68030 or better, or a '
            '68020 with 24-bit addressing off. The big curated packs want '
            'hundreds of megabytes.',
        onChanged: (int v) => _update(settings.copyWith(z3Ram: v)),
      ),
    ]);
  }

  Widget _mediaTab(EmulatorSettings settings) {
    return _body(<Widget>[
      const _Section('Floppy drives'),
      for (int i = 0; i < 4; i++) ...<Widget>[
        _DriveRow(
          drive: i,
          settings: settings,
          onChanged: _update,
        ),
      ],
      const _Section('CD'),
      _FileField(
        label: 'CD image',
        category: FileCategory.cdImages,
        value: settings.cdImage,
        onChanged: (String v) => _update(settings.copyWith(cdImage: v)),
      ),
      if (settings.baseModel == AmigaModel.cd32)
        _Switch(
          label: 'FMV cartridge',
          help: 'The motion-video board a handful of CD32 titles use.',
          value: settings.cd32Fmv,
          onChanged: (bool v) => _update(settings.copyWith(cd32Fmv: v)),
        ),
      const _Section('WHDLoad'),
      _FileField(
        label: 'WHDLoad package',
        category: FileCategory.whdloadGames,
        value: settings.whdloadFilename,
        help: 'The .lha the WHDLoad booter installs and runs.',
        onChanged: (String v) =>
            _update(settings.copyWith(whdloadFilename: v)),
      ),
      const _Section('Hard drives'),
      for (int i = 0; i < settings.hardDrives.length; i++)
        if (settings.hardDrives[i].isNotEmpty)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.storage, size: 20),
            title: Text(
              settings.hardDrives[i].split(RegExp(r'[/\\]')).last,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              settings.hardDrives[i],
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            trailing: IconButton(
              tooltip: 'Remove',
              icon: const Icon(Icons.delete_outline, size: 20),
              onPressed: () {
                final List<String> drives = List<String>.of(
                  settings.hardDrives,
                )..removeAt(i);
                if (drives.isEmpty) drives.add('');
                _update(settings.copyWith(hardDrives: drives));
              },
            ),
          ),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: () async {
            final String? picked = await _pickMedia(
              context,
              FileCategory.hardDrives,
              '',
            );
            if (picked == null) return;
            final List<String> drives = settings.hardDrives
                .where((String d) => d.isNotEmpty)
                .toList();
            drives.add(picked);
            _update(settings.copyWith(hardDrives: drives));
          },
          icon: const Icon(Icons.add, size: 18),
          label: const Text('Add a hard drive'),
        ),
      ),
    ]);
  }

  Widget _displayTab(EmulatorSettings settings) {
    return _body(<Widget>[
      _Switch(
        label: 'Correct aspect ratio',
        help: '4:3, the shape the games were drawn for.',
        value: settings.correctAspect,
        onChanged: (bool v) => _update(settings.copyWith(correctAspect: v)),
      ),
      _Switch(
        label: 'Auto crop',
        help: 'Trim the empty borders some titles draw.',
        value: settings.autoCrop,
        onChanged: (bool v) => _update(settings.copyWith(autoCrop: v)),
      ),
      _Switch(
        label: 'Drive lights',
        value: settings.showLeds,
        onChanged: (bool v) => _update(settings.copyWith(showLeds: v)),
      ),
      _Choice<String>(
        label: 'Native resolution',
        value: '${settings.gfxWidth}x${settings.gfxHeight}',
        options: const <String, String>{
          '640x512': '640 × 512',
          '720x568': '720 × 568',
          '1440x1136': '1440 × 1136',
        },
        onChanged: (String v) {
          final List<String> parts = v.split('x');
          _update(
            settings.copyWith(
              gfxWidth: int.parse(parts[0]),
              gfxHeight: int.parse(parts[1]),
            ),
          );
        },
      ),
      if (settings.baseModel.canRtg) ...<Widget>[
        const _Section('Graphics card'),
        _Switch(
          label: 'Zorro III graphics card (uaegfx)',
          help:
              'A Picasso-class RTG card. RTG builds draw nothing on a native '
              'screen without it.',
          value: settings.useRtg,
          onChanged: (bool v) => _update(settings.copyWith(useRtg: v)),
        ),
        if (settings.useRtg) ...<Widget>[
          _Choice<int>(
            label: 'Card memory',
            value: settings.rtgMemory,
            options: const <int, String>{
              8: '8 MB',
              16: '16 MB',
              32: '32 MB',
              64: '64 MB',
              128: '128 MB',
            },
            onChanged: (int v) =>
                _update(settings.copyWith(rtgMemory: v)),
          ),
          _Switch(
            label: 'True colour modes',
            help: 'Offer 24- and 32-bit screens, not just 8- and 16-bit.',
            value: settings.rtgTrueColour,
            onChanged: (bool v) =>
                _update(settings.copyWith(rtgTrueColour: v)),
          ),
          _Choice<String>(
            label: 'Card resolution',
            value: '${settings.rtgWidth}x${settings.rtgHeight}',
            options: const <String, String>{
              '1024x768': '1024 × 768',
              '1280x720': '1280 × 720',
              '1920x1080': '1920 × 1080',
            },
            onChanged: (String v) {
              final List<String> parts = v.split('x');
              _update(
                settings.copyWith(
                  rtgWidth: int.parse(parts[0]),
                  rtgHeight: int.parse(parts[1]),
                ),
              );
            },
          ),
        ],
      ],
    ]);
  }

  Widget _soundTab(EmulatorSettings settings) {
    return _body(<Widget>[
      _Choice<String>(
        label: 'Output',
        value: settings.soundOutput,
        options: const <String, String>{
          'none': 'Off',
          'interrupts': 'Interrupts',
          'normal': 'Good',
          'exact': 'Exact',
        },
        help:
            'Exact is the costliest and the truest. Interrupts is the cheap '
            'mode for a host that cannot keep up.',
        onChanged: (String v) => _update(settings.copyWith(soundOutput: v)),
      ),
      _Choice<int>(
        label: 'Rate',
        value: settings.soundFreq,
        options: const <int, String>{
          22050: '22 kHz',
          32000: '32 kHz',
          44100: '44.1 kHz',
          48000: '48 kHz',
        },
        onChanged: (int v) => _update(settings.copyWith(soundFreq: v)),
      ),
      _Choice<String>(
        label: 'Channels',
        value: settings.soundChannels,
        options: const <String, String>{
          'mono': 'Mono',
          'stereo': 'Stereo',
          '4ch': '4-channel',
          '6ch': '6-channel',
          '8ch': '8-channel',
          'mixed': 'Mixed',
        },
        onChanged: (String v) =>
            _update(settings.copyWith(soundChannels: v)),
      ),
      _Choice<int>(
        label: 'Stereo separation',
        value: settings.soundStereoSeparation,
        options: const <int, String>{
          0: 'Mono',
          4: '40%',
          7: '70%',
          10: 'Full',
        },
        help:
            'The Amiga panned two channels hard left and two hard right; '
            'full is what the hardware did and less is kinder on '
            'headphones.',
        onChanged: (int v) =>
            _update(settings.copyWith(soundStereoSeparation: v)),
      ),
      _Choice<String>(
        label: 'Interpolation',
        value: settings.soundInterpolation,
        options: const <String, String>{
          'none': 'None',
          'anti': 'Anti-aliasing',
          'sinc': 'Sinc',
          'rh': 'Crux',
          'crux': 'Crux (spline)',
        },
        onChanged: (String v) =>
            _update(settings.copyWith(soundInterpolation: v)),
      ),
    ]);
  }

  Widget _inputTab(EmulatorSettings settings) {
    return _body(<Widget>[
      _Choice<String>(
        label: 'Port 1 - the mouse port',
        value: settings.joyport0,
        options: const <String, String>{
          'mouse': 'Mouse',
          'joy0': 'Joystick',
          'kbd1': 'Keyboard layout A',
          'none': 'None',
        },
        onChanged: (String v) => _update(settings.copyWith(joyport0: v)),
      ),
      _Choice<String>(
        label: 'Port 2 - the joystick port',
        value: settings.joyport1,
        options: const <String, String>{
          'onscreen_joy': 'On-screen pad',
          'joy1': 'Joystick',
          'mouse': 'Mouse',
          'cd32joy': 'CD32 pad',
          'kbd2': 'Keyboard layout B',
          'none': 'None',
        },
        help:
            'The on-screen pad is the host overlay; the rest are emulated '
            'devices. A CD32 config gets the pad protocol regardless.',
        onChanged: (String v) => _update(settings.copyWith(joyport1: v)),
      ),
      _Switch(
        label: 'Keyboard button',
        help: 'The on-screen button that calls up the virtual keyboard.',
        value: settings.onScreenKeyboard,
        onChanged: (bool v) =>
            _update(settings.copyWith(onScreenKeyboard: v)),
      ),
    ]);
  }

}

/// A slot picker: the scanned library first, Browse underneath for
/// anything outside it. MediaChooser does the whole job; the dialog is
/// just somewhere to put it.
Future<String?> _pickMedia(
  BuildContext context,
  FileCategory category,
  String current,
) {
  return showDialog<String>(
    context: context,
    builder: (BuildContext dialogContext) => Dialog(
      child: SizedBox(
        width: 680,
        height: 520,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: MediaChooser(
            category: category,
            selected: current,
            onSelected: (String path) =>
                Navigator.of(dialogContext).pop(path),
          ),
        ),
      ),
    ),
  );
}

class _Section extends StatelessWidget {
  const _Section(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 18, 0, 6),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
          color: Theme.of(context).colorScheme.primary,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _Switch extends StatelessWidget {
  const _Switch({
    required this.label,
    required this.value,
    required this.onChanged,
    this.help,
  });

  final String label;
  final String? help;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      title: Text(label),
      subtitle: help == null ? null : Text(help!),
      value: value,
      onChanged: onChanged,
    );
  }
}

/// A row of choices rather than a dropdown: on a handheld a dropdown is a
/// second screen for something with four answers.
class _Choice<T> extends StatelessWidget {
  const _Choice({
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
    this.help,
  });

  final String label;
  final T value;
  final Map<T, String> options;
  final String? help;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(label, style: Theme.of(context).textTheme.bodyMedium),
          if (help != null)
            Padding(
              padding: const EdgeInsets.only(top: 2, bottom: 4),
              child: Text(help!, style: Theme.of(context).textTheme.bodySmall),
            ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: <Widget>[
              for (final MapEntry<T, String> option in options.entries)
                ChoiceChip(
                  label: Text(option.value),
                  selected: option.key == value,
                  onSelected: (_) => onChanged(option.key),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A file slot: the name of what is mounted, a button to pick from the
/// scanned library, an eject when something is in. The chooser is a dialog
/// because the slot is a row, not a screen.
class _FileField extends StatelessWidget {
  const _FileField({
    required this.label,
    required this.category,
    required this.value,
    required this.onChanged,
    this.help,
  });

  final String label;
  final FileCategory category;
  final String value;
  final ValueChanged<String> onChanged;
  final String? help;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      title: Text(label),
      subtitle: Text(
        value.isEmpty
            ? (help ?? 'Empty')
            : value.split(RegExp(r'[/\\]')).last,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          IconButton(
            tooltip: 'Choose',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.folder_open, size: 20),
            onPressed: () async {
              final String? picked = await _pickMedia(
                context,
                category,
                value,
              );
              if (picked != null) onChanged(picked);
            },
          ),
          if (value.isNotEmpty)
            IconButton(
              tooltip: 'Eject',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.eject, size: 20),
              onPressed: () => onChanged(''),
            ),
        ],
      ),
    );
  }
}

/// One floppy drive: its disk and its wiring. The type chips are the drive
/// itself - an ADF in a disabled drive is a disk in a drive that is not
/// there.
class _DriveRow extends StatelessWidget {
  const _DriveRow({
    required this.drive,
    required this.settings,
    required this.onChanged,
  });

  final int drive;
  final EmulatorSettings settings;
  final ValueChanged<EmulatorSettings> onChanged;

  @override
  Widget build(BuildContext context) {
    final List<String> paths = <String>[
      settings.floppy0,
      settings.floppy1,
      settings.floppy2,
      settings.floppy3,
    ];
    final List<int> types = <int>[
      settings.floppy0Type,
      settings.floppy1Type,
      settings.floppy2Type,
      settings.floppy3Type,
    ];
    final String path = paths[drive];
    final int type = types[drive];

    void setPath(String v) {
      final EmulatorSettings next = switch (drive) {
        0 => settings.copyWith(floppy0: v),
        1 => settings.copyWith(floppy1: v),
        2 => settings.copyWith(floppy2: v),
        _ => settings.copyWith(floppy3: v),
      };
      onChanged(next);
    }

    void setType(int v) {
      final EmulatorSettings next = switch (drive) {
        0 => settings.copyWith(floppy0Type: v),
        1 => settings.copyWith(floppy1Type: v),
        2 => settings.copyWith(floppy2Type: v),
        _ => settings.copyWith(floppy3Type: v),
      };
      onChanged(next);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _FileField(
          label: 'DF$drive',
          category: FileCategory.floppies,
          value: path,
          onChanged: setPath,
        ),
        Padding(
          padding: const EdgeInsets.only(left: 8, bottom: 4),
          child: Wrap(
            spacing: 6,
            runSpacing: 4,
            children: <Widget>[
              for (final MapEntry<int, String> t
                  in const <int, String>{
                    -1: 'No drive',
                    0: '3.5" DD',
                    1: '3.5" HD',
                  }.entries)
                ChoiceChip(
                  label: Text(t.value),
                  selected: type == t.key,
                  onSelected: (_) => setType(t.key),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
