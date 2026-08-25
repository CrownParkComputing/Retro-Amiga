import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

/// The Amiga's picture as a surface the compositor owns.
///
/// The panel's original path copied every frame four times -- native staging
/// buffer, Dart allocation, `decodeImageFromPixels`, GPU upload -- which at
/// 752x576 is nearly 7MB of copying per frame and is why the Android panel had
/// to be capped at 30fps to leave the audio callback any room. An external
/// texture replaces all of it with one memcpy, straight from the emulator's
/// front buffer into the buffer the compositor is about to read.
///
/// Frames are pushed by the platform, not by Dart. On Android a Choreographer
/// callback calls into the native side once per vsync; nothing about a frame
/// crosses a platform channel or enters the Dart heap. This class exists only
/// to start that loop, carry the texture id into the widget tree, and stop it
/// again -- three messages for a whole session.
///
/// Everything here is best-effort. A platform with no producer, or a core
/// built before host_texture.cpp existed, simply returns null from [create],
/// and AmigaScreenView falls back to copy-and-decode with nothing to
/// configure.
class AmigaTexture {
  static const MethodChannel _channel = MethodChannel('uae4arm2026/texture');

  /// The texture id to hand to a `Texture` widget.
  final int id;

  /// The surface's size when it was created. The platform resizes it as the
  /// Amiga changes mode, so this is a starting point rather than the truth --
  /// ask AmigaCore.frameSize for what is on screen now.
  final int width;
  final int height;

  bool _disposed = false;

  AmigaTexture._({required this.id, required this.width, required this.height});

  /// Whether it is worth asking. Desktop builds have no producer, and asking
  /// there costs a channel round trip and a MissingPluginException per
  /// session.
  static bool get isSupported => Platform.isAndroid || Platform.isIOS;

  /// Registers a texture and starts the platform's frame loop, or returns null
  /// if this platform or this core cannot do it.
  static Future<AmigaTexture?> create() async {
    if (!isSupported) return null;
    try {
      final Map<Object?, Object?>? reply = await _channel
          .invokeMapMethod<Object?, Object?>('create');
      if (reply == null) return null;
      final int? id = (reply['id'] as num?)?.toInt();
      if (id == null) return null;
      return AmigaTexture._(
        id: id,
        width: (reply['width'] as num?)?.toInt() ?? 0,
        height: (reply['height'] as num?)?.toInt() ?? 0,
      );
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  /// Stops the frame loop and releases the surface. Idempotent: the panel is
  /// torn down from more than one place.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    try {
      await _channel.invokeMethod<void>('dispose');
    } on PlatformException {
      // Already gone. Nothing left to release.
    } on MissingPluginException {
      // Ditto.
    }
  }
}
