package com.uae4arm2026.data

import android.content.Context
import com.uae4arm2026.data.model.AmigaModel
import com.uae4arm2026.data.model.EmulatorSettings
import com.uae4arm2026.data.model.FileCategory
import java.io.File

/**
 * Generates .uae config files from EmulatorSettings.
 * Config key names match cfgfile_save_options() format in cfgfile.cpp.
 */
object ConfigGenerator {

	fun generate(settings: EmulatorSettings): String {
		return generate(settings, { path -> !path.startsWith("content://") && File(path).isDirectory }, ::hasRdbSignature)
	}

	/**
	 * RDB (Rigid Disk Block) partition tables are what AmigaOS's IDE/Gayle boot scan relies on
	 * to auto-mount a hard drive. Raw, RDB-less hardfiles (just a DOS boot block, no partition
	 * table) can only auto-boot when mounted through UAE's own uaehf.device pseudo-controller
	 * ("uae0"/"uae1"), not through emulated real IDE ("ide0"/"ide1") — real IDE requires a real
	 * RDB to be discoverable. Detect this by scanning the first 16 blocks for the "RDSK" magic.
	 */
	fun hasRdbSignature(path: String): Boolean {
		if (path.startsWith("content://")) return true // can't cheaply sniff; assume modern/RDB'd image
		return try {
			File(path).inputStream().use { stream ->
				val buffer = ByteArray(16 * 512)
				val read = stream.read(buffer)
				if (read <= 0) return false
				val magic = byteArrayOf('R'.code.toByte(), 'D'.code.toByte(), 'S'.code.toByte(), 'K'.code.toByte())
				(0..read - magic.size).any { offset ->
					magic.indices.all { i -> buffer[offset + i] == magic[i] }
				}
			}
		} catch (e: Exception) {
			true // if we can't read it, don't second-guess the default (ide) controller
		}
	}

	private fun generate(
		settings: EmulatorSettings,
		isDirectoryPath: (String) -> Boolean,
		hasRdb: (String) -> Boolean = { true }
	): String {
		val sb = StringBuilder()
		val normalizedCdImage = normalizeCdImageValue(settings.cdImage)
		val onScreenJoystick = settings.onScreenJoystick || settings.joyport1 == "onscreen_joy"
		val onScreenKeyboard = settings.onScreenKeyboard
		val androidJoyport1 = settings.joyport1
		val nativeJoyport1 = if (settings.joyport1 == "onscreen_joy") "joy1" else settings.joyport1
		sb.appendLine(UpstreamConfig.GENERATED_BY_HEADER)
		sb.appendLine()

		// CPU
		sb.appendLine("cpu_model=${settings.cpuModel}")
		// "More compatible" + JIT is a known-bad combo: it forces slow/exact instruction paths
		// that make self-modifying-code-heavy software (WHDLoad ROM decrypters, etc.) run
		// orders of magnitude slower — the native core only auto-disables this for 68040+, so
		// force it off here for JIT'd 68020/030 configs too (matches AgsDetector.kt and every
		// hand-tuned bundled *-RTG.uae config).
		val cpuCompatible = settings.cpuCompatible && settings.jitCacheSize == 0
		sb.appendLine("cpu_compatible=${cpuCompatible.toCfg()}")
		sb.appendLine("cpu_24bit_addressing=${settings.address24Bit.toCfg()}")
		sb.appendLine("cpu_speed=${settings.cpuSpeed}")
		if (settings.fpuModel > 0) {
			sb.appendLine("fpu_model=${settings.fpuModel}")
		}
		if (settings.jitCacheSize > 0) {
			sb.appendLine("cachesize=${settings.jitCacheSize}")
			sb.appendLine("compfpu=${settings.jitFpu.toCfg()}")
		}

		// Chipset
		sb.appendLine("chipset=${settings.chipset}")
		when (settings.baseModel) {
			AmigaModel.A600, AmigaModel.A1200 -> sb.appendLine("ide=a600/a1200")
			AmigaModel.A4000 -> sb.appendLine("ide=a4000")
			else -> {}
		}
		sb.appendLine("immediate_blits=${settings.immediateBlits.toCfg()}")
		sb.appendLine("collision_level=${settings.collisionLevel}")
		sb.appendLine("cycle_exact=${settings.cycleExact.toCfg()}")
		sb.appendLine("ntsc=${settings.ntsc.toCfg()}")
		// Platform-specific chipset extensions
		if (settings.baseModel == AmigaModel.CD32) {
			sb.appendLine("chipset_compatible=CD32")
			sb.appendLine("cd32cd=true")
			sb.appendLine("cd32c2p=true")
			sb.appendLine("cd32nvram=true")
			sb.appendLine("cdcon=cd32")
		} else if (settings.baseModel == AmigaModel.CDTV) {
			sb.appendLine("chipset_compatible=CDTV")
			sb.appendLine("cdtv=true")
			sb.appendLine("cdcon=cdtv")
		}

		// Memory
		sb.appendLine("chipmem_size=${settings.chipRam}")
		sb.appendLine("bogomem_size=${settings.slowRam}")
		sb.appendLine("fastmem_size=${settings.fastRam}")
		if (settings.z3Ram > 0) {
			sb.appendLine("z3mem_size=${settings.z3Ram}")
		}

		// RTG
		if (settings.useRtg) {
			// For CD32/A1200, Zorro III requires 32-bit addressing (handled in constraints)
			sb.appendLine("gfxcard_type=ZorroIII")
			sb.appendLine("gfxcard_size=16") // Use 16MB VRAM for RTG
			sb.appendLine("rtg_nocustom=true")
			sb.appendLine("rtg_noautomodes=false")
			sb.appendLine("gfx_fullscreen_picasso=fullwindow")
		} else {
			sb.appendLine("gfxcard_size=0")
			sb.appendLine("rtg_nocustom=false")
		}

		// Kickstart ROM
		if (settings.romFile.isNotEmpty()) {
			sb.appendLine("kickstart_rom_file=${settings.romFile}")
		}
		if (settings.romExtFile.isNotEmpty()) {
			sb.appendLine("kickstart_ext_rom_file=${settings.romExtFile}")
		}

		// Floppy drives
		if (settings.floppy0.isNotEmpty()) sb.appendLine("floppy0=${settings.floppy0}")
		sb.appendLine("floppy0type=${settings.floppy0Type}")
		if (settings.floppy1.isNotEmpty()) sb.appendLine("floppy1=${settings.floppy1}")
		sb.appendLine("floppy1type=${settings.floppy1Type}")
		if (settings.floppy2.isNotEmpty()) sb.appendLine("floppy2=${settings.floppy2}")
		sb.appendLine("floppy2type=${settings.floppy2Type}")
		if (settings.floppy3.isNotEmpty()) sb.appendLine("floppy3=${settings.floppy3}")
		sb.appendLine("floppy3type=${settings.floppy3Type}")
		val numFloppies = if (settings.floppy3Type != -1) 4 
						  else if (settings.floppy2Type != -1) 3 
						  else if (settings.floppy1Type != -1) 2 
						  else if (settings.floppy0Type != -1) 1 
						  else 0
		sb.appendLine("nr_floppies=$numFloppies")

		// CD
		if (normalizedCdImage.isNotEmpty()) {
			// Suffix ',image' is required by Amiberry core for direct image mounting.
			// Use unit 0 and ensure the core knows it's an image.
			sb.appendLine("cdimage0=$normalizedCdImage,image")
			sb.appendLine("cdimage0_present=true")
			sb.appendLine("cdimage0_readonly=true")
		} else if (settings.baseModel == AmigaModel.CD32 || settings.baseModel == AmigaModel.CDTV) {
			// Required for CD console models even if no image is present to avoid BIOS loop
			sb.appendLine("cdimage0_present=false")
		}
		if (settings.baseModel == AmigaModel.CD32 && settings.cd32Fmv) {
			// Real CD32 "Full Motion Video" MPEG decoder cartridge add-on
			sb.appendLine("cd32fmv=true")
		}

		// WHDLoad
		if (settings.whdloadFilename.isNotEmpty()) {
			sb.appendLine("whdload_filename=${settings.whdloadFilename}")
		}

		// Hard drives
		var physicalUnit = 0
		var bootPriSet = false
		settings.hardDrives.forEachIndexed { i, path ->
			if (path.isNotEmpty()) {
				val isDir = isDirectoryPath(path)
				val name = File(path).name.ifBlank { "DH$i" }
				
				// Only first non-empty drive is bootable (priority 0)
				val bootPri = if (!bootPriSet) 0 else -128
				bootPriSet = true

				if (isDir) {
					// Directory drive — use the robust filesystem2 format
					sb.appendLine("filesystem2=rw,DH$i:$name:\"$path\",$bootPri")
				} else {
					// HDF drive — use the robust hardfile2 format that supports controller mapping
					// Format: rw,devname:path,sectors,heads,reserved,blocksize,bootpri,filesys,controller
					// RDB-less hardfiles can't auto-boot through emulated real IDE — fall back to
					// UAE's own uaehf.device controller for those (see hasRdbSignature).
					val rdbPresent = hasRdb(path)
					val controller = when {
						!rdbPresent -> "uae$physicalUnit"
						settings.baseModel == AmigaModel.A600 || settings.baseModel == AmigaModel.A1200 || settings.baseModel == AmigaModel.A4000 -> "ide$physicalUnit"
						else -> "uae$physicalUnit"
					}
					// With a real RDB, UAE can auto-detect geometry (0,0,0). Without one, UAE needs
					// an explicit CHS (surfaces=1, sectors=32, reserved=2) to synthesize a single
					// bootable partition — otherwise mounting fails with "no supported partition
					// tables detected", even via uaehf.device.
					val geometry = if (rdbPresent) "0,0,0" else "32,1,2"
					// We use uaehf.device as the filesys name; the controller mapping will handle the actual device binding in the core.
					sb.appendLine("hardfile2=rw,DH$i:\"$path\",$geometry,512,$bootPri,uaehf.device,$controller")
				}
				physicalUnit++
			}
		}

		// Sound
		sb.appendLine("sound_output=${settings.soundOutput}")
		sb.appendLine("sound_frequency=${settings.soundFreq}")
		sb.appendLine("sound_channels=${settings.soundChannels}")
		sb.appendLine("sound_stereo_separation=${settings.soundStereoSeparation}")
		sb.appendLine("sound_interpol=${settings.soundInterpolation}")

		// Misc
		sb.appendLine("bsdsocket_emu=true")

		// Display
		val activeWidth = if (settings.useRtg) settings.rtgWidth else settings.gfxWidth
		val activeHeight = if (settings.useRtg) settings.rtgHeight else settings.gfxHeight
		sb.appendLine("gfx_width=$activeWidth")
		sb.appendLine("gfx_height=$activeHeight")
		sb.appendLine("gfx_fullscreen_amiga=fullwindow")
		sb.appendLine("gfx_correct_aspect=${settings.correctAspect.toCfg()}")
		sb.appendLine("gfx_auto_crop=${settings.autoCrop.toCfg()}")
		sb.appendLine("show_leds=${settings.showLeds.toCfg()}")

		// Input
		sb.appendLine("joyport0=${settings.joyport0}")
		sb.appendLine("joyport1=$nativeJoyport1")
		// A CD32 needs its control port explicitly in CD32-pad mode. Without joyport1mode=cd32joy
		// the port stays a plain 2-button Atari-style joystick, so CD32 titles - which poll the
		// pad's shift-register protocol for the red/blue/green/yellow/play/fwd/rew buttons - see
		// no usable controller at all (not just "missing extra buttons"). joyportmodes in
		// cfgfile.cpp is the authority for this string.
		if (settings.baseModel == AmigaModel.CD32) {
			sb.appendLine("joyport1mode=cd32joy")
		}
		sb.appendLine("${UpstreamConfig.KEY_ANDROID_JOYPORT1}=$androidJoyport1")

		// Upstream Android compatibility keys that must remain stable for the core.
		sb.appendLine("${UpstreamConfig.KEY_TOUCH_SETTINGS_VERSION}=${UpstreamConfig.TOUCH_SETTINGS_VERSION}")
		
		// Force native on-screen joystick and keyboard OFF. We use our own Android overlays.
		sb.appendLine("${UpstreamConfig.KEY_ONSCREEN_JOYSTICK}=false")
		sb.appendLine("${UpstreamConfig.KEY_AMIBERRY_ONSCREEN_JOYSTICK}=false")
		sb.appendLine("${UpstreamConfig.KEY_ONSCREEN_CD32PAD}=false")
		sb.appendLine("${UpstreamConfig.KEY_AMIBERRY_ONSCREEN_CD32PAD}=false")
		sb.appendLine("${UpstreamConfig.KEY_VIRTUAL_KEYBOARD_ENABLED}=false")
		sb.appendLine("${UpstreamConfig.KEY_DEFAULT_OSK}=false")
		
		sb.appendLine("${UpstreamConfig.KEY_SHOW_ANDROID_KEYBOARD_BUTTON}=${onScreenKeyboard.toCfg()}")

		// Skip GUI when launched from Android native UI
		sb.appendLine("use_gui=no")

		return sb.toString()
	}

	fun writeConfig(context: Context, settings: EmulatorSettings, filename: String): File {
		val confDir = File(context.getExternalFilesDir(null), "conf")
		if (!confDir.exists()) confDir.mkdirs()
		val file = File(confDir, filename)
		val normalizedSettings = settings.copy(
			romFile = MediaPathHelper.normalizeLaunchPath(context, settings.romFile),
			romExtFile = MediaPathHelper.normalizeLaunchPath(context, settings.romExtFile),
			floppy0 = MediaPathHelper.normalizeLaunchPath(context, settings.floppy0),
			floppy1 = MediaPathHelper.normalizeLaunchPath(context, settings.floppy1),
			floppy2 = MediaPathHelper.normalizeLaunchPath(context, settings.floppy2),
			floppy3 = MediaPathHelper.normalizeLaunchPath(context, settings.floppy3),
			cdImage = MediaPathHelper.normalizeLaunchPath(context, settings.cdImage),
			hardDrives = settings.hardDrives.map { MediaPathHelper.normalizeLaunchPath(context, it) }
		)
		file.writeText(generate(
			normalizedSettings,
			{ path -> MediaPathHelper.isDirectoryPath(context, path) },
			::hasRdbSignature
		))
		return file
	}

	/**
	 * Write config and return the args needed to launch emulation with it.
	 * Uses --model for base hardware, plus --config for overrides.
	 */
	fun generateLaunchArgs(context: Context, settings: EmulatorSettings): Array<String> {
		val configFile = writeConfig(context, settings, ".current_settings.uae")
		return arrayOf(
			"--rescan-roms",
			"--model", settings.baseModel.cmdArg,
			"--config", configFile.absolutePath,
			"-G"
		)
	}

	private fun Boolean.toCfg(): String = if (this) "true" else "false"

	private fun normalizeCdImageValue(value: String): String {
		var normalized = value.trim()
		while (normalized.endsWith(",image", ignoreCase = true)) {
			normalized = normalized.dropLast(6)
		}
		return normalized.takeIf(::isSupportedCdImagePath).orEmpty()
	}

	private fun isSupportedCdImagePath(path: String): Boolean {
		val extension = path.substringAfterLast('.', "").lowercase()
		return extension in FileCategory.CD_IMAGES.extensions
	}
}
