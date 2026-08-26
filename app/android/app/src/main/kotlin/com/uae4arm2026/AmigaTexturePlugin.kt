package com.uae4arm2026

import android.view.Choreographer
import android.view.Surface
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.view.TextureRegistry

/**
 * The Amiga's picture as an external texture.
 *
 * The panel's first version took each frame the long way round: a native
 * staging copy, a Dart allocation, decodeImageFromPixels, and a fresh GPU
 * upload -- four copies of 1.7MB per frame at 752x576, which is why the
 * Android panel had to be capped at 30fps to leave the audio callback any
 * room. Flutter can composite a surface the app owns instead, and that turns
 * the whole thing into one memcpy from the emulator's front buffer into the
 * buffer the compositor is about to read.
 *
 * ## Why a SurfaceTexture and not a SurfaceProducer
 *
 * The obvious registry entry is `createSurfaceProducer()`, and it is the one
 * this used at first. It does not work for a CPU producer. On API 29+ the
 * producer is an ImageReader built with `ImageFormat.PRIVATE` and
 * `HardwareBuffer.USAGE_GPU_SAMPLED_IMAGE` -- an opaque, GPU-only buffer.
 * `ANativeWindow_lock` on it has nothing CPU-writable to hand back, so it
 * fails; every present failed with it, and because failing to present is not
 * an error anywhere in the path, the result was a black panel with working
 * sound. `setSize()` on it does not help: the format is the problem, not the
 * geometry.
 *
 * A SurfaceTexture's surface is a plain BufferQueue. It hands out CPU-writable
 * buffers, it takes its geometry from the producer -- so the native side can
 * follow a mode change immediately rather than waiting to be resized -- and
 * posting a buffer marks the texture frame available without anything having
 * to call `scheduleFrame`.
 *
 * Both ends still have to agree on the size, though: the producer's geometry
 * is set natively and the consumer's default buffer size is set here, in
 * [resizeToFrame], from the same number. Letting them drift is what draws the
 * picture into the corner of the panel.
 *
 * Nothing about a frame passes through Dart or through a platform channel.
 * The channel is used twice a session -- to hand the texture id up and to tear
 * it down -- and the frames themselves are pushed by a Choreographer callback
 * calling straight into the native side.
 */
class AmigaTexturePlugin(private val registry: TextureRegistry) {

	companion object {
		const val CHANNEL = "uae4arm2026/texture"

		/**
		 * The library is the emulator's own, and it is tens of megabytes.
		 * Loading it here would slow every cold start for a screen most
		 * sessions reach only after choosing something to run; by the time a
		 * texture is asked for, the in-process core has loaded it already.
		 */
		@JvmStatic external fun nativeAttachSurface(surface: android.view.Surface?): Boolean
		@JvmStatic external fun nativeDetachSurface()
		@JvmStatic external fun nativePresent(): Boolean
		@JvmStatic external fun nativeFrameSize(): Long
	}

	private var entry: TextureRegistry.SurfaceTextureEntry? = null
	private var surface: Surface? = null
	private var frameCallback: Choreographer.FrameCallback? = null

	/** What the SurfaceTexture is currently sized to. */
	private var width = 0
	private var height = 0

	fun register(engine: FlutterEngine) {
		MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL)
			.setMethodCallHandler { call, result ->
				when (call.method) {
					"create" -> result.success(create())
					"dispose" -> {
						dispose()
						result.success(true)
					}
					else -> result.notImplemented()
				}
			}
	}

	private fun create(): Map<String, Any>? {
		dispose()
		val created = try {
			registry.createSurfaceTexture()
		} catch (error: Throwable) {
			// No entry means no texture path, which is a fallback and not a
			// failure: Dart takes the copy-and-decode route instead.
			return null
		}
		entry = created
		// A first size so there is a buffer queue before the Amiga has drawn
		// anything. Both ends move off it together -- native through
		// ANativeWindow_setBuffersGeometry, this side through resizeToFrame --
		// the moment a frame reports a different mode.
		width = 720
		height = 568
		created.surfaceTexture().setDefaultBufferSize(width, height)
		val target = Surface(created.surfaceTexture())
		surface = target
		if (!attach(target)) {
			dispose()
			return null
		}
		startFrameLoop()
		return mapOf("id" to created.id(), "width" to width, "height" to height)
	}

	private fun attach(target: Surface): Boolean =
		try {
			nativeAttachSurface(target)
		} catch (error: UnsatisfiedLinkError) {
			// A core built before host_texture.cpp existed. Same answer as no
			// entry at all: fall back.
			false
		}

	private fun startFrameLoop() {
		val choreographer = Choreographer.getInstance()
		val callback = object : Choreographer.FrameCallback {
			override fun doFrame(frameTimeNanos: Long) {
				if (entry == null) return
				resizeToFrame()
				// Posting a buffer is what marks the texture frame available,
				// so there is nothing to schedule.
				nativePresent()
				choreographer.postFrameCallback(this)
			}
		}
		frameCallback = callback
		choreographer.postFrameCallback(callback)
	}

	/**
	 * Keeps the CONSUMER's idea of the buffer size in step with the producer's.
	 *
	 * The native side sets the producer geometry itself, which is what lets a
	 * mode change take effect immediately. That is only half of it: a
	 * SurfaceTexture also has a default buffer size, and Flutter samples the
	 * texture through the transform matrix that goes with it. Let the two drift
	 * apart -- native producing 752x576, or the 1920x1080 the headless surface
	 * fallback can publish, into a texture still declared 720x568 -- and the
	 * compositor draws the frame at the wrong scale, which on screen is the
	 * picture shrunk into the top-left corner of the panel.
	 *
	 * That is the "resuming a game shrinks it to the top left" report. Resume
	 * is where it shows up first because a restored state brings its own
	 * display mode, which is usually not the one the surface was created with.
	 */
	private fun resizeToFrame() {
		val created = entry ?: return
		val packed = nativeFrameSize()
		val frameWidth = (packed ushr 32).toInt()
		val frameHeight = (packed and 0xFFFFFFFFL).toInt()
		if (frameWidth <= 0 || frameHeight <= 0) return
		if (frameWidth == width && frameHeight == height) return
		width = frameWidth
		height = frameHeight
		created.surfaceTexture().setDefaultBufferSize(width, height)
	}

	/** Releases the surface and stops the frame loop. Safe to call twice. */
	fun dispose() {
		frameCallback?.let { Choreographer.getInstance().removeFrameCallback(it) }
		frameCallback = null
		try {
			// Sink first: present() must stop before the surface it writes to
			// is released, not after.
			nativeDetachSurface()
		} catch (error: UnsatisfiedLinkError) {
			// Never attached; nothing to let go of.
		}
		surface?.release()
		surface = null
		entry?.release()
		entry = null
		width = 0
		height = 0
	}
}
