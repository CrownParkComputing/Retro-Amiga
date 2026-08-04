package com.uae4arm2026.ui.viewmodel

import android.app.Application
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.uae4arm2026.data.AppPreferences
import com.uae4arm2026.data.ConfigGenerator
import com.uae4arm2026.data.FileRepository
import com.uae4arm2026.data.MediaPathHelper
import java.io.File
import com.uae4arm2026.data.model.AmigaFile
import com.uae4arm2026.data.model.AmigaModel
import com.uae4arm2026.data.model.EmulatorSettings
import com.uae4arm2026.data.ConfigParser
import com.uae4arm2026.ui.hasTouchScreen
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch
import org.json.JSONObject

class SettingsViewModel(application: Application) : AndroidViewModel(application) {

	private val repository = FileRepository.getInstance(application)

	var settings by mutableStateOf(EmulatorSettings())
		private set

	var currentUnknownLines by mutableStateOf<List<String>>(emptyList())
		private set

	var currentConfigName by mutableStateOf<String?>(null)
		private set

	val availableRoms: StateFlow<List<AmigaFile>> = repository.roms
	val availableFloppies: StateFlow<List<AmigaFile>> = repository.floppies
	val availableHardDrives: StateFlow<List<AmigaFile>> = repository.hardDrives
	val availableCds: StateFlow<List<AmigaFile>> = repository.cdImages
	private val romIdCacheByPath = mutableMapOf<String, Int?>()

	init {
		restoreLastSession()
		val constrainedSettings = applyConstraints(settings)
		if (constrainedSettings != settings) {
			settings = constrainedSettings
			saveLastSession()
		} else {
			settings = constrainedSettings
		}
		viewModelScope.launch {
			repository.rescan()
			autoSelectDefaultRomIfNeeded(availableRoms.value)
		}
		// Re-run whenever the library is rescanned (e.g. after setup wizard or folder change)
		viewModelScope.launch {
			availableRoms.collect { roms ->
				autoSelectDefaultRomIfNeeded(roms)
			}
		}
	}

	private fun restoreLastSession() {
		val confDir = File(getApplication<Application>().getExternalFilesDir(null), "conf")
		val sessionFile = File(confDir, LAST_SESSION_FILE)
		if (!sessionFile.exists()) return
		try {
			val parsed = ConfigParser.parse(sessionFile)
			settings = ConfigParser.migrateLegacyManagedSettings(sessionFile, parsed.settings)
			currentUnknownLines = ConfigParser.sanitizeUnknownLines(parsed.unknownLines)
		} catch (_: Exception) {
			// Corrupted session file — start with defaults
		}
	}

	private fun saveLastSession() {
		viewModelScope.launch(kotlinx.coroutines.Dispatchers.IO) {
			try {
				ConfigGenerator.writeConfig(getApplication(), settings, LAST_SESSION_FILE)
			} catch (_: Exception) {
				// Non-critical — settings persistence is best-effort
			}
		}
	}

	fun applyModel(model: AmigaModel) {
		val selectedRoms = selectRomsForModel(model, availableRoms.value)
		val newSettings = EmulatorSettings.fromModel(model).copy(
			onScreenJoystick = settings.onScreenJoystick,
			onScreenKeyboard = settings.onScreenKeyboard,
			joyport0 = settings.joyport0,
			joyport1 = if (settings.onScreenJoystick) "onscreen_joy" else settings.joyport1,
			gfxWidth = settings.gfxWidth,
			gfxHeight = settings.gfxHeight,
			rtgWidth = settings.rtgWidth,
			rtgHeight = settings.rtgHeight,
			correctAspect = settings.correctAspect,
			autoCrop = settings.autoCrop,
			showLeds = settings.showLeds,
			useRtg = settings.useRtg,
			romFile = selectedRoms.kick?.path.orEmpty(),
			romExtFile = selectedRoms.ext?.path.orEmpty(),
			cdImage = if (model.hasCd) settings.cdImage else "",
			floppy0 = if (model.hasFloppy) settings.floppy0 else "",
			floppy1 = if (model.hasFloppy) settings.floppy1 else "",
			hardDrives = settings.hardDrives,
		)
		settings = applyConstraints(newSettings)
		saveLastSession()
	}

	fun loadConfig(parsed: ConfigParser.ParsedConfig, name: String? = null) {
		settings = applyConstraints(parsed.settings)
		currentUnknownLines = ConfigParser.sanitizeUnknownLines(parsed.unknownLines)
		currentConfigName = name
		autoSelectDefaultRomIfNeeded(availableRoms.value)
		saveLastSession()
	}

	private fun autoSelectDefaultRomIfNeeded(roms: List<AmigaFile>) {
		if (roms.isEmpty()) return

		val context = getApplication<Application>()
		val model = settings.baseModel
		// CD32 and CDTV require an extended ROM in addition to the Kickstart.
		// Always re-check the ext ROM for these models so it gets filled in even
		// when the kick ROM was already set (e.g. carried over from a previous session).
		val needsExt = model == AmigaModel.CD32 || model == AmigaModel.CDTV
		val extRomMissing = needsExt && !MediaPathHelper.canAccessPath(context, settings.romExtFile)

		// Check if current ROM and floppy files still exist.
		if (MediaPathHelper.canAccessPath(context, settings.romFile) && !extRomMissing) {
			if (settings.floppy0.isBlank() || MediaPathHelper.canAccessPath(context, settings.floppy0)) return
		}

		val selectedRoms = selectRomsForModel(model, roms)
		// Prefer a CRC-matched Kickstart; fall back to the first available ROM file
		// so users with unrecognised or custom ROMs aren't left with a blank kickstart.
		// EXCLUDE "amigavision" from generic fallbacks as it is specialized.
		val kickPath = selectedRoms.kick?.path
			?: roms.firstOrNull { 
				it.extension == "rom" && !it.name.lowercase().contains("amigavision") 
			}?.path
			?: roms.firstOrNull { 
				!it.name.lowercase().contains("amigavision") 
			}?.path

		var updated = settings
		if (settings.romFile.isBlank() && kickPath != null) {
			updated = updated.copy(romFile = kickPath)
		}
		if (extRomMissing && selectedRoms.ext?.path != null) {
			updated = updated.copy(romExtFile = selectedRoms.ext.path)
		}
		if (updated == settings) return

		settings = applyConstraints(updated)
		// Persist so the selection survives a restart
		saveLastSession()
	}

	private fun selectRomsForModel(model: AmigaModel, roms: List<AmigaFile>): SelectedRoms {
		val filteredRoms = roms.filter { !it.name.lowercase().contains("amigavision") }
		if (filteredRoms.isEmpty()) return SelectedRoms(null, null)
		val profile = MODEL_ROM_PROFILE[model] ?: return SelectedRoms(null, null)

		// First, try to find a CRC-matched Kickstart
		val romsWithIds = filteredRoms.map { it to detectRomId(it) }
		
		val crcMatchedKick = profile.kickIds.firstNotNullOfOrNull { id ->
			romsWithIds.filter { it.second == id }.map { it.first }.sortedBy { it.name.lowercase() }.firstOrNull()
		}

		if (crcMatchedKick != null) {
			val ext = findExtRom(model, profile, romsWithIds, profile.kickIds.first { id -> 
				romsWithIds.any { it.first == crcMatchedKick && it.second == id } 
			})
			return SelectedRoms(crcMatchedKick, ext)
		}

		// Fallback: Try to match by filename if no CRC match found
		val modelKeywords = MODEL_KEYWORDS[model] ?: emptyList()

		val nameMatchedKick = roms.filter { rom ->
			val name = rom.name.lowercase()
			modelKeywords.any { name.contains(it) } && !name.contains("ext")
		}.sortedBy { it.name.lowercase() }.firstOrNull()

		if (nameMatchedKick != null) {
			val ext = findExtRom(model, profile, romsWithIds, -1) // -1 since not a CRC match
			return SelectedRoms(nameMatchedKick, ext)
		}

		return SelectedRoms(null, null)
	}

	private fun findExtRom(
		model: AmigaModel, 
		profile: ModelRomProfile, 
		romsWithIds: List<Pair<AmigaFile, Int?>>,
		selectedKickId: Int
	): AmigaFile? {
		return when (model) {
			AmigaModel.CD32 -> {
				if (selectedKickId == 64) null
				else {
					// Try CRC first
					val crcExt = profile.extIds.firstNotNullOfOrNull { id ->
						romsWithIds.filter { it.second == id }.map { it.first }.sortedBy { it.name.lowercase() }.firstOrNull()
					}
					// Fallback to filename
					crcExt ?: romsWithIds.map { it.first }.filter { 
						val name = it.name.lowercase()
						name.contains("cd32") && name.contains("ext")
					}.sortedBy { it.name.lowercase() }.firstOrNull()
				}
			}
			AmigaModel.CDTV -> {
				val crcExt = profile.extIds.firstNotNullOfOrNull { id ->
					romsWithIds.filter { it.second == id }.map { it.first }.sortedBy { it.name.lowercase() }.firstOrNull()
				}
				crcExt ?: romsWithIds.map { it.first }.filter { 
					val name = it.name.lowercase()
					name.contains("cdtv") && name.contains("ext")
				}.sortedBy { it.name.lowercase() }.firstOrNull()
			}
			else -> null
		}
	}

	fun detectRomId(rom: AmigaFile): Int? {
		return romIdCacheByPath.getOrPut(rom.path) {
			val crc = rom.crc32 ?: return@getOrPut null
			ROM_CRC_TO_ID[crc and 0xffffffffL]
		}
	}

	private fun pickDeterministic(candidates: List<AmigaFile>): AmigaFile? {
		return candidates.sortedBy { it.name.lowercase() }.firstOrNull()
	}

	data class SelectedRoms(
		val kick: AmigaFile?,
		val ext: AmigaFile?
	)

	data class ModelRomProfile(
		val kickIds: List<Int>,
		val extIds: List<Int> = emptyList()
	)

	companion object {
		private const val LAST_SESSION_FILE = ".last_session.uae"

		/**
		 * Exact --model ROM priority behavior from main.cpp wrappers:
		 * A500->bip_a500(130), A500P->bip_a500plus(-1), A2000->bip_a2000(130), etc.
		 */
		val MODEL_ROM_PROFILE = mapOf(
			AmigaModel.A500 to ModelRomProfile(kickIds = listOf(6, 5, 4)),
			AmigaModel.A500_PLUS to ModelRomProfile(kickIds = listOf(7, 6, 5)),
			AmigaModel.A600 to ModelRomProfile(kickIds = listOf(10, 9, 8)),
			AmigaModel.A1000 to ModelRomProfile(kickIds = listOf(24)),
			AmigaModel.A2000 to ModelRomProfile(kickIds = listOf(6, 5, 4)),
			AmigaModel.A3000 to ModelRomProfile(kickIds = listOf(59)),
			AmigaModel.A1200 to ModelRomProfile(kickIds = listOf(11, 15, 276, 281, 286, 291, 304)),
			AmigaModel.A4000 to ModelRomProfile(kickIds = listOf(16, 31, 13, 12, 46, 278, 283, 288, 293, 306)),
			AmigaModel.CD32 to ModelRomProfile(kickIds = listOf(64, 18), extIds = listOf(19)),
			AmigaModel.CDTV to ModelRomProfile(kickIds = listOf(6, 32), extIds = listOf(20, 21, 22))
		)

		val MODEL_KEYWORDS = mapOf(
			AmigaModel.A500 to listOf("a500", "kick13"),
			AmigaModel.A500_PLUS to listOf("a500plus", "a500+", "kick204"),
			AmigaModel.A600 to listOf("a600", "kick205", "kick37"),
			AmigaModel.A1000 to listOf("a1000"),
			AmigaModel.A2000 to listOf("a2000"),
			AmigaModel.A3000 to listOf("a3000"),
			AmigaModel.A1200 to listOf("a1200", "kick30", "kick31"),
			AmigaModel.A4000 to listOf("a4000"),
			AmigaModel.CD32 to listOf("cd32"),
			AmigaModel.CDTV to listOf("cdtv")
		)

		// CRC32 -> ROM ID mapping for the ids used above.
		private val ROM_CRC_TO_ID: Map<Long, Int> = mapOf(
			0x9ed783d0L to 4,
			0xa6ce1636L to 5,
			0xc4f0f55fL to 6,
			0xc3bdb240L to 7,
			0x83028fb5L to 8,
			0x64466c2aL to 9,
			0x43b0df7bL to 10,
			0x6c9b07d2L to 11,
			0x9e6ac152L to 12,
			0x2b4566f1L to 13,
			0x1483a091L to 15,
			0xd6bae334L to 16,
			0x1e62d4a5L to 18,
			0x87746be2L to 19,
			0x42baa124L to 20,
			0x30b54232L to 21,
			0xceae68d2L to 22,
			0x0b1ad2d0L to 24,
			0x43b6dd22L to 31,
			0xe0f37258L to 32,
			0xbc0ec13fL to 59,
			0xf5d4f3c8L to 64,
			0xf17fa97fL to 276,
			0xd47e18fdL to 278,
			0xb87506a7L to 281,
			0x1b84cb33L to 283,
			0xbd1ff75eL to 286,
			0x9bb8fc93L to 288,
			0x2b653371L to 291,
			0xf3ced3b8L to 293,
			0x5c40328aL to 304,
			0x4bea9798L to 306,
		)
	}

	fun updateSettings(transform: (EmulatorSettings) -> EmulatorSettings) {
		val newSettings = transform(settings)
		settings = applyConstraints(newSettings)
		saveLastSession()
	}

	fun rescan() {
		viewModelScope.launch {
			repository.rescan()
		}
	}

	fun getCompatibleRoms(model: AmigaModel): List<AmigaFile> {
		val profile = MODEL_ROM_PROFILE[model] ?: return emptyList()
		val modelKeywords = MODEL_KEYWORDS[model] ?: emptyList()
		
		return availableRoms.value.filter { rom ->
			val romId = detectRomId(rom)
			val name = rom.name.lowercase()
			val matchesCrc = romId != null && (romId in profile.kickIds || romId in profile.extIds)
			val matchesName = modelKeywords.any { name.contains(it) } && !name.contains("ext")
			
			matchesCrc || matchesName
		}
	}

	fun generateLaunchArgs(): Array<String> {
		val configFile = ConfigGenerator.writeConfig(getApplication(), settings, ".current_settings.uae")
		// Record in recent launches so FAB launches are replayable
		AppPreferences.getInstance(getApplication()).addRecentLaunch(JSONObject().apply {
			put("type", "quickstart")
			put("model", settings.baseModel.cmdArg)
			put("df0", settings.floppy0)
			put("df1", settings.floppy1)
			put("cd", settings.cdImage)
			put("hd", settings.hardDrives.firstOrNull { it.isNotBlank() } ?: "")
			put("romExtFile", settings.romExtFile)
		})
		return arrayOf(
			"--rescan-roms",
			"--model", settings.baseModel.cmdArg,
			"--config", configFile.absolutePath,
			"-G"
		)
	}

	/**
	 * Enforce hardware constraints between interdependent settings.
	 */
	private fun applyConstraints(s: EmulatorSettings): EmulatorSettings {
		var result = s

		if (result.baseModel == AmigaModel.CD32 || result.baseModel == AmigaModel.CDTV) {
			result = result.copy(useRtg = false, z3Ram = 0)
		}

		// 68000/68010 must use 24-bit addressing
		if (result.cpuModel <= 68010) {
			result = result.copy(address24Bit = true, z3Ram = 0, jitCacheSize = 0)
		}

		// Cycle-exact forces real speed and disables JIT
		if (result.cycleExact) {
			result = result.copy(cpuSpeed = "real", jitCacheSize = 0)
		}

		if (result.jitCacheSize > 0) {
			if (result.cpuModel < 68020) {
				result = result.copy(jitCacheSize = 0, jitFpu = false)
			} else {
				// JIT forces fastest possible speed and disables cycle-exact
				result = result.copy(cpuSpeed = "max", cycleExact = false, address24Bit = false)
			}
		}

		// RTG or Z3 RAM requires 32-bit addressing
		if (result.useRtg || result.z3Ram > 0) {
			result = result.copy(address24Bit = false)
		}

		// 24-bit addressing disables JIT and RTG
		if (result.address24Bit) {
			result = result.copy(jitCacheSize = 0, useRtg = false)
		}

		// FPU: only internal for 68040/68060
		if (result.fpuModel == 68040 && result.cpuModel < 68040) {
			result = result.copy(fpuModel = 0)
		}

		return result
	}
}

