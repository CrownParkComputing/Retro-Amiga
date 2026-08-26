import Accelerate
import CoreVideo
import Flutter
import QuartzCore

/// The Amiga's picture as a Flutter external texture.
///
/// The panel's first version took every frame the long way: a native staging
/// copy, a Dart allocation, `decodeImageFromPixels`, and a fresh GPU upload.
/// At 752x576 that is close to 7MB of copying per frame, and it is why the
/// panel had to be capped below the Amiga's own frame rate. A `FlutterTexture`
/// hands the compositor a buffer the app owns, so a frame costs one strided
/// copy out of the emulator's front buffer and a channel permute.
///
/// Frames are pushed by a `CADisplayLink` rather than polled from Dart, so
/// nothing about a frame crosses a platform channel. The channel is used
/// twice a session: once to hand the texture id up, once to tear it down.
///
/// Everything here is best-effort. A core too old to carry host_texture.cpp
/// has no symbols to bind, `create` answers nil, and the Dart side falls back
/// to copy-and-decode with nothing to configure.
final class AmigaTexturePlugin: NSObject {

  static let channelName = "uae4arm2026/texture"

  private typealias SinkFn = @convention(c) (UnsafeMutableRawPointer?) -> Bool
  private typealias SetSinkFn =
    @convention(c) (SinkFn?, UnsafeMutableRawPointer?) -> Void
  private typealias PresentFn = @convention(c) () -> Bool
  private typealias SizeFn =
    @convention(c) (UnsafeMutablePointer<Int32>?, UnsafeMutablePointer<Int32>?) -> Void
  private typealias CopyFn = @convention(c) (
    UnsafeMutableRawPointer?, Int32, Int32,
    UnsafeMutablePointer<Int32>?, UnsafeMutablePointer<Int32>?,
    UnsafeMutablePointer<UInt64>?
  ) -> Int32

  private let registry: FlutterTextureRegistry
  private var textureId: Int64?
  private var displayLink: CADisplayLink?

  /// Guards [ready] against the raster thread, which asks for it through
  /// copyPixelBuffer while the display link may be filling the next one.
  private let lock = NSLock()

  /// The buffer the compositor should draw, and the one being written. Two,
  /// not one: writing into the buffer the raster thread is reading is a tear
  /// that only shows on slow frames.
  private var ready: CVPixelBuffer?
  private var spare: CVPixelBuffer?
  private var bufferWidth: Int32 = 0
  private var bufferHeight: Int32 = 0

  private var setSink: SetSinkFn?
  private var present: PresentFn?
  private var frameSize: SizeFn?
  private var copyStrided: CopyFn?

  init(registry: FlutterTextureRegistry) {
    self.registry = registry
    super.init()
  }

  static func register(with controller: FlutterViewController) -> AmigaTexturePlugin? {
    guard
      let registrar = controller.engine?.registrar(forPlugin: "AmigaTexturePlugin"),
      let textures = registrar.textures() as FlutterTextureRegistry?
    else { return nil }

    let plugin = AmigaTexturePlugin(registry: textures)
    let channel = FlutterMethodChannel(
      name: channelName, binaryMessenger: controller.binaryMessenger)
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "create":
        result(plugin.create())
      case "dispose":
        plugin.dispose()
        result(true)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    return plugin
  }

  // MARK: - Lifecycle

  private func bindSymbols() -> Bool {
    if setSink != nil { return true }
    guard
      let sinkSymbol = EmulatorHost.shared.coreSymbol("uae4arm_host_texture_set_sink"),
      let presentSymbol = EmulatorHost.shared.coreSymbol("uae4arm_host_texture_present"),
      let sizeSymbol = EmulatorHost.shared.coreSymbol("uae4arm_host_framebuffer_size"),
      let copySymbol = EmulatorHost.shared.coreSymbol("uae4arm_host_copy_framebuffer_strided")
    else { return false }
    setSink = unsafeBitCast(sinkSymbol, to: SetSinkFn.self)
    present = unsafeBitCast(presentSymbol, to: PresentFn.self)
    frameSize = unsafeBitCast(sizeSymbol, to: SizeFn.self)
    copyStrided = unsafeBitCast(copySymbol, to: CopyFn.self)
    return true
  }

  private func create() -> [String: Any]? {
    dispose()
    guard bindSymbols() else { return nil }

    // A first size so there is a texture before the Amiga has drawn anything.
    // Replaced the moment a real frame reports its mode.
    guard resize(width: 720, height: 568) else { return nil }

    let id = registry.registerTexture(self)
    textureId = id

    setSink?(
      { context in
        guard let context = context else { return false }
        let plugin = Unmanaged<AmigaTexturePlugin>
          .fromOpaque(context).takeUnretainedValue()
        return plugin.fill()
      }, Unmanaged.passUnretained(self).toOpaque())

    let link = CADisplayLink(target: self, selector: #selector(step))
    link.add(to: .main, forMode: .common)
    displayLink = link

    return ["id": id, "width": Int(bufferWidth), "height": Int(bufferHeight)]
  }

  func dispose() {
    displayLink?.invalidate()
    displayLink = nil
    // Sink first: it must stop before the buffers it writes into are released.
    setSink?(nil, nil)
    if let id = textureId {
      registry.unregisterTexture(id)
      textureId = nil
    }
    lock.lock()
    ready = nil
    spare = nil
    bufferWidth = 0
    bufferHeight = 0
    lock.unlock()
  }

  // MARK: - Frames

  @objc private func step() {
    guard let present = present, let frameSize = frameSize else { return }

    // The Amiga changes display mode mid-game, and fill() refuses a buffer
    // that is not exactly the frame's size rather than shear the picture or
    // leave a margin of stale pixels. Resizing is what lets it start again.
    var width: Int32 = 0
    var height: Int32 = 0
    frameSize(&width, &height)
    if width > 0, height > 0, width != bufferWidth || height != bufferHeight {
      _ = resize(width: width, height: height)
      return
    }

    if present(), let id = textureId {
      registry.textureFrameAvailable(id)
    }
  }

  /// Called from the core's present, with no emulator lock held.
  private func fill() -> Bool {
    guard let copyStrided = copyStrided else { return false }

    lock.lock()
    let target = spare
    let width = bufferWidth
    let height = bufferHeight
    lock.unlock()

    guard let buffer = target, width > 0, height > 0 else { return false }

    CVPixelBufferLockBaseAddress(buffer, [])
    defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
    guard let base = CVPixelBufferGetBaseAddress(buffer) else { return false }

    let stride = CVPixelBufferGetBytesPerRow(buffer)
    let written = copyStrided(
      base, Int32(stride / 4), height, nil, nil, nil)
    if written <= 0 { return false }

    // The emulator publishes ABGR8888, which little-endian is R,G,B,A in
    // memory; a Flutter texture wants BGRA. Doing it here rather than asking
    // the core for another format keeps Android -- where R,G,B,A is exactly
    // what the compositor wants -- on a copy with no fixup at all. vImage
    // rather than a loop: this is a SIMD permute over 1.7MB, and a scalar
    // version of it costs more than the copy it follows.
    var image = vImage_Buffer(
      data: base, height: vImagePixelCount(height),
      width: vImagePixelCount(width), rowBytes: stride)
    let toBGRA: [UInt8] = [2, 1, 0, 3]
    _ = vImagePermuteChannels_ARGB8888(&image, &image, toBGRA, vImage_Flags(kvImageNoFlags))

    // ...and the alpha byte forced opaque, HERE.
    //
    // The emulator leaves the top byte zero, and this buffer is 32BGRA, which
    // Core Video and Flutter both take at its word: every pixel of a
    // perfectly correct picture is fully transparent and the screen shows
    // whatever is behind it.
    //
    // It used to be done by the publisher, for every frame on every platform.
    // That is two million read-modify-writes a frame at the resolutions an
    // RTG collection asks for, on the thread whose scheduling latency causes
    // audio underruns -- so it moved to the consumers that actually care.
    // Android does not: its window is RGBX, where the byte is ignored by
    // definition. iOS does, and pays for it in one more SIMD pass over a
    // buffer already in cache from the permute above.
    _ = vImageOverwriteChannelsWithScalar_ARGB8888(
      255, &image, &image, 0x1, vImage_Flags(kvImageNoFlags))

    lock.lock()
    spare = ready
    ready = buffer
    lock.unlock()
    return true
  }

  /// Allocates the pair of buffers for a new mode. Returns false if the
  /// allocation failed, in which case the texture stays on its old size and
  /// the next display link tick tries again.
  private func resize(width: Int32, height: Int32) -> Bool {
    guard let first = makeBuffer(width: width, height: height),
      let second = makeBuffer(width: width, height: height)
    else { return false }
    lock.lock()
    ready = first
    spare = second
    bufferWidth = width
    bufferHeight = height
    lock.unlock()
    return true
  }

  private func makeBuffer(width: Int32, height: Int32) -> CVPixelBuffer? {
    var buffer: CVPixelBuffer?
    let attributes: [CFString: Any] = [
      // Both are needed: Metal to sample it, IOSurface because a Flutter
      // texture is handed to the compositor rather than drawn here.
      kCVPixelBufferMetalCompatibilityKey: true,
      kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary,
    ]
    let status = CVPixelBufferCreate(
      kCFAllocatorDefault, Int(width), Int(height),
      kCVPixelFormatType_32BGRA, attributes as CFDictionary, &buffer)
    return status == kCVReturnSuccess ? buffer : nil
  }
}

extension AmigaTexturePlugin: FlutterTexture {
  func copyPixelBuffer() -> Unmanaged<CVPixelBuffer>? {
    lock.lock()
    defer { lock.unlock() }
    guard let buffer = ready else { return nil }
    return Unmanaged.passRetained(buffer)
  }
}
