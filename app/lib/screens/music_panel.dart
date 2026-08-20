import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../data/file_category.dart';
import '../data/media_library.dart';
import '../data/music_picks.dart';
import '../data/music_player.dart';
import '../theme/amiga_theme.dart';

/// The music panel: the ten demo tunes and ten game soundtracks worth having.
///
/// The two shelves are the point. A list of every module on a device buries
/// the useful soundtrack list, so only the curated picks appear here. The
/// Files page remains the complete local file manager.
///
/// Nothing is bundled: these are other people's compositions, and the archives
/// that host them - Aminet, The Mod Archive, Modland - are a download away.
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
  StreamSubscription<MediaIndex>? _mediaChanges;
  double _volume = 0.7;

  @override
  void initState() {
    super.initState();
    _sub = MusicPlayer.states.listen((MusicState state) {
      if (mounted) setState(() => _state = state);
    });
    _mediaChanges = MediaLibrary.changes.listen(_applyIndex);
    _load();
    MusicPlayer.refresh();
  }

  @override
  void dispose() {
    _sub?.cancel();
    _mediaChanges?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    MediaIndex index = await MediaLibrary.cached();
    if (index.files.isEmpty) index = await MediaLibrary.scan();
    if (!mounted) return;
    _applyIndex(index);
  }

  void _applyIndex(MediaIndex index) {
    final List<MediaFile> tunes =
        index.files
            .where(
              (MediaFile f) =>
                  f.category == FileCategory.music &&
                  MusicPicks.all.any((MusicPick p) => p.matches(f.name)),
            )
            .toList()
          ..sort(
            (MediaFile a, MediaFile b) =>
                a.title.toLowerCase().compareTo(b.title.toLowerCase()),
          );
    if (!mounted) return;
    setState(() {
      _tunes = tunes;
      _loading = false;
    });
  }

  /// The file on this device for [pick], if there is one.
  MediaFile? _fileFor(MusicPick pick) {
    for (final MediaFile tune in _tunes) {
      if (pick.matches(tune.name)) return tune;
    }
    return null;
  }

  Future<void> _play(MediaFile tune) async {
    if (_playingPath == tune.path && _state.playing) {
      await MusicPlayer.setPaused(!_state.paused);
      return;
    }
    final bool ok = await MusicPlayer.play(tune.path);
    if (!mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('${tune.name} would not play.')));
      return;
    }
    setState(() => _playingPath = tune.path);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());

    return Column(
      children: <Widget>[
        _statusBar(),
        const Divider(height: 1, color: AmigaColors.panelBorder),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.only(bottom: 16),
            children: <Widget>[
              for (final MusicShelf shelf in MusicShelf.values) ...<Widget>[
                _ShelfHeader(shelf: shelf, found: _foundIn(shelf)),
                for (final MusicPick pick in MusicPicks.of(shelf))
                  _pickTile(pick),
              ],
            ],
          ),
        ),
      ],
    );
  }

  int _foundIn(MusicShelf shelf) =>
      MusicPicks.of(shelf).where((MusicPick p) => _fileFor(p) != null).length;

  Widget _pickTile(MusicPick pick) {
    final MediaFile? file = _fileFor(pick);
    final bool present = file != null;
    final bool isCurrent =
        present && file.path == _playingPath && _state.playing;

    return ListTile(
      dense: true,
      enabled: present,
      leading: Icon(
        isCurrent
            ? (_state.paused ? Icons.pause_circle : Icons.graphic_eq)
            : present
            ? Icons.play_circle_outline
            : Icons.download_outlined,
        color: isCurrent
            ? AmigaColors.accent
            : present
            ? AmigaColors.text
            : AmigaColors.textDim.withValues(alpha: 0.5),
      ),
      title: Text(
        pick.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: isCurrent
              ? AmigaColors.accent
              : present
              ? AmigaColors.text
              : AmigaColors.textDim.withValues(alpha: 0.6),
          fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w500,
        ),
      ),
      subtitle: Text(
        present ? pick.credit : '${pick.credit}  ·  not on this device',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 11,
          color: AmigaColors.textDim.withValues(alpha: present ? 1.0 : 0.5),
        ),
      ),
      onTap: present ? () => _play(file) : null,
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
                _LevelMeter(
                  level: playing && !_state.paused ? _state.level : 0,
                ),
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
  /// not - plenty were saved with the name field blank.
  String _titleOf(MusicState state) {
    if (state.title.trim().isNotEmpty) return state.title.trim();
    for (final MediaFile tune in _tunes) {
      if (tune.path == _playingPath) return tune.title;
    }
    return 'Playing';
  }
}

class _ShelfHeader extends StatelessWidget {
  const _ShelfHeader({required this.shelf, required this.found});

  final MusicShelf shelf;
  final int found;

  @override
  Widget build(BuildContext context) {
    final int total = MusicPicks.of(shelf).length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: <Widget>[
          Text(
            shelf.title,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AmigaColors.accent,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              shelf.blurb,
              style: const TextStyle(fontSize: 11, color: AmigaColors.textDim),
            ),
          ),
          Text(
            '$found of $total',
            style: const TextStyle(fontSize: 11, color: AmigaColors.textDim),
          ),
        ],
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
  static const double _height = 10;

  @override
  Widget build(BuildContext context) {
    // Square-rooted: peak level sits low most of the time, and a linear meter
    // barely moves off the floor.
    final double scaled = level <= 0 ? 0 : math.sqrt(level);

    return SizedBox(
      height: _height,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: <Widget>[
          for (int i = 0; i < _bars; i++)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(right: 2),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 110),
                  height: (_height * scaled * (1 - i / (_bars * 1.5))).clamp(
                    1.0,
                    _height,
                  ),
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
