import 'dart:async';

import 'package:flutter/services.dart';

/// What the native player is doing right now.
class MusicState {
  const MusicState({
    this.playing = false,
    this.paused = false,
    this.title = '',
    this.level = 0,
  });

  final bool playing;
  final bool paused;

  /// The name the composer typed into the module, which is often not the
  /// filename and is usually better.
  final String title;

  /// Peak level 0..1 of the last block mixed, for the equaliser.
  final double level;

  static MusicState fromMap(Map<Object?, Object?> map) => MusicState(
    playing: map['playing'] as bool? ?? false,
    paused: map['paused'] as bool? ?? false,
    title: map['title'] as String? ?? '',
    level: (map['level'] as num?)?.toDouble() ?? 0,
  );
}

/// The launcher's music.
///
/// The replayer is native - src/osdep/protracker.cpp - because it has to keep
/// feeding an audio device on time, which is not something to ask of the
/// Dart isolate that is also drawing the UI. Dart starts and stops tunes and
/// polls for the level; it never touches a sample.
class MusicPlayer {
  const MusicPlayer._();

  static const MethodChannel _channel = MethodChannel('uae4arm2026/emulator');

  /// Broadcast so the music screen and the workbench equaliser can both listen
  /// without one cancelling the other's subscription.
  static final StreamController<MusicState> _states =
      StreamController<MusicState>.broadcast();

  static Timer? _poll;
  static MusicState _last = const MusicState();

  static Stream<MusicState> get states => _states.stream;
  static MusicState get state => _last;

  /// Starts [path]. Whatever was playing stops. Returns false if the host
  /// could not read the file or it is not a module.
  static Future<bool> play(String path) async {
    _silencedByUser = false;
    final bool ok = await _invoke<bool>('musicPlay', <String, Object?>{
          'path': path,
        }) ??
        false;
    if (ok) _startPolling();
    return ok;
  }

  static Future<void> stop({bool byUser = true}) async {
    _silencedByUser = byUser;
    await _invoke<void>('musicStop');
    _stopPolling();
    _emit(const MusicState());
  }

  static Future<void> setPaused(bool paused) async {
    await _invoke<void>('musicSetPaused', <String, Object?>{'paused': paused});
    await refresh();
  }

  static Future<void> setVolume(double volume) async {
    await _invoke<void>('musicSetVolume', <String, Object?>{'volume': volume});
  }

  /// Asks the host what it is actually doing, rather than trusting what we
  /// last told it: a tune can end on its own.
  static Future<MusicState> refresh() async {
    final Map<Object?, Object?>? raw =
        await _invoke<Map<Object?, Object?>>('musicState');
    final MusicState state =
        raw == null ? const MusicState() : MusicState.fromMap(raw);
    _emit(state);
    return state;
  }

  static void _emit(MusicState state) {
    _last = state;
    if (!_states.isClosed) _states.add(state);
  }

  /// 100ms is fast enough for a level meter to look alive and slow enough that
  /// the channel traffic does not matter.
  static void _startPolling() {
    _poll ??= Timer.periodic(
      const Duration(milliseconds: 100),
      (_) => refresh(),
    );
  }

  static void _stopPolling() {
    _poll?.cancel();
    _poll = null;
  }

  /// True once the user has stopped the music themselves, so the workbench
  /// does not start another tune over their decision.
  static bool _silencedByUser = false;
  static bool get silencedByUser => _silencedByUser;

  /// Plays one of [tunes] at random, unless something is already playing or
  /// the user has stopped it.
  ///
  /// Random rather than the first: the workbench is where you spend the time
  /// between games, and hearing the same tune every time you open it is what
  /// makes people turn music off.
  static Future<void> playRandom(List<String> tunes) async {
    if (tunes.isEmpty || _silencedByUser) return;
    if (_last.playing) return;
    final int index = DateTime.now().microsecondsSinceEpoch % tunes.length;
    await play(tunes[index]);
  }

  /// Silences without forgetting the tune, for leaving the app. Not stop():
  /// coming back to silence and having to find the track again is worse than
  /// coming back to where it was.
  static Future<void> suspend() async {
    if (_last.playing && !_last.paused) await setPaused(true);
    _stopPolling();
  }

  static Future<void> resumeIfSuspended() async {
    if (_silencedByUser) return;
    final MusicState state = await refresh();
    if (state.playing && state.paused) await setPaused(false);
  }

  /// A host that does not implement music must not take the app down with it -
  /// desktop has no handler yet, and the launcher still has to run there.
  static Future<T?> _invoke<T>(String method, [Object? arguments]) async {
    try {
      return await _channel.invokeMethod<T>(method, arguments);
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }
}
