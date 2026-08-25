import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../data/amiga_keys.dart';
import '../ffi/amiga_core.dart';
import '../ffi/amiga_texture.dart';

/// The Amiga's picture, as a widget.
///
/// This is the whole point of the in-process core: the machine renders into a
/// panel in the launcher, beside the rail and the status strip, instead of a
/// second Activity replacing the screen.
///
/// Where the platform offers one, frames go through an external texture: the
/// core's pixels are handed to the compositor and never enter the Dart heap
/// or the widget tree at all. See AmigaTexture. Everywhere else the fallback
/// path polls, uploads through `decodeImageFromPixels`, and paints the result
/// -- more expensive, but it needs nothing but Dart.
///
/// Both paths are driven by a `Ticker` rather than a `Timer`. A fixed-period
/// timer beats against vsync, so some raster passes got two uploads and
/// others none; a ticker gives exactly one poll per displayed frame, and the
/// frame serial means a poll that finds nothing new does no work at all.
///
/// Neither path rebuilds anything per frame. The picture is a `CustomPaint`
/// repainting off a notifier inside a `RepaintBoundary`, so a running Amiga
/// no longer drags the rail and the status strip through a repaint with it.
class AmigaScreenView extends StatefulWidget {
  final AmigaCore core;

  /// The shortest gap between two uploads, as a ceiling on the frame rate the
  /// fallback path will pay for. `Duration.zero` takes every frame the Amiga
  /// publishes. Ignored on the texture path, which is cheap enough not to
  /// need a ceiling.
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

class _AmigaScreenViewState extends State<AmigaScreenView>
    with SingleTickerProviderStateMixin {
  /// What the painter watches. Swapping the image on this repaints the
  /// picture and nothing else -- no `setState`, so no rebuild and no layout
  /// for the fifty frames a second the Amiga produces.
  final _FrameSource _source = _FrameSource();

  /// Flips exactly once, when the first frame lands. Only the placeholder
  /// listens, so the transition costs one rebuild for the life of a session.
  final ValueNotifier<bool> _started = ValueNotifier<bool>(false);

  late final Ticker _ticker;

  /// The external-texture path, when the platform has one. Null means the
  /// fallback: poll, upload, paint.
  AmigaTexture? _texture;
  bool _attaching = false;

  /// The Amiga's current mode on the texture path. The surface is resized by
  /// the platform as the mode changes; this is what fits it into the panel.
  Size _textureSize = Size.zero;

  bool _uploading = false;
  int _lastSerial = -1;
  Duration _lastUpload = const Duration(days: -1);

  @override
  void initState() {
    super.initState();
    _attach();
    _ticker = createTicker(_onTick)..start();
  }

  Future<void> _attach() async {
    if (!AmigaTexture.isSupported) return;
    _attaching = true;
    try {
      final AmigaTexture? texture = await AmigaTexture.create();
      if (texture == null) return;
      if (!mounted) {
        await texture.dispose();
        return;
      }
      // The texture id has to reach the tree, so this one IS a rebuild -- once
      // per session, not once per frame.
      setState(() => _texture = texture);
    } on Object {
      // Any failure here means the fallback, which needs no platform side at
      // all. Not worth a message: the picture appears either way.
    } finally {
      _attaching = false;
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    unawaited(_texture?.dispose());
    _source.dispose();
    _started.dispose();
    super.dispose();
  }

  void _onTick(Duration elapsed) {
    // Still deciding which path this is. Polling now would consume the frame
    // the texture path is about to want.
    if (_attaching) return;

    if (_texture != null) {
      // Frames are the platform's business here -- it pushes them to the
      // compositor without Dart in the loop at all. The one thing still worth
      // asking for is the shape to fit the picture into, because the Amiga
      // changes mode mid-game. Two stores behind an uncontended mutex, and it
      // only reaches the tree on the frames where the answer changed.
      final Size size = widget.core.frameSize();
      if (size != _textureSize && !size.isEmpty) {
        setState(() => _textureSize = size);
      }
      if (!_started.value && !size.isEmpty) _started.value = true;
      return;
    }

    // One upload in flight at a time. The upload is asynchronous, and piling
    // frames onto it turns a slow moment into an unbounded queue. It also
    // holds the core's staging buffer still while we read it -- see
    // AmigaFrame.pixels, which is borrowed rather than copied.
    if (_uploading) return;
    final Duration floor = widget.pollInterval;
    if (floor > Duration.zero && elapsed - _lastUpload < floor) return;

    final AmigaFrame? frame = widget.core.frame();
    if (frame == null || frame.serial == _lastSerial) return;
    _lastSerial = frame.serial;
    _lastUpload = elapsed;
    unawaited(_upload(frame));
  }

  Future<void> _upload(AmigaFrame frame) async {
    _uploading = true;
    try {
      final Completer<ui.Image> completer = Completer<ui.Image>();
      ui.decodeImageFromPixels(
        frame.pixels,
        frame.width,
        frame.height,
        // The core's surface is SDL_PIXELFORMAT_ABGR8888, which on a
        // little-endian machine is R,G,B,A in memory -- Flutter's rgba8888.
        // Decoding it as bgra8888 swaps red and blue.
        ui.PixelFormat.rgba8888,
        completer.complete,
      );
      final ui.Image image = await completer.future;
      if (!mounted) {
        image.dispose();
        return;
      }
      _source.replace(image);
      if (!_started.value) _started.value = true;
    } finally {
      _uploading = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final AmigaTexture? texture = _texture;
    // The boundary is the point: without it the picture shares a layer with
    // the rail and the status strip, and repainting at 50Hz repaints them too.
    final Widget canvas = RepaintBoundary(
      child: texture != null
          ? FittedBox(
              fit: widget.fill ? BoxFit.fill : BoxFit.contain,
              child: SizedBox(
                width: _textureSize.isEmpty
                    ? texture.width.toDouble()
                    : _textureSize.width,
                height: _textureSize.isEmpty
                    ? texture.height.toDouble()
                    : _textureSize.height,
                child: Texture(
                  textureId: texture.id,
                  filterQuality: FilterQuality.none,
                ),
              ),
            )
          : CustomPaint(
              painter: _FramePainter(source: _source, fill: widget.fill),
              size: Size.infinite,
              isComplex: true,
              willChange: true,
            ),
    );
    final Widget picture = Stack(
      fit: StackFit.expand,
      children: <Widget>[
        canvas,
        // Rebuilt on the null-to-first-frame transition and never again.
        ValueListenableBuilder<bool>(
          valueListenable: _started,
          builder: (BuildContext context, bool started, Widget? child) =>
              started ? const SizedBox.shrink() : child!,
          child: const Center(
            child: Text(
              'Starting the Amiga...',
              style: TextStyle(color: Colors.white38, fontSize: 12),
            ),
          ),
        ),
      ],
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

/// Holds the frame the painter draws, and says when it changes.
///
/// A `ChangeNotifier` rather than widget state so a new frame is a repaint and
/// not a rebuild: `CustomPainter` takes this as its `repaint`, which walks
/// straight to the render object.
class _FrameSource extends ChangeNotifier {
  ui.Image? image;

  /// Takes ownership of [next] and releases the frame it replaces. The old
  /// image is disposed only after the swap, so a raster pass already holding
  /// it keeps a valid handle.
  void replace(ui.Image next) {
    final ui.Image? previous = image;
    image = next;
    notifyListeners();
    previous?.dispose();
  }

  @override
  void dispose() {
    image?.dispose();
    image = null;
    super.dispose();
  }
}

/// Draws the current frame, scaled to the panel.
///
/// `paintImage` rather than the `FittedBox` + `RawImage` this replaced: the
/// old pair re-ran layout every time the Amiga changed mode, and mode changes
/// are something the Amiga does mid-game.
class _FramePainter extends CustomPainter {
  final _FrameSource source;
  final bool fill;

  const _FramePainter({required this.source, required this.fill})
    : super(repaint: source);

  @override
  void paint(Canvas canvas, Size size) {
    final ui.Image? image = source.image;
    if (image == null || size.isEmpty) return;
    paintImage(
      canvas: canvas,
      rect: Offset.zero & size,
      image: image,
      // The Amiga's pixels are the artwork. Smoothing them is the difference
      // between a chunky screen and a blurred one.
      filterQuality: FilterQuality.none,
      fit: fill ? BoxFit.fill : BoxFit.contain,
    );
  }

  @override
  bool shouldRepaint(_FramePainter old) =>
      old.fill != fill || old.source != source;
}
