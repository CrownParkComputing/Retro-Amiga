import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../data/amiga_keys.dart';
import '../data/app_log.dart';
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
  /// FALLBACK path will pay for. `Duration.zero` takes every frame the Amiga
  /// publishes; the texture path ignores it entirely, being one memcpy rather
  /// than an upload.
  ///
  /// Defaulted rather than passed in, and the default is deliberately the
  /// cautious one. The caller cannot know which path this widget ended up on
  /// -- the texture is asked for asynchronously and may be refused by the
  /// platform or by an older core -- so a caller that picked the ceiling from
  /// `AmigaTexture.isSupported` would leave Android uncapped in exactly the
  /// case where the cap still mattered.
  final Duration? pollInterval;

  /// Stretch the picture over the whole panel instead of keeping the Amiga's
  /// shape. On a 16:9 phone that is the difference between bars and no bars.
  final bool fill;

  /// The shape an Amiga picture is meant to be, whatever its pixel count.
  ///
  /// Amiga pixels are not square and their proportions change with the mode:
  /// lores is 320x256, hires 640x256, PAL hires interlaced 752x576. All of
  /// them were displayed on the same 4:3 screen, so the pixel counts are not
  /// the shape -- 640x256 is 2.5:1 as numbers and 4:3 as a picture.
  ///
  /// Fitting by pixel count is what this used to do, and it is the "problems
  /// with stretching video for other formats" report: hires interlaced came
  /// out close enough to look right (1.31 against 1.33) and every other mode
  /// came out visibly wrong, tall in lores and flat in hires. Correcting to
  /// a fixed 4:3 is what WinUAE and Amiberry both call correct aspect, and it
  /// is right for PAL and NTSC alike.
  static const double displayAspect = 4 / 3;

  /// The fallback path's frame-rate ceiling.
  ///
  /// Only reached where there is no external texture. Android gets the
  /// stricter figure for the reason it always did: a full upload per frame
  /// starves the audio callback on modest hardware, and torn sound is worse
  /// than a slightly coarser picture. Where the texture path works -- which
  /// is now the normal case on both mobile platforms -- neither figure
  /// applies.
  static final Duration _fallbackFloor = Platform.isAndroid
      ? const Duration(milliseconds: 33)
      : const Duration(milliseconds: 20);

  /// Treat touches as the Amiga mouse: drag moves it, tap clicks, a long press
  /// is the right button.
  final bool mouseMode;

  const AmigaScreenView({
    super.key,
    required this.core,
    this.pollInterval,
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

  /// The texture path, once given up on, is not tried again this session.
  bool _textureRefused = false;

  /// How many ticks have gone by with the core publishing frames, the texture
  /// path attached, and nothing reaching the compositor. See [_watchTexture].
  int _texturePostedNothing = 0;

  /// The last serials seen from each side, so "is it still delivering" is a
  /// comparison rather than a guess.
  int _lastPostedSerial = -1;
  int _lastPublishedSerial = -1;

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
    if (!AmigaTexture.isSupported || _textureRefused) return;
    _attaching = true;
    try {
      final AmigaTexture? texture = await AmigaTexture.create();
      if (texture == null) {
        // Which path the picture is on decides everything about its cost: the
        // texture is one memcpy on the platform thread, the fallback is a
        // full decode on the UI thread for every frame. At an RTG
        // resolution that is the difference between a running app and one
        // that cannot be touched.
        AppLog.warn('picture', 'no external texture; using copy-and-decode');
        return;
      }
      AppLog.info('picture', 'external texture ${texture.id} attached');
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
    _holdTimer?.cancel();
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
      // compositor without Dart in the loop at all, and the picture is drawn
      // into a fixed 4:3 box, so a mode change needs nothing from this side.
      // All that is left is watching that it IS happening, and noticing the
      // first frame to take the placeholder down.
      if (!_watchTexture()) return;
      if (!_started.value && !widget.core.frameSize().isEmpty) {
        _started.value = true;
      }
      return;
    }

    // One upload in flight at a time. The upload is asynchronous, and piling
    // frames onto it turns a slow moment into an unbounded queue. It also
    // holds the core's staging buffer still while we read it -- see
    // AmigaFrame.pixels, which is borrowed rather than copied.
    if (_uploading) return;
    final Duration floor = widget.pollInterval ?? AmigaScreenView._fallbackFloor;
    if (floor > Duration.zero && elapsed - _lastUpload < floor) return;

    final AmigaFrame? frame = widget.core.frame();
    if (frame == null || frame.serial == _lastSerial) return;
    _lastSerial = frame.serial;
    _lastUpload = elapsed;
    unawaited(_upload(frame));
  }

  /// Checks the texture path is actually delivering, and abandons it if not.
  ///
  /// A created texture is not a working one. Flutter's SurfaceProducer is
  /// backed by an ImageReader in `ImageFormat.PRIVATE` with GPU-only usage,
  /// which a CPU producer cannot lock; the platform side then fails every
  /// present, silently, because a skipped frame is a normal thing for it to
  /// report. What the user sees is a black panel and hears working sound --
  /// which is exactly the report this exists to make impossible.
  ///
  /// The test is unambiguous: the core has published frames and the sink has
  /// posted none of them. Waiting [_textureGraceFrames] ticks -- about a
  /// second, one tick being one displayed frame -- covers a slow first surface
  /// without leaving a genuinely broken path up long enough to notice.
  ///
  /// Returns false when the texture has just been dropped, so the caller stops
  /// treating this tick as a texture tick.
  bool _watchTexture() {
    // Watched for the whole session, not just until it first works.
    //
    // The old version stopped checking the moment one frame posted, on the
    // reasoning that a working path stays working. It does not: the picture
    // can stop reaching the compositor part-way through a session -- after a
    // screen-mode change, after the surface is recreated -- and the widget
    // then shows the last frame that made it, frozen. Nothing repaints it
    // because nothing tells Flutter there is anything new, so the picture
    // only reappears when something else forces a rebuild. Pausing does,
    // which is why "I can only see the screen if I press pause".
    //
    // So the test is now "is it still delivering", and the answer is
    // whether the posted serial has moved since we last looked.
    final int posted = widget.core.texturePostedSerial();
    if (posted != _lastPostedSerial) {
      _lastPostedSerial = posted;
      _texturePostedNothing = 0;
      return true;
    }
    // Nothing new posted. That is only a fault if the core has something to
    // post -- a paused or idle machine publishes nothing and is not broken.
    final int published = widget.core.publishedSerial();
    if (published == _lastPublishedSerial) return true;
    _lastPublishedSerial = published;
    if (++_texturePostedNothing < _textureGraceFrames) return true;

    // Give it up. The fallback needs nothing but Dart, so there is nothing to
    // set up: dropping _texture is enough for the next tick to poll, upload
    // and paint.
    final AmigaTexture? dead = _texture;
    _textureRefused = true;
    AppLog.warn(
      'picture',
      'the texture stopped delivering after $published published frame(s); '
          'falling back to copy-and-decode',
    );
    setState(() => _texture = null);
    unawaited(dead?.dispose());
    return false;
  }

  /// Ticks, i.e. displayed frames, the texture path gets to prove itself over.
  static const int _textureGraceFrames = 60;

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
          ? (widget.fill
                ? Texture(
                    textureId: texture.id,
                    filterQuality: FilterQuality.none,
                  )
                : Center(
                    child: AspectRatio(
                      // The mode's pixel count is deliberately not used here;
                      // see AmigaScreenView.displayAspect.
                      aspectRatio: AmigaScreenView.displayAspect,
                      child: Texture(
                        textureId: texture.id,
                        filterQuality: FilterQuality.none,
                      ),
                    ),
                  ))
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
    // The touch mouse, built on raw pointers rather than GestureDetector.
    //
    // A gesture recogniser can say "tap", "long press" and "drag", and none
    // of those is the thing Workbench actually runs on: the LEFT BUTTON HELD
    // while the pointer moves. Resizing a window, dragging one, lassoing
    // icons, pulling a slider -- all of it is hold-and-move, and with only
    // tap and drag available none of it could be done at all.
    //
    // The grammar, borrowed from every laptop trackpad:
    //   one finger moving        the pointer, button up
    //   a second finger DOWN     the left button goes down and STAYS down
    //   the second finger UP     the button releases -- the drop
    //   quick single tap         a click
    //   press and hold still     a right click
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (PointerDownEvent e) {
        _mousePointers.add(e.pointer);
        if (_mousePointers.length == 1) {
          _dragPointer = e.pointer;
          _downAt = e.position;
          _moved = false;
          // A finger held still is a right click -- for context menus and
          // requesters. Cancelled the moment it moves or a second finger
          // arrives, because then it is a drag or a hold, not a press.
          _holdFired = false;
          _holdTimer?.cancel();
          _holdTimer = Timer(const Duration(milliseconds: 550), () {
            if (!_moved && _mousePointers.length == 1) {
              _holdFired = true;
              _click(1);
            }
          });
        } else if (_mousePointers.length == 2 && !_lmbHeld) {
          _holdTimer?.cancel();
          _lmbHeld = true;
          widget.core.mouseButton(0, true);
        }
      },
      onPointerMove: (PointerMoveEvent e) {
        if (e.pointer != _dragPointer) return;
        if ((e.position - _downAt).distance > 8) _moved = true;
        if (_moved) _holdTimer?.cancel();
        // Relative, like a trackpad. A touch pixel is roughly a screen pixel;
        // 1.5x makes Workbench crossable in one swipe on a phone.
        _carryX += e.delta.dx * 1.5;
        _carryY += e.delta.dy * 1.5;
        final int dx = _carryX.truncate();
        final int dy = _carryY.truncate();
        if (dx != 0 || dy != 0) {
          _carryX -= dx;
          _carryY -= dy;
          widget.core.mouseMove(dx, dy);
        }
      },
      onPointerUp: (PointerUpEvent e) => _mousePointerGone(e.pointer),
      onPointerCancel: (PointerCancelEvent e) => _mousePointerGone(e.pointer),
      child: keyed,
    );
  }

  final Set<int> _mousePointers = <int>{};
  int _dragPointer = -1;
  Offset _downAt = Offset.zero;
  bool _moved = false;
  bool _lmbHeld = false;
  bool _holdFired = false;
  Timer? _holdTimer;

  void _mousePointerGone(int pointer) {
    final bool wasOnly =
        _mousePointers.length == 1 && _mousePointers.contains(pointer);
    _mousePointers.remove(pointer);
    _holdTimer?.cancel();
    if (_lmbHeld && _mousePointers.length <= 1) {
      // The second finger lifting is the drop. Releasing on ANY finger going
      // -- rather than only the second -- means lifting both at once can
      // never leave the Amiga holding a button with nothing to release it.
      _lmbHeld = false;
      widget.core.mouseButton(0, false);
    }
    if (wasOnly && !_moved && !_lmbHeld && !_holdFired) {
      // Down and up in place, alone: a click. NOT after a hold: the hold
      // already right-clicked, and following it with a left click on the
      // lift dismissed whatever the right click had just opened -- which
      // read as the right click not working at all.
      unawaited(_click(0));
    }
    if (_mousePointers.isEmpty) _dragPointer = -1;
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
      // Not the image's own proportions: the destination is a 4:3 box, and
      // the whole frame is stretched into it whatever mode produced it. See
      // AmigaScreenView.displayAspect.
      rect: fill ? Offset.zero & size : _correctedRect(size),
      image: image,
      // The Amiga's pixels are the artwork. Smoothing them is the difference
      // between a chunky screen and a blurred one.
      filterQuality: FilterQuality.none,
      fit: BoxFit.fill,
    );
  }

  /// The largest 4:3 rectangle that fits [size], centred.
  static Rect _correctedRect(Size size) {
    const double aspect = AmigaScreenView.displayAspect;
    double width = size.width;
    double height = width / aspect;
    if (height > size.height) {
      height = size.height;
      width = height * aspect;
    }
    return Rect.fromLTWH(
      (size.width - width) / 2,
      (size.height - height) / 2,
      width,
      height,
    );
  }

  @override
  bool shouldRepaint(_FramePainter old) =>
      old.fill != fill || old.source != source;
}
