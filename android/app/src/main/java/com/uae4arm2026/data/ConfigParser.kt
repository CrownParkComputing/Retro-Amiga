package com.uae4arm2026.data

import android.util.Log
import com.uae4arm2026.data.model.AmigaModel
import com.uae4arm2026.data.model.EmulatorSettings
import com.uae4arm2026.data.model.FileCategory
import java.io.File
import java.io.IOException

/**
 * Parses .uae config files back into EmulatorSettings.
 * Preserves unknown keys so configs created by ImGui don't lose settings on round-trip.
 */
object ConfigParser {
	private val uaehfFileKeyRegex = Regex("""uaehf(\d+)_file""")
	private val uaehfKeyRegex = Regex("""uaehf\d+(?:_(?:file|name|bootpri|present|blocksize|readonly))?""")

	data class ParsedConfig(
		val settings: EmulatorSettings,
		val unknownLines: List<String>,
		val description: String
	)

	// Keys we know how to parse into EmulatorSettings
	private val knownKeys = setOf(
		"cpu_model", "cpu_compatible", "cpu_24bit_addressing", "cpu_speed",
		"fpu_model", "cachesize", "compfpu",
		"chipset", "immediate_blits", "collision_level", "cycle_exact", "ntsc",
		"chipmem_size", "bogomem_size", "fastmem_size", "z3mem_size",
		"kickstart_rom_file", "kickstart_ext_rom_file",
		"floppy0", "floppy0type", "floppy1", "floppy1type",
		"floppy2", "floppy2type", "floppy3", "floppy3type",
		"cdimage0", "whdload_filename", "hardfile2", "filesystem2",
		"sound_output", "sound_frequency", "sound_channels", "sound_stereo_separation", "sound_interpol",
		"gfx_width", "gfx_height", "gfx_correct_aspect", "gfx_auto_crop", "rtgmem_type", "rtgmem_size", "gfxcard_type", "gfxcard_size", "gfxcard_options", "gfx_fullscreen_amiga", "gfx_fullscreen_picasso", "rtg_nocustom", "rtg_noautomodes", "show_leds",
		"joyport0", "joyport1",
		UpstreamConfig.KEY_TOUCH_SETTINGS_VERSION,
		UpstreamConfig.KEY_ONSCREEN_JOYSTICK, UpstreamConfig.KEY_AMIBERRY_ONSCREEN_JOYSTICK,
		UpstreamConfig.KEY_ONSCREEN_CD32PAD, UpstreamConfig.KEY_AMIBERRY_ONSCREEN_CD32PAD, UpstreamConfig.KEY_VIRTUAL_KEYBOARD_ENABLED, UpstreamConfig.KEY_DEFAULT_OSK,
		UpstreamConfig.KEY_SHOW_ANDROID_KEYBOARD_BUTTON,
		UpstreamConfig.KEY_ANDROID_JOYPORT1,
		"use_gui", "config_description", "config_hardware_path"
	)

	private const val TAG = "Uae4Arm-ConfigParser"

	fun sanitizeUnknownLines(lines: List<String>): List<String> {
		return lines.filterNot { line ->
			val trimmed = line.trim()
			if (trimmed.isEmpty() || trimmed.startsWith(";") || !trimmed.contains('=')) {
				false
			} else {
				val key = trimmed.substringBefore('=').trim()
				key in knownKeys || uaehfKeyRegex.matches(key)
			}
		}
	}

	fun migrateLegacyManagedSettings(file: File, settings: EmulatorSettings): EmulatorSettings {
		if (!file.name.startsWith(".")) {
			return settings
		}

		val hasTouchSettingsVersion = try {
			file.useLines { lines ->
				lines.any { it.trim().startsWith("${UpstreamConfig.KEY_TOUCH_SETTINGS_VERSION}=") }
			}
		} catch (_: IOException) {
			true
		}

		if (hasTouchSettingsVersion) {
			return settings
		}

		return settings.copy(
			onScreenJoystick = false,
			joyport1 = if (settings.joyport1 == "onscreen_joy") "joy1" else settings.joyport1
		)
	}

	fun parse(file: File): ParsedConfig {
		if (!file.exists()) return ParsedConfig(EmulatorSettings(), emptyList(), "")

		val lines = try {
			file.readLines()
		} catch (e: IOException) {
			Log.e(TAG, "Failed to read config file: ${file.path}", e)
			return ParsedConfig(EmulatorSettings(), emptyList(), "")
		}
		val kvPairs = mutableMapOf<String, String>()
		val unknownLines = mutableListOf<String>()
		val hardfileLines = mutableListOf<String>()

		for (line in lines) {
			val trimmed = line.trim()
			if (trimmed.isEmpty() || trimmed.startsWith(";")) continue

			val eqIndex = trimmed.indexOf('=')
			if (eqIndex < 0) {
				unknownLines.add(line)
				continue
			}

			val key = trimmed.substring(0, eqIndex).trim()
			val value = trimmed.substring(eqIndex + 1).trim()

			if (key in knownKeys || uaehfKeyRegex.matches(key)) {
				if (key == "hardfile2" || key == "filesystem2") {
					hardfileLines += value
				} else {
					kvPairs[key] = value
				}
			} else {
				unknownLines.add(line)
			}
		}

		val settings = buildSettings(kvPairs, hardfileLines)
		val description = kvPairs["config_description"] ?: ""

		return ParsedConfig(settings, unknownLines, description)
	}

	private fun buildSettings(kv: Map<String, String>, hardfileLines: List<String>): EmulatorSettings {
		val hardDriveList = parseAllHardfilePaths(kv, hardfileLines)
		val onScreenJoystick = kv[UpstreamConfig.KEY_AMIBERRY_ONSCREEN_JOYSTICK].toBool(false)
			|| kv[UpstreamConfig.KEY_ONSCREEN_JOYSTICK].toBool(false)
		val onScreenKeyboard = when {
			kv.containsKey(UpstreamConfig.KEY_SHOW_ANDROID_KEYBOARD_BUTTON) -> kv[UpstreamConfig.KEY_SHOW_ANDROID_KEYBOARD_BUTTON].toBool(true)
			kv.containsKey(UpstreamConfig.KEY_DEFAULT_OSK) -> kv[UpstreamConfig.KEY_DEFAULT_OSK].toBool(true)
			kv.containsKey(UpstreamConfig.KEY_VIRTUAL_KEYBOARD_ENABLED) -> kv[UpstreamConfig.KEY_VIRTUAL_KEYBOARD_ENABLED].toBool(true)
			else -> true
		}
		val parsedWidth = kv["gfx_width"]?.toIntOrNull() ?: 720
		val parsedHeight = kv["gfx_height"]?.toIntOrNull() ?: 568
		val useRtg = (kv["gfxcard_size"]?.toIntOrNull() ?: 0) > 0
			|| (kv["rtgmem_size"]?.toIntOrNull() ?: 0) > 0
			|| kv["gfxcard_type"] == "uaegfx"
			|| kv["gfxcard_type"] == "ZorroIII"
			|| kv["rtgmem_type"] == "uaegfx"
			|| kv["rtgmem_type"] == "ZorroIII"
		val androidJoyport1 = kv[UpstreamConfig.KEY_ANDROID_JOYPORT1]
		val joyport1 = when {
			androidJoyport1 == "onscreen_joy" -> "onscreen_joy"
			onScreenJoystick -> "onscreen_joy"
			else -> kv["joyport1"] ?: "none"
		}
		return EmulatorSettings(
			baseModel = guessModel(kv),
			cpuModel = kv["cpu_model"]?.toIntOrNull() ?: 68000,
			cpuCompatible = kv["cpu_compatible"].toBool(true),
			address24Bit = kv["cpu_24bit_addressing"].toBool(true),
			cpuSpeed = kv["cpu_speed"] ?: "real",
			fpuModel = kv["fpu_model"]?.toIntOrNull() ?: 0,
			jitCacheSize = kv["cachesize"]?.toIntOrNull() ?: 0,
			jitFpu = kv["compfpu"].toBool(false),

			chipset = kv["chipset"] ?: "ocs",
			immediateBlits = kv["immediate_blits"].toBool(false),
			collisionLevel = kv["collision_level"] ?: "playfields",
			cycleExact = kv["cycle_exact"].toBool(false),
			ntsc = kv["ntsc"].toBool(false),

			chipRam = kv["chipmem_size"]?.toIntOrNull() ?: 1,
			slowRam = kv["bogomem_size"]?.toIntOrNull() ?: 2,
			fastRam = kv["fastmem_size"]?.toIntOrNull() ?: 0,
			z3Ram = kv["z3mem_size"]?.toIntOrNull() ?: 0,

			romFile = kv["kickstart_rom_file"] ?: "",
			romExtFile = kv["kickstart_ext_rom_file"] ?: "",

			floppy0 = kv["floppy0"] ?: "",
			floppy0Type = kv["floppy0type"]?.toIntOrNull() ?: 0,
			floppy1 = kv["floppy1"] ?: "",
			floppy1Type = kv["floppy1type"]?.toIntOrNull() ?: -1,
			floppy2 = kv["floppy2"] ?: "",
			floppy2Type = kv["floppy2type"]?.toIntOrNull() ?: -1,
			floppy3 = kv["floppy3"] ?: "",
			floppy3Type = kv["floppy3type"]?.toIntOrNull() ?: -1,

			cdImage = normalizeCdImagePath(kv["cdimage0"]),
			whdloadFilename = kv["whdload_filename"] ?: "",
			hardDrives = hardDriveList,

			soundOutput = kv["sound_output"] ?: "exact",
			soundFreq = kv["sound_frequency"]?.toIntOrNull() ?: 44100,
			soundChannels = kv["sound_channels"] ?: "stereo",
			soundStereoSeparation = kv["sound_stereo_separation"]?.toIntOrNull() ?: 7,
			soundInterpolation = kv["sound_interpol"] ?: "anti",

			gfxWidth = if (useRtg) 720 else parsedWidth,
			gfxHeight = if (useRtg) 568 else parsedHeight,
			rtgWidth = if (useRtg) parsedWidth else 1920,
			rtgHeight = if (useRtg) parsedHeight else 1080,
			correctAspect = kv["gfx_correct_aspect"].toBool(true),
			autoCrop = kv["gfx_auto_crop"].toBool(false),
			showLeds = kv["show_leds"].toBool(false),
			useRtg = useRtg,

			joyport0 = kv["joyport0"] ?: "mouse",
			joyport1 = joyport1,
			onScreenJoystick = onScreenJoystick || joyport1 == "onscreen_joy",
			onScreenCd32Pad = kv[UpstreamConfig.KEY_AMIBERRY_ONSCREEN_CD32PAD].toBool(false) || kv[UpstreamConfig.KEY_ONSCREEN_CD32PAD].toBool(false),
			onScreenKeyboard = onScreenKeyboard
		)
	}

	private fun parseAllHardfilePaths(kv: Map<String, String>, lines: List<String>): List<String> {
		val result = mutableListOf<String>()
		for (i in 0 until 10) {
			result.add(parseHardfilePath(lines, "DH$i"))
		}
		kv.forEach { (key, value) ->
			val match = uaehfFileKeyRegex.matchEntire(key) ?: return@forEach
			val physicalUnit = match.groupValues[1].toIntOrNull() ?: return@forEach
			val logicalName = kv["uaehf${physicalUnit}_name"] ?: "DH$physicalUnit"
			val logicalUnit = logicalName.removePrefix("DH").toIntOrNull() ?: physicalUnit
			while (logicalUnit >= result.size) {
				result.add("")
			}
			result[logicalUnit] = value
		}
		// Trim trailing empty entries but keep at least one (DH0)
		while (result.size > 1 && result.last().isEmpty()) result.removeAt(result.size - 1)
		return result
	}

	private fun parseHardfilePath(lines: List<String>, device: String): String {
		val prefix = "rw,$device:"
		val line = lines.firstOrNull { it.startsWith(prefix) } ?: return ""
		val pathStart = line.indexOf('"')
		if (pathStart >= 0) {
			val pathEnd = line.indexOf('"', pathStart + 1)
			if (pathEnd > pathStart) {
				return line.substring(pathStart + 1, pathEnd)
			}
		}
		val afterDevice = line.substringAfter(prefix, "")
		return afterDevice.substringBefore(',').trim()
	}

	private fun normalizeCdImagePath(value: String?): String {
		var normalized = value?.trim().orEmpty()
		while (normalized.endsWith(",image", ignoreCase = true)) {
			normalized = normalized.dropLast(6)
		}
		val extension = normalized.substringAfterLast('.', "").lowercase()
		return normalized.takeIf { extension in FileCategory.CD_IMAGES.extensions }.orEmpty()
	}

	fun guessCategory(settings: EmulatorSettings): ConfigCategory {
		return when {
			settings.whdloadFilename.isNotBlank() -> ConfigCategory.WHDLOAD
			settings.cdImage.isNotBlank() -> ConfigCategory.CD32
			settings.hardDrives.any { it.isNotBlank() } -> ConfigCategory.HDF
			settings.floppy0.isNotBlank() -> ConfigCategory.ADF
			else -> ConfigCategory.GENERIC
		}
	}

	/**
	 * Guess the AmigaModel from chipset + CPU combination.
	 */
	private fun guessModel(kv: Map<String, String>): AmigaModel {
		val cpu = kv["cpu_model"]?.toIntOrNull() ?: 68000
		val chipset = kv["chipset"] ?: "ocs"
		val hasCd = kv["cdimage0"]?.isNotEmpty() == true
		val chipRam = kv["chipmem_size"]?.toIntOrNull() ?: 1
		val slowRam = kv["bogomem_size"]?.toIntOrNull() ?: 0
		val hwPath = kv["config_hardware_path"] ?: ""

		return when {
			chipset == "aga" && cpu >= 68040 -> AmigaModel.A4000
			chipset == "aga" && hasCd -> AmigaModel.CD32
			chipset == "aga" -> AmigaModel.A1200
			chipset == "ecs" && cpu >= 68030 -> AmigaModel.A3000
			chipset == "ecs" && hwPath.contains("A600", ignoreCase = true) -> AmigaModel.A600
			chipset == "ecs" && hwPath.contains("A500", ignoreCase = true) -> AmigaModel.A500_PLUS
			// Without config_hardware_path, A500+ has 1MB chip + no slow RAM,
			// while A600 has 2MB chip + no slow RAM. But both have chipRam=2 in defaults.
			// Default to A500+ (more common) when we can't distinguish.
			chipset == "ecs" -> AmigaModel.A500_PLUS
			hasCd -> AmigaModel.CDTV
			// OCS with 512KB chip + 512KB slow = A500 (or A2000), default A500
			else -> AmigaModel.A500
		}
	}

	private fun String?.toBool(default: Boolean): Boolean {
		if (this == null) return default
		return this == "true" || this == "1" || this == "yes"
	}
}

