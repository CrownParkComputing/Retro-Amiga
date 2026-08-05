package com.uae4arm2026.data

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioTrack
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlin.math.pow

data class ModPlayerState(
	val isPlaying: Boolean = false,
	val assetName: String? = null,
	val title: String = "",
	val durationSeconds: Double = 0.0
)

/**
 * Bundled MOD/XM/S3M/IT tracker playback, backed by libopenmpt (see the JNI bridge in
 * src/osdep/mod_player_jni.cpp and the openmpt CMake target in cmake/Dependencies.cmake).
 *
 * Deliberately independent of the Amiga emulation core's own audio pipeline - this decodes a
 * bundled tracker module to PCM on a background coroutine and feeds it straight to an AudioTrack.
 * A process-wide singleton (not tied to any Activity/ViewModel) so a tune started by the boot
 * intro keeps playing as the user lands on Configurations, and so the Mod Player screen can
 * reflect/control whatever's already playing.
 */
object ModPlayer {
	// A dedicated small library (see cmake/Dependencies.cmake), NOT libuae4arm.so - the emulation
	// core only ever loads in the separate ":sdl" process (see Uae4ArmEmulatorActivity's manifest
	// entry), which this singleton's callers (MainActivity's process) never touch.
	init {
		System.loadLibrary("modplayer")
	}

	private const val SAMPLE_RATE = 44100
	private const val ASSET_DIR = "mods"

	private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
	private var playJob: Job? = null

	private val _state = MutableStateFlow(ModPlayerState())
	val state: StateFlow<ModPlayerState> = _state.asStateFlow()

	/** Number of spectrum bands published for the on-screen graphic EQ. */
	const val BAND_COUNT = 16
	private val _levels = MutableStateFlow(FloatArray(BAND_COUNT))
	/** Per-band 0..1 magnitudes of the audio currently being played (all zeroes when idle). */
	val levels: StateFlow<FloatArray> = _levels.asStateFlow()

	// FFT scratch, reused per chunk to keep the audio loop allocation-free.
	private const val FFT_SIZE = 512
	private val fftRe = FloatArray(FFT_SIZE)
	private val fftIm = FloatArray(FFT_SIZE)
	private val smoothed = FloatArray(BAND_COUNT)

	/**
	 * In-place iterative radix-2 Cooley-Tukey FFT. Small and self-contained - the alternative
	 * would be pulling in a DSP dependency purely to drive a decorative visualiser.
	 */
	private fun fft(re: FloatArray, im: FloatArray) {
		val n = re.size
		// Bit-reversal permutation.
		var j = 0
		for (i in 1 until n) {
			var bit = n shr 1
			while (j and bit != 0) {
				j = j xor bit
				bit = bit shr 1
			}
			j = j or bit
			if (i < j) {
				val tr = re[i]; re[i] = re[j]; re[j] = tr
				val ti = im[i]; im[i] = im[j]; im[j] = ti
			}
		}
		var len = 2
		while (len <= n) {
			val ang = -2.0 * Math.PI / len
			val wRe = kotlin.math.cos(ang).toFloat()
			val wIm = kotlin.math.sin(ang).toFloat()
			var i = 0
			while (i < n) {
				var curRe = 1f
				var curIm = 0f
				for (k in 0 until len / 2) {
					val uRe = re[i + k]
					val uIm = im[i + k]
					val vRe = re[i + k + len / 2] * curRe - im[i + k + len / 2] * curIm
					val vIm = re[i + k + len / 2] * curIm + im[i + k + len / 2] * curRe
					re[i + k] = uRe + vRe
					im[i + k] = uIm + vIm
					re[i + k + len / 2] = uRe - vRe
					im[i + k + len / 2] = uIm - vIm
					val nextRe = curRe * wRe - curIm * wIm
					curIm = curRe * wIm + curIm * wRe
					curRe = nextRe
				}
				i += len
			}
			len = len shl 1
		}
	}

	/** Folds one PCM chunk into BAND_COUNT log-spaced bands for the visualiser. */
	private fun publishLevels(buffer: ShortArray, frames: Int) {
		val n = minOf(FFT_SIZE, frames)
		for (i in 0 until n) {
			// Mono-sum the interleaved stereo pair, normalise, and Hann-window to cut spectral leakage.
			val mono = (buffer[i * 2].toFloat() + buffer[i * 2 + 1].toFloat()) * 0.5f / 32768f
			val w = 0.5f - 0.5f * kotlin.math.cos(2.0 * Math.PI * i / n).toFloat()
			fftRe[i] = mono * w
			fftIm[i] = 0f
		}
		for (i in n until FFT_SIZE) {
			fftRe[i] = 0f
			fftIm[i] = 0f
		}
		fft(fftRe, fftIm)

		val out = FloatArray(BAND_COUNT)
		val bins = FFT_SIZE / 2
		for (b in 0 until BAND_COUNT) {
			// Log-spaced bands: music energy is bunched in the low end, so linear bands would
			// leave the upper two-thirds of the display permanently flat.
			val lo = (bins.toDouble().pow(b.toDouble() / BAND_COUNT)).toInt().coerceIn(1, bins - 1)
			val hi = (bins.toDouble().pow((b + 1.0) / BAND_COUNT)).toInt().coerceIn(lo + 1, bins)
			// Mean (not peak) energy across the band, normalised by the transform length - raw FFT
			// magnitudes scale with FFT_SIZE, which is what made the old linear scaling peg the
			// bass band at full height and leave every other bar at zero.
			var sum = 0f
			for (k in lo until hi) {
				sum += kotlin.math.sqrt(fftRe[k] * fftRe[k] + fftIm[k] * fftIm[k])
			}
			val mean = (sum / (hi - lo)) / (FFT_SIZE / 4f)

			// dB scale, because amplitude is perceptually logarithmic: a linear meter shows one
			// tall bass bar and nothing else. -58..-6 dBFS maps onto the bar's full travel.
			val db = 20f * kotlin.math.log10(mean + 1e-7f)
			var v = ((db + 58f) / 52f).coerceIn(0f, 1f)
			// Gentle high-frequency tilt: real music rolls off ~ -6 dB/octave upward, so without
			// this the top bands still barely move even on a dB scale.
			v *= 0.55f + 0.45f * (b.toFloat() / (BAND_COUNT - 1))
			v = v.coerceIn(0f, 1f)

			// Instant attack, smoothed release - bars punch on transients then fall back.
			smoothed[b] = if (v > smoothed[b]) v else smoothed[b] * 0.80f + v * 0.20f
			out[b] = smoothed[b]
		}
		_levels.value = out
	}

	/** Bundled mod filenames, sorted for a stable list order. */
	fun listAvailableMods(context: Context): List<String> {
		return try {
			context.assets.list(ASSET_DIR)
				?.filter { it.endsWith(".mod", ignoreCase = true) }
				?.sorted()
				?: emptyList()
		} catch (_: Exception) {
			emptyList()
		}
	}

	fun randomMod(context: Context): String? = listAvailableMods(context).randomOrNull()

	/** Starts playback of [assetName] (from assets/mods/), replacing whatever's currently playing. */
	fun play(context: Context, assetName: String, loop: Boolean = true) {
		stop()
		playJob = scope.launch {
			val bytes = try {
				context.assets.open("$ASSET_DIR/$assetName").use { it.readBytes() }
			} catch (_: Exception) {
				return@launch
			}

			val newHandle = nativeOpen(bytes)
			if (newHandle == 0L) {
				return@launch
			}
			val duration = nativeGetDurationSeconds(newHandle)
			val title = nativeGetTitle(newHandle).ifBlank { assetName.removeSuffix(".mod") }
			_state.value = ModPlayerState(isPlaying = true, assetName = assetName, title = title, durationSeconds = duration)

			val track = AudioTrack.Builder()
				.setAudioAttributes(
					AudioAttributes.Builder()
						.setUsage(AudioAttributes.USAGE_MEDIA)
						.setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
						.build()
				)
				.setAudioFormat(
					AudioFormat.Builder()
						.setSampleRate(SAMPLE_RATE)
						.setChannelMask(AudioFormat.CHANNEL_OUT_STEREO)
						.setEncoding(AudioFormat.ENCODING_PCM_16BIT)
						.build()
				)
				.setTransferMode(AudioTrack.MODE_STREAM)
				.build()
			track.play()

			val framesPerChunk = 2048
			val buffer = ShortArray(framesPerChunk * 2) // interleaved stereo
			try {
				// isActive is the cancellation checkpoint this loop needs: nativeReadStereo() and
				// track.write() are both blocking native/JNI calls, not suspend functions, so
				// Job.cancel() (called by stop() when switching tracks) can't interrupt this loop
				// on its own - without checking isActive, this coroutine kept running the OLD
				// track's read/write loop against a handle that stop() had already destroyed via
				// nativeClose(), a use-after-free that crashed (SIGSEGV) on picking a new track.
				while (isActive) {
					val rendered = nativeReadStereo(newHandle, buffer, framesPerChunk)
					if (rendered <= 0) {
						if (loop) {
							nativeSetPositionSeconds(newHandle, 0.0)
							continue
						}
						break
					}
					publishLevels(buffer, rendered)
					track.write(buffer, 0, rendered * 2)
				}
			} finally {
				track.stop()
				track.release()
				nativeClose(newHandle)
			}
		}
	}

	/**
	 * Stops playback. Safe to call when idle. Only cancels the job and resets published state -
	 * the AudioTrack/native handle are exclusively owned and torn down by play()'s own coroutine
	 * (its `finally` block runs on cancellation too), never touched from the calling thread. Two
	 * owners racing to release the same handle/AudioTrack was the earlier crash on switching mods.
	 */
	fun stop() {
		playJob?.cancel()
		playJob = null
		_state.value = ModPlayerState()
		java.util.Arrays.fill(smoothed, 0f)
		_levels.value = FloatArray(BAND_COUNT)
	}

	private external fun nativeOpen(data: ByteArray): Long
	private external fun nativeReadStereo(handle: Long, buffer: ShortArray, frames: Int): Int
	private external fun nativeGetDurationSeconds(handle: Long): Double
	private external fun nativeGetTitle(handle: Long): String
	private external fun nativeSetPositionSeconds(handle: Long, seconds: Double)
	private external fun nativeClose(handle: Long)
}
