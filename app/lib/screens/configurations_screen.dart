import 'package:flutter/material.dart';

import '../data/amiga_model.dart';
import '../data/config_store.dart';
import '../emulator.dart';
import '../theme/amiga_theme.dart';
import '../widgets/amiga_logo.dart';
import 'guided_config_screen.dart';

/// The shelf: every saved setup as a card, tap to play.
class ConfigurationsScreen extends StatefulWidget {
  const ConfigurationsScreen({super.key, this.embedded = false});

  /// True when this sits inside the workbench panel rather than being the
  /// whole screen. The workbench already shows the masthead and owns the
  /// background, so an embedded shelf drops both and keeps only the list.
  final bool embedded;

  @override
  State<ConfigurationsScreen> createState() => _ConfigurationsScreenState();
}

class _ConfigurationsScreenState extends State<ConfigurationsScreen> {
  List<SavedConfig> _configs = <SavedConfig>[];

  /// null means every machine. Only machines that actually have setups get a
  /// tab, so the row is short and never offers an empty filter.
  AmigaModel? _machine;

  List<AmigaModel> get _machinesPresent {
    final Set<AmigaModel> present = <AmigaModel>{
      for (final SavedConfig c in _configs)
        if (c.model != null) c.model!,
    };
    // In hardware order rather than the order setups happened to be made.
    return AmigaModel.values.where(present.contains).toList();
  }

  List<SavedConfig> get _visible => _machine == null
      ? _configs
      : _configs.where((SavedConfig c) => c.model == _machine).toList();
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    setState(() => _loading = true);
    try {
      final List<SavedConfig> configs = await ConfigStore.list();
      if (mounted) {
        setState(() {
          _configs = configs;
          _loading = false;
          _error = null;
        });
      }
    } on Exception catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = '$e';
        });
      }
    }
  }

  Future<void> _newSetup() async {
    final WizardMode? mode = await showModalBottomSheet<WizardMode>(
      context: context,
      showDragHandle: true,
      // Scrollable, and capped at half the screen: six options do not fit the
      // short landscape screen of a handheld, where the sheet overflowed.
      builder: (BuildContext context) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.7,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Padding(
                  padding: EdgeInsets.fromLTRB(24, 0, 24, 12),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'What are you setting up?',
                      style: TextStyle(fontSize: 18),
                    ),
                  ),
                ),
                ...WizardMode.values
                    .where((WizardMode m) => m != WizardMode.edit)
                    .map(
                      (WizardMode m) => ListTile(
                        title: Text(m.title),
                        subtitle: Text(m.blurb),
                        onTap: () => Navigator.of(context).pop(m),
                      ),
                    ),
              ],
            ),
          ),
        ),
      ),
    );
    if (mode == null || !mounted) return;

    final bool? saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(builder: (_) => GuidedConfigScreen(mode: mode)),
    );
    if (saved == true) await _reload();
  }

  Future<void> _play(SavedConfig config) async {
    try {
      // Heals paths written by a previous install before the core is handed
      // the file; see ConfigStore.repairConfigFile.
      await ConfigStore.repairConfigFile(config.path);
      await Emulator.launchConfig(
        config.path,
        whdloadArchive: config.whdloadArchive,
      );
    } on Exception catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  Future<void> _delete(SavedConfig config) async {
    await ConfigStore.delete(config.path);
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: widget.embedded ? Colors.transparent : null,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _newSetup,
        icon: const Icon(Icons.add),
        label: const Text('New setup'),
      ),
      body: SafeArea(
        // The workbench panel has already inset and clipped this.
        top: !widget.embedded,
        child: Column(
          children: <Widget>[
            if (!widget.embedded) const _Masthead(),
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
            if (!_loading && _machinesPresent.length > 1) _machineTabs(),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _configs.isEmpty
                      ? const _EmptyShelf()
                      : RefreshIndicator(
                          onRefresh: _reload,
                          child: LayoutBuilder(
                            builder: (
                              BuildContext context,
                              BoxConstraints constraints,
                            ) {
                              // Cards sized so the machine photo is worth
                              // showing; three across a handheld, more on a
                              // tablet.
                              // Small enough that a shelf of setups reads as
                              // a shelf rather than two posters.
                              final int columns =
                                  (constraints.maxWidth / 130).floor().clamp(2, 10);
                              return GridView.builder(
                                padding: const EdgeInsets.fromLTRB(14, 6, 14, 96),
                                gridDelegate:
                                    SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: columns,
                                  childAspectRatio: 1.0,
                                  crossAxisSpacing: 10,
                                  mainAxisSpacing: 10,
                                ),
                                itemCount: _visible.length,
                                itemBuilder: (BuildContext context, int i) =>
                                    _SetupCard(
                                  config: _visible[i],
                                  onPlay: () => _play(_visible[i]),
                                  onDelete: () => _delete(_visible[i]),
                                ),
                              );
                            },
                          ),
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _machineTabs() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 2),
      child: Row(
        children: <Widget>[
          _MachinePill(
            label: 'All',
            count: _configs.length,
            selected: _machine == null,
            onTap: () => setState(() => _machine = null),
          ),
          for (final AmigaModel model in _machinesPresent)
            _MachinePill(
              label: model.displayName,
              count: _configs
                  .where((SavedConfig c) => c.model == model)
                  .length,
              selected: _machine == model,
              onTap: () => setState(() => _machine = model),
            ),
        ],
      ),
    );
  }
}

/// One setup, with the machine it runs on.
///
/// A card rather than a row because a setup has a face: the machine photo says
/// at a glance whether this is the A500 disk version or the CD32 one, which is
/// the distinction that actually matters when two setups share a game's name.
class _SetupCard extends StatelessWidget {
  const _SetupCard({
    required this.config,
    required this.onPlay,
    required this.onDelete,
  });

  final SavedConfig config;
  final VoidCallback onPlay;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AmigaColors.card,
      borderRadius: BorderRadius.circular(10),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onPlay,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Expanded(
                child: Stack(
                  children: <Widget>[
                    Positioned.fill(
                      child: config.model == null
                          ? const Center(child: AmigaLogo(height: 34))
                          : Image.asset(
                              config.model!.artworkPath,
                              fit: BoxFit.contain,
                              errorBuilder: (
                                BuildContext c,
                                Object e,
                                StackTrace? s,
                              ) => const Center(child: AmigaLogo(height: 34)),
                            ),
                    ),
                    Positioned(
                      top: -8,
                      right: -8,
                      child: PopupMenuButton<String>(
                        iconSize: 18,
                        onSelected: (String action) {
                          if (action == 'delete') onDelete();
                        },
                        itemBuilder: (_) => <PopupMenuEntry<String>>[
                          const PopupMenuItem<String>(
                            value: 'delete',
                            child: Text('Delete'),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              Text(
                config.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AmigaColors.text,
                ),
              ),
              Text(
                config.summary,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 11,
                  color: AmigaColors.textDim,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MachinePill extends StatelessWidget {
  const _MachinePill({
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
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            child: Text(
              '$label  $count',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: selected ? Colors.white : AmigaColors.text,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyShelf extends StatelessWidget {
  const _EmptyShelf();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const AmigaLogo(height: 56),
            const SizedBox(height: 24),
            Text(
              'Nothing on the shelf yet',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            const Text(
              'Add a setup and it turns up here. You supply your own Kickstart '
              'ROM and games.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _Masthead extends StatelessWidget {
  const _Masthead();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
      child: Column(
        children: <Widget>[
          Image.asset(
            'assets/images/retro_recomp_logo.png',
            height: 56,
            fit: BoxFit.contain,
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              const AmigaLogo(height: 32),
              const SizedBox(width: 12),
              Text(
                'Amiga-Retro',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
