import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../data/app_log.dart';
import '../data/config_store.dart';
import '../data/save_states.dart';
import '../emulator.dart';
import '../theme/amiga_theme.dart';

/// The last five games, as they were left.
///
/// The emulator writes a save state on the way out, so these are not "recently
/// played" but "still where you left them" - which is the difference between a
/// list and something worth tapping.
class ResumePanel extends StatefulWidget {
  const ResumePanel({super.key});

  @override
  State<ResumePanel> createState() => _ResumePanelState();
}

class _ResumePanelState extends State<ResumePanel> {
  List<SaveState> _states = <SaveState>[];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final List<SaveState> states = await SaveStates.list();
    if (!mounted) return;
    setState(() {
      _states = states;
      _loading = false;
    });
  }

  /// Restores by handing the core the .uss alongside the config it came from.
  ///
  /// Both are needed: the state holds the machine's contents, the config holds
  /// which machine and which disks, and a state restored into the wrong
  /// hardware is not a game.
  Future<void> _resume(SaveState state) async {
    // Both halves named, and checked, before the core is asked for anything.
    //
    // A resume that does not resume has three possible causes -- a missing
    // snapshot, a missing config, or a restore the core refused -- and they
    // look identical from the outside: the machine boots as if fresh, or
    // sits on grey. Naming which of the two files was absent turns two of
    // those three into a one-line answer.
    final bool haveState = File(state.statePath).existsSync();
    final bool haveConfig = File(state.configPath).existsSync();
    AppLog.info(
      'resume',
      '${state.title}: state=${haveState ? 'ok' : 'MISSING'} '
          '(${state.statePath}), config=${haveConfig ? 'ok' : 'MISSING'}',
    );
    if (!haveState || !haveConfig) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              haveState
                  ? 'That setup is gone, so there is nothing to resume into.'
                  : 'The saved moment is gone. Start the game again instead.',
            ),
          ),
        );
      }
      return;
    }
    await ConfigStore.repairConfigFile(state.configPath);
    await Emulator.launch(<String>[
      '--rescan-roms',
      '--config',
      state.configPath,
      '--statefile',
      state.statePath,
      '-G',
    ]);
  }

  Future<void> _forget(SaveState state) async {
    await SaveStates.remove(state);
    if (mounted) unawaited(_load());
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());

    if (_states.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                Icons.play_circle_outline,
                size: 40,
                color: AmigaColors.textDim,
              ),
              SizedBox(height: 12),
              Text(
                'Nothing to resume',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AmigaColors.text,
                ),
              ),
              SizedBox(height: 6),
              Text(
                'Leaving a game saves where you were. The last five are kept.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AmigaColors.textDim),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: _states.length,
      separatorBuilder: (BuildContext context, int i) =>
          const SizedBox(height: 8),
      itemBuilder: (BuildContext context, int i) {
        final SaveState state = _states[i];
        return Material(
          color: AmigaColors.card,
          borderRadius: BorderRadius.circular(10),
          child: ListTile(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            leading: const Icon(
              Icons.play_circle_fill,
              size: 34,
              color: AmigaColors.tickGreen,
            ),
            title: Text(
              state.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                color: AmigaColors.text,
              ),
            ),
            subtitle: Text(
              'Left ${state.ago}',
              style: const TextStyle(fontSize: 11, color: AmigaColors.textDim),
            ),
            trailing: IconButton(
              tooltip: 'Forget',
              icon: const Icon(Icons.delete_outline),
              onPressed: () => _forget(state),
            ),
            onTap: () => _resume(state),
          ),
        );
      },
    );
  }
}
