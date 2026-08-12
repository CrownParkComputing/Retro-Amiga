import 'package:flutter/material.dart';

import '../data/config_store.dart';
import '../emulator.dart';
import '../widgets/amiga_logo.dart';
import 'guided_config_screen.dart';

/// The shelf: every saved setup as a card, tap to play.
class ConfigurationsScreen extends StatefulWidget {
  const ConfigurationsScreen({super.key});

  @override
  State<ConfigurationsScreen> createState() => _ConfigurationsScreenState();
}

class _ConfigurationsScreenState extends State<ConfigurationsScreen> {
  List<SavedConfig> _configs = <SavedConfig>[];
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
      await Emulator.launchConfig(config.path);
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
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _newSetup,
        icon: const Icon(Icons.add),
        label: const Text('New setup'),
      ),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            const _Masthead(),
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
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _configs.isEmpty
                  ? const _EmptyShelf()
                  : RefreshIndicator(
                      onRefresh: _reload,
                      child: ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
                        itemCount: _configs.length,
                        itemBuilder: (BuildContext context, int i) {
                          final SavedConfig config = _configs[i];
                          return Card(
                            child: ListTile(
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 8,
                              ),
                              leading: SizedBox(
                                width: 88,
                                height: 56,
                                child: config.model == null
                                    ? const AmigaLogo(height: 28)
                                    : Image.asset(
                                        config.model!.artworkPath,
                                        fit: BoxFit.contain,
                                        errorBuilder:
                                            (
                                              BuildContext c,
                                              Object e,
                                              StackTrace? s,
                                            ) => const AmigaLogo(height: 28),
                                      ),
                              ),
                              title: Text(config.name),
                              subtitle: Text(
                                '${config.model?.displayName ?? 'Unknown machine'} · ${config.summary}',
                              ),
                              trailing: PopupMenuButton<String>(
                                onSelected: (String action) {
                                  if (action == 'delete') _delete(config);
                                },
                                itemBuilder: (_) => <PopupMenuEntry<String>>[
                                  const PopupMenuItem<String>(
                                    value: 'delete',
                                    child: Text('Delete'),
                                  ),
                                ],
                              ),
                              onTap: () => _play(config),
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
