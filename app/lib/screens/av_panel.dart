import 'package:flutter/material.dart';

import '../data/app_prefs.dart';
import '../data/music_player.dart';
import '../theme/amiga_theme.dart';
import 'settings_panel.dart';

/// Picture and sound, app-wide.
///
/// One page, where there were two rail entries with a card each. Both were
/// thin -- a switch on one, a slider on the other -- and both ended with the
/// SAME "the machine's own settings are per config" card, so the rail asked
/// the user to choose between two places that each said "not here". Together
/// they are one page you can read at a glance, one pointer at the config
/// editor instead of two, and one fewer entry in a rail that has to fit on a
/// phone.
///
/// The split that matters is not video/audio, it is app-wide versus per
/// machine: what the launcher does with the picture and the workbench music
/// lives here, and resolution, aspect, output rate and interpolation belong
/// to the config that names the machine.
class AvPanel extends StatefulWidget {
  const AvPanel({super.key});

  @override
  State<AvPanel> createState() => _AvPanelState();
}

class _AvPanelState extends State<AvPanel> {
  double _volume = 1;

  @override
  void initState() {
    super.initState();
    AppPrefs.musicVolume().then((double v) {
      if (mounted) setState(() => _volume = v);
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(14),
      children: <Widget>[
        const SettingsHeader('Screen'),
        Card(
          color: AmigaColors.card,
          child: ValueListenableBuilder<bool>(
            valueListenable: AppPrefs.screenFill,
            builder: (BuildContext context, bool fill, _) => SwitchListTile(
              secondary: const Icon(Icons.aspect_ratio),
              title: const Text('Fill the screen (16:9)'),
              subtitle: const Text(
                'Stretch the Amiga picture over the whole panel instead of '
                'keeping its shape with bars either side.',
              ),
              value: fill,
              onChanged: (bool v) => AppPrefs.setScreenFill(value: v),
            ),
          ),
        ),
        const SettingsHeader('On-screen controls'),
        Card(
          color: AmigaColors.card,
          child: Column(
            children: <Widget>[
              ValueListenableBuilder<bool>(
                valueListenable: AppPrefs.showPad,
                builder: (BuildContext context, bool on, _) => SwitchListTile(
                  secondary: const Icon(Icons.videogame_asset),
                  title: const Text('On-screen pad'),
                  subtitle: const Text(
                    'A stick and buttons drawn over the game. Hidden '
                    'automatically whenever a real controller is connected, '
                    'whatever this says.',
                  ),
                  value: on,
                  onChanged: (bool v) => AppPrefs.setShowPad(value: v),
                ),
              ),
              ValueListenableBuilder<bool>(
                valueListenable: AppPrefs.showKeyboard,
                builder: (BuildContext context, bool on, _) => SwitchListTile(
                  secondary: const Icon(Icons.keyboard),
                  title: const Text('On-screen keyboard'),
                  subtitle: const Text(
                    'The Amiga keyboard over the game. For Workbench and '
                    'anything that asks you to type; most games want the '
                    'stick instead.',
                  ),
                  value: on,
                  onChanged: (bool v) => AppPrefs.setShowKeyboard(value: v),
                ),
              ),
            ],
          ),
        ),
        const SettingsHeader('Workbench music'),
        Card(
          color: AmigaColors.card,
          child: ListTile(
            leading: Icon(_volume == 0 ? Icons.volume_off : Icons.volume_up),
            title: const Text('Volume'),
            subtitle: Slider(
              value: _volume,
              onChanged: (double v) {
                setState(() => _volume = v);
                MusicPlayer.setVolume(v);
              },
              onChangeEnd: (double v) => AppPrefs.setMusicVolume(v),
            ),
          ),
        ),
      ],
    );
  }
}
