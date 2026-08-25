package com.uae4arm2026

import android.view.Choreographer
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

	private var producer: TextureRegistry.SurfaceProducer? = null
	private var frameCallback: Choreographer.FrameCallback? = null

	/** What the producer is currently sized to, so a resize is only done once. */
	private var width = 0
	private var height = 0

	/** True between onSurfaceCleanup and the next onSurfaceAvailable. */
	private var surfaceLost = false

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
		val entry = try {
			registry.createSurfaceProducer()
		} catch (error: Throwable) {
			// No producer means no texture path, which is a fallback and not a
			// failure: Dart takes the copy-and-decode route instead.
			return null
		}
		producer = entry
		// A first size so the surface exists before the Amiga has drawn
		// anything. It is replaced the moment a real frame reports its mode.
		width = 720
		height = 568
		entry.setSize(width, height)
		entry.setCallback(object : TextureRegistry.SurfaceProducer.Callback {
			override fun onSurfaceAvailable() {
				// A new surface is a different buffer queue, so the handle the
				// native side is holding is stale. Re-attaching also clears
				// the "already posted" serial, so the next frame repaints
				// rather than being skipped as unchanged.
				surfaceLost = false
				attach()
			}

			override fun onSurfaceCleanup() {
				// Detach BEFORE the surface goes: a present landing after the
				// compositor has released the buffer queue writes to memory
				// that is no longer ours.
				surfaceLost = true
				nativeDetachSurface()
			}
		})
		if (!attach()) {
			dispose()
			return null
		}
		startFrameLoop()
		return mapOf("id" to entry.id(), "width" to width, "height" to height)
	}

	private fun attach(): Boolean {
		val entry = producer ?: return false
		return try {
			nativeAttachSurface(entry.getSurface())
		} catch (error: UnsatisfiedLinkError) {
			// A core built before host_texture.cpp existed. Same answer as no
			// producer at all: fall back.
			false
		}
	}

	private fun startFrameLoop() {
		val choreographer = Choreographer.getInstance()
		val callback = object : Choreographer.FrameCallback {
			override fun doFrame(frameTimeNanos: Long) {
				if (producer == null) return
				pumpFrame()
				choreographer.postFrameCallback(this)
			}
		}
		frameCallback = callback
		choreographer.postFrameCallback(callback)
	}

	private fun pumpFrame() {
		val entry = producer ?: return
		if (surfaceLost) return

		// The Amiga changes display mode mid-game, and the native side refuses
		// to fill a buffer that is not exactly the frame's size rather than
		// shear the picture or leave a margin of stale pixels. Resizing here
		// is what lets it start filling again.
		val packed = nativeFrameSize()
		val frameWidth = (packed ushr 32).toInt()
		val frameHeight = (packed and 0xFFFFFFFFL).toInt()
		if (frameWidth > 0 && frameHeight > 0 &&
			(frameWidth != width || frameHeight != height)
		) {
			width = frameWidth
			height = frameHeight
			entry.setSize(width, height)
			// setSize can hand back a different surface, and the native side
			// is holding the old one.
			attach()
			return
		}

		if (nativePresent()) entry.scheduleFrame()
	}

	/** Releases the surface and stops the frame loop. Safe to call twice. */
	fun dispose() {
		frameCallback?.let { Choreographer.getInstance().removeFrameCallback(it) }
		frameCallback = null
		try {
			nativeDetachSurface()
		} catch (error: UnsatisfiedLinkError) {
			// Never attached; nothing to let go of.
		}
		producer?.release()
		producer = null
		width = 0
		height = 0
		surfaceLost = false
	}
}
