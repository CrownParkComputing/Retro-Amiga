import 'package:flutter/material.dart';

import '../data/app_prefs.dart';
import '../data/music_player.dart';
import '../theme/amiga_theme.dart';
import 'settings_panel.dart';

/// Sound, app-wide: the workbench music. The machine's own sound (output,
/// rate, stereo separation, interpolation) is per config.
class AudioPanel extends StatefulWidget {
  const AudioPanel({super.key});

  @override
  State<AudioPanel> createState() => _AudioPanelState();
}

class _AudioPanelState extends State<AudioPanel> {
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
        const SettingsHeader('Per machine'),
        const Card(
          color: AmigaColors.card,
          child: ListTile(
            leading: Icon(Icons.tune),
            title: Text('Output, rate, stereo, interpolation'),
            subtitle: Text(
              'Set per config, in its Sound section: Configs, long-press, '
              'Edit.',
            ),
          ),
        ),
      ],
    );
  }
}
