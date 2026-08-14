import 'package:flutter/material.dart';

import '../data/config_parser.dart';
import '../data/config_store.dart';
import '../data/emulator_settings.dart';

/// The whole machine, on one screen.
///
/// This is what the ImGui panels did, minus the parts nobody changed. The line
/// drawn here is "settings that decide whether a game runs, or runs properly":
/// CPU and its speed, memory, the chipset, sound and the picture. Everything
/// finer - board-by-board expansion, per-chip timing, filter presets - stays
/// out, because a launcher that exposes all of it is the emulator's own
/// settings dialog with extra steps.
///
/// It edits a config file that already exists, so it starts by reading one:
/// the wizard writes, this reads back and writes over.
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
      setState(() => _settings = ConfigParser.parse(
            text,
            model: widget.config.model,
          ));
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
    final bool confirmed = await showDialog<bool>(
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

    return Scaffold(
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
      ),
      body: settings == null
          ? Center(
              child: _error == null
                  ? const CircularProgressIndicator()
                  : Text(_error!),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: <Widget>[
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                Text(
                  '${settings.baseModel.displayName} · ${settings.baseModel.description}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 12),

                _Section('Processor'),
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
                _Choice<String>(
                  label: 'Speed',
                  value: settings.cpuSpeed,
                  options: const <String, String>{
                    'real': 'As the real machine',
                    'max': 'Fastest possible',
                  },
                  help: 'Fastest suits WHDLoad and Workbench. Games written '
                      'for a stock machine often need the real speed, or they '
                      'run too quickly to play.',
                  onChanged: (String v) =>
                      _update(settings.copyWith(cpuSpeed: v)),
                ),
                _Switch(
                  label: 'Cycle exact',
                  help: 'Slower, and the only way some demos and games behave.',
                  value: settings.cycleExact,
                  onChanged: (bool v) =>
                      _update(settings.copyWith(cycleExact: v)),
                ),
                _Switch(
                  label: 'More compatible CPU',
                  help: 'Prefetch and timing as the real chip. Off is faster.',
                  value: settings.cpuCompatible,
                  onChanged: (bool v) =>
                      _update(settings.copyWith(cpuCompatible: v)),
                ),
                if (settings.cpuModel >= 68020)
                  _Switch(
                    label: 'JIT',
                    help: 'Recompiles 68020 and later. Much faster; a few '
                        'timing-sensitive titles dislike it.',
                    value: settings.jitCacheSize > 0,
                    onChanged: (bool v) => _update(settings.copyWith(
                      jitCacheSize: v ? 16384 : 0,
                      jitFpu: v,
                    )),
                  ),

                _Section('Memory'),
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
                  help: 'WHDLoad wants some. A few floppy games refuse to run '
                      'with any.',
                  onChanged: (int v) => _update(settings.copyWith(fastRam: v)),
                ),
                if (settings.cpuModel >= 68020)
                  _Choice<int>(
                    label: 'Z3 fast',
                    value: settings.z3Ram,
                    options: const <int, String>{
                      0: 'None',
                      8: '8 MB',
                      16: '16 MB',
                      32: '32 MB',
                      64: '64 MB',
                    },
                    onChanged: (int v) => _update(settings.copyWith(z3Ram: v)),
                  ),

                _Section('Chipset'),
                _Choice<String>(
                  label: 'Chipset',
                  value: settings.chipset,
                  options: const <String, String>{
                    'ocs': 'OCS',
                    'ecs': 'ECS',
                    'aga': 'AGA',
                  },
                  onChanged: (String v) =>
                      _update(settings.copyWith(chipset: v)),
                ),
                _Switch(
                  label: 'Immediate blits',
                  help: 'The blitter finishes at once. Faster, and wrong for '
                      'anything that races it.',
                  value: settings.immediateBlits,
                  onChanged: (bool v) =>
                      _update(settings.copyWith(immediateBlits: v)),
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

                _Section('Sound'),
                _Choice<int>(
                  label: 'Rate',
                  value: settings.soundFreq,
                  options: const <int, String>{
                    22050: '22 kHz',
                    32000: '32 kHz',
                    44100: '44.1 kHz',
                    48000: '48 kHz',
                  },
                  onChanged: (int v) =>
                      _update(settings.copyWith(soundFreq: v)),
                ),
                _Choice<String>(
                  label: 'Interpolation',
                  value: settings.soundInterpolation,
                  options: const <String, String>{
                    'none': 'None',
                    'anti': 'Anti-aliasing',
                    'sinc': 'Sinc',
                    'rh': 'Crux',
                  },
                  onChanged: (String v) =>
                      _update(settings.copyWith(soundInterpolation: v)),
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
                  help: 'The Amiga panned two channels hard left and two hard '
                      'right; full is what the hardware did and less is '
                      'kinder on headphones.',
                  onChanged: (int v) =>
                      _update(settings.copyWith(soundStereoSeparation: v)),
                ),

                _Section('Picture'),
                _Switch(
                  label: 'Correct aspect ratio',
                  help: '4:3, the shape the games were drawn for.',
                  value: settings.correctAspect,
                  onChanged: (bool v) =>
                      _update(settings.copyWith(correctAspect: v)),
                ),
                _Switch(
                  label: 'Drive lights',
                  value: settings.showLeds,
                  onChanged: (bool v) =>
                      _update(settings.copyWith(showLeds: v)),
                ),
              ],
            ),
    );
  }
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
              child: Text(
                help!,
                style: Theme.of(context).textTheme.bodySmall,
              ),
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
