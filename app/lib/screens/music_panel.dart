import 'dart:async';

import 'package:flutter/material.dart';

import '../data/file_category.dart';
import '../data/media_library.dart';
import '../data/music_player.dart';
import '../theme/amiga_theme.dart';

/// Every module the scan found, and a player for them.
///
/// The tunes are whatever is on the device. Nothing ships with the app:
/// modules are their composers' work, and the good collections - Aminet, the
/// Mod Archive - are a download away and belong to the person who made them.
class MusicPanel extends StatefulWidget {
  const MusicPanel({super.key});

  @override
  State<MusicPanel> createState() => _MusicPanelState();
}

class _MusicPanelState extends State<MusicPanel> {
  List<MediaFile> _tunes = <MediaFile>[];
  bool _loading = true;
  String? _playingPath;
  MusicState _state = MusicPlayer.state;
  StreamSubscription<MusicState>? _sub;
  double _volume = 0.7;

  @override
  void initState() {
    super.initState();
    _sub = MusicPlayer.states.listen((MusicState state) {
      if (mounted) setState(() => _state = state);
    });
    _load();
    MusicPlayer.refresh();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final MediaIndex index = await MediaLibrary.cached();
    if (!mounted) return;
    setState(() {
      _tunes = index.files
          .where((MediaFile f) => f.category == FileCategory.music)
          .toList()
        ..sort((MediaFile a, MediaFile b) =>
            a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      _loading = false;
    });
  }

  Future<void> _tap(MediaFile tune) async {
    // Tapping the tune that is already playing toggles it, which is what a
    // second tap on a playing track means everywhere else.
    if (_playingPath == tune.path && _state.playing) {
      await MusicPlayer.setPaused(!_state.paused);
      return;
    }
    final bool ok = await MusicPlayer.play(tune.path);
    if (!mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${tune.name} would not play.')),
      );
      return;
    }
    setState(() => _playingPath = tune.path);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      children: <Widget>[
        _statusBar(),
        const Divider(height: 1, color: AmigaColors.panelBorder),
        Expanded(
          child: _tunes.isEmpty ? _empty() : _list(),
        ),
      ],
    );
  }

  Widget _statusBar() {
    final bool playing = _state.playing;
    final String label = !playing
        ? 'Nothing playing'
        : _state.paused
            ? 'Paused - ${_titleOf(_state)}'
            : _titleOf(_state);

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Row(
        children: <Widget>[
          IconButton(
            onPressed: playing
                ? () => MusicPlayer.setPaused(!_state.paused)
                : null,
            icon: Icon(
              _state.paused || !playing ? Icons.play_arrow : Icons.pause,
            ),
          ),
          IconButton(
            onPressed: playing
                ? () {
                    MusicPlayer.stop();
                    setState(() => _playingPath = null);
                  }
                : null,
            icon: const Icon(Icons.stop),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    color: AmigaColors.text,
                  ),
                ),
                const SizedBox(height: 5),
                _LevelMeter(level: playing && !_state.paused ? _state.level : 0),
              ],
            ),
          ),
          SizedBox(
            width: 120,
            child: Slider(
              value: _volume,
              onChanged: (double value) {
                setState(() => _volume = value);
                MusicPlayer.setVolume(value);
              },
            ),
          ),
        ],
      ),
    );
  }

  /// The module's internal title where it has one, the filename where it does
  /// not - plenty of modules were saved with the name field blank.
  String _titleOf(MusicState state) {
    if (state.title.trim().isNotEmpty) return state.title.trim();
    final MediaFile? file = _playingPath == null
        ? null
        : _tunes.where((MediaFile f) => f.path == _playingPath).firstOrNull;
    return file?.name ?? 'Playing';
  }

  Widget _list() {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 6),
      itemCount: _tunes.length,
      itemBuilder: (BuildContext context, int i) {
        final MediaFile tune = _tunes[i];
        final bool isCurrent = tune.path == _playingPath && _state.playing;
        return ListTile(
          dense: true,
          leading: Icon(
            isCurrent
                ? (_state.paused ? Icons.pause_circle : Icons.graphic_eq)
                : Icons.music_note_outlined,
            color: isCurrent ? AmigaColors.accent : AmigaColors.textDim,
          ),
          title: Text(
            tune.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: isCurrent ? AmigaColors.accent : AmigaColors.text,
              fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
          subtitle: Text(
            tune.folder,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: AmigaColors.textDim, fontSize: 11),
          ),
          onTap: () => _tap(tune),
        );
      },
    );
  }

  Widget _empty() {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.music_off_outlined, size: 40, color: AmigaColors.textDim),
            SizedBox(height: 12),
            Text(
              'No modules found',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AmigaColors.text,
              ),
            ),
            SizedBox(height: 6),
            Text(
              'Put .mod files on the device and scan again.\n'
              'Names in the Amiga style - mod.axel_f - are found too.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AmigaColors.textDim),
            ),
          ],
        ),
      ),
    );
  }
}

/// A row of bars driven by the peak level.
///
/// Not a spectrum - the native side reports one number, not a set of bands -
/// so the bars are a decaying trail of it rather than a lie about frequency
/// content.
class _LevelMeter extends StatelessWidget {
  const _LevelMeter({required this.level});

  final double level;

  static const int _bars = 24;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 8,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: <Widget>[
          for (int i = 0; i < _bars; i++)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(right: 2),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 110),
                  height: (8 * level * (1 - i / (_bars * 1.6))).clamp(1.0, 8.0),
                  decoration: BoxDecoration(
                    color: Color.lerp(
                      AmigaColors.tickGreen,
                      AmigaColors.accent,
                      i / _bars,
                    ),
                    borderRadius: BorderRadius.circular(1),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
