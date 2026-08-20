import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/amiga_keys.dart';
import '../ffi/amiga_core.dart';

/// The Amiga's picture, as a widget.
///
/// This is the whole point of the in-process core: the machine renders into a
/// panel in the launcher, beside the rail and the status strip, instead of a
/// second Activity replacing the screen.
///
/// Frames are polled and decoded rather than handed to a Flutter `Texture`.
/// That costs an upload per frame and is the same first-pass trade Retro-C64
/// made; a real external texture is the next improvement, not a different
/// design. The frame serial means a poll that finds nothing new does no work
/// at all.
class AmigaScreenView extends StatefulWidget {
  final AmigaCore core;
  final Duration pollInterval;

  /// Stretch the picture over the whole panel instead of keeping the Amiga's
  /// shape. On a 16:9 phone that is the difference between bars and no bars.
  final bool fill;

  /// Treat touches as the Amiga mouse: drag moves it, tap clicks, a long press
  /// is the right button.
  final bool mouseMode;

  const AmigaScreenView({
    super.key,
    required this.core,
    this.pollInterval = const Duration(milliseconds: 20),
    this.fill = false,
    this.mouseMode = false,
  });

  @override
  State<AmigaScreenView> createState() => _AmigaScreenViewState();
}

class _AmigaScreenViewState extends State<AmigaScreenView> {
  ui.Image? _image;
  Timer? _timer;
  bool _decoding = false;
  int _lastSerial = -1;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(widget.pollInterval, (_) => _tick());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _image?.dispose();
    super.dispose();
  }

  Future<void> _tick() async {
    // One decode in flight at a time: the decoder is asynchronous and piling
    // frames onto it turns a slow moment into an unbounded queue.
    if (_decoding) return;
    final frame = widget.core.frame();
    if (frame == null || frame.serial == _lastSerial) return;
    _decoding = true;
    _lastSerial = frame.serial;
    try {
      final completer = Completer<ui.Image>();
      ui.decodeImageFromPixels(
        frame.pixels.buffer.asUint8List(),
        frame.width,
        frame.height,
        // The core's surface is SDL_PIXELFORMAT_ABGR8888, which on a
        // little-endian machine is R,G,B,A in memory -- Flutter's rgba8888.
        // Decoding it as bgra8888 swaps red and blue.
        ui.PixelFormat.rgba8888,
        completer.complete,
      );
      final image = await completer.future;
      if (!mounted) {
        image.dispose();
        return;
      }
      setState(() {
        _image?.dispose();
        _image = image;
      });
    } finally {
      _decoding = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final image = _image;
    if (image == null) {
      return const Center(
        child: Text(
          'Starting the Amiga...',
          style: TextStyle(color: Colors.white38, fontSize: 12),
        ),
      );
    }
    final Widget picture = FittedBox(
      fit: widget.fill ? BoxFit.fill : BoxFit.contain,
      child: SizedBox(
        width: image.width.toDouble(),
        height: image.height.toDouble(),
        child: RawImage(image: image, filterQuality: FilterQuality.none),
      ),
    );
    // A real keyboard, wherever there is one: the desktop always, a phone
    // when one is paired. Physical keys, because the Amiga is a matrix.
    final Widget keyed = Focus(
      autofocus: true,
      onKeyEvent: (FocusNode node, KeyEvent event) {
        // The Amiga does its own key repeat; forwarding the host's makes
        // every held key stutter.
        if (event is KeyRepeatEvent) return KeyEventResult.handled;
        final int? code = AmigaKeys.fromPhysical(event.physicalKey);
        if (code == null) return KeyEventResult.ignored;
        widget.core.sendKey(code, event is KeyDownEvent);
        return KeyEventResult.handled;
      },
      child: picture,
    );
    if (!widget.mouseMode) return keyed;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanUpdate: (DragUpdateDetails d) {
        // Relative, like a trackpad. A touch pixel is roughly a screen pixel;
        // 1.5x makes Workbench crossable in one swipe on a phone.
        _carryX += d.delta.dx * 1.5;
        _carryY += d.delta.dy * 1.5;
        final int dx = _carryX.truncate();
        final int dy = _carryY.truncate();
        if (dx != 0 || dy != 0) {
          _carryX -= dx;
          _carryY -= dy;
          widget.core.mouseMove(dx, dy);
        }
      },
      onTap: () => _click(0),
      onLongPress: () => _click(1),
      child: keyed,
    );
  }

  double _carryX = 0;
  double _carryY = 0;

  Future<void> _click(int button) async {
    widget.core.mouseButton(button, true);
    // The Amiga samples the button per frame; an instant release can miss.
    await Future<void>.delayed(const Duration(milliseconds: 60));
    widget.core.mouseButton(button, false);
  }
}
