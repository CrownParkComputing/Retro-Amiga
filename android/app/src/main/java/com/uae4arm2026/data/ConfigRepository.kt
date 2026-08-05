package com.uae4arm2026.data

import android.content.Context
import com.uae4arm2026.data.model.AmigaModel
import com.uae4arm2026.data.model.EmulatorSettings
import java.io.File
import java.io.IOException

// Declaration order drives the Configurations screen's filter-tab order.
enum class ConfigCategory { ADF, WHDLOAD, CD32, HDF, GENERIC }

data class ConfigInfo(
	val path: String,
	val name: String,
	val lastModified: Long,
	val description: String,
	val category: ConfigCategory = ConfigCategory.GENERIC,
	val model: AmigaModel = AmigaModel.A500,
	val validationError: String? = null
)

class ConfigRepository(private val context: Context) {

	private val confDir: File
		get() = File(context.getExternalFilesDir(null), "conf").also {
			if (!it.exists()) it.mkdirs()
		}

	fun listConfigs(): List<ConfigInfo> {
		return confDir.listFiles { f -> f.extension == "uae" && !f.name.startsWith(".") }
			?.map { file ->
				val parsed = ConfigParser.parse(file)
				val settings = parsed.settings
				
				var error: String? = null
				val missingFiles = mutableListOf<String>()

				if (settings.romFile.isNotBlank() && !MediaPathHelper.canAccessPath(context, settings.romFile)) {
					missingFiles.add("ROM: ${settings.romFile.substringAfterLast('/')}")
				}
				if (settings.romExtFile.isNotBlank() && !MediaPathHelper.canAccessPath(context, settings.romExtFile)) {
					missingFiles.add("Ext ROM: ${settings.romExtFile.substringAfterLast('/')}")
				}
				if (settings.floppy0.isNotBlank() && !MediaPathHelper.canAccessPath(context, settings.floppy0)) {
					missingFiles.add("Disk: ${settings.floppy0.substringAfterLast('/')}")
				}
				if (settings.cdImage.isNotBlank() && !MediaPathHelper.canAccessPath(context, settings.cdImage)) {
					missingFiles.add("CD: ${settings.cdImage.substringAfterLast('/')}")
				}
				if (settings.whdloadFilename.isNotBlank() && !MediaPathHelper.canAccessPath(context, settings.whdloadFilename)) {
					missingFiles.add("LHA: ${settings.whdloadFilename.substringAfterLast('/')}")
				}
				settings.hardDrives.filter { it.isNotBlank() }.forEach { hdf ->
					if (!MediaPathHelper.canAccessPath(context, hdf)) {
						missingFiles.add("Drive: ${hdf.substringAfterLast('/')}")
					}
				}

				if (missingFiles.isNotEmpty()) {
					error = "Missing: " + missingFiles.joinToString(", ")
				}

				ConfigInfo(
					path = file.absolutePath,
					name = file.nameWithoutExtension,
					lastModified = file.lastModified(),
					description = parsed.description,
					category = ConfigParser.guessCategory(parsed.settings),
					model = parsed.settings.baseModel,
					validationError = error
				)
			}
			?.sortedByDescending { it.lastModified }
			?: emptyList()
	}

	fun loadConfig(path: String): ConfigParser.ParsedConfig {
		return ConfigParser.parse(File(path))
	}

	fun saveConfig(settings: EmulatorSettings, name: String, unknownLines: List<String> = emptyList(), description: String = ""): File? {
		val safeName = name.trim()
		if (!isValidConfigName(safeName)) return null

		return try {
			val file = ConfigGenerator.writeConfig(context, settings, "$safeName.uae")
			val preservedUnknownLines = ConfigParser.sanitizeUnknownLines(unknownLines)

			// Append description if provided
			if (description.isNotBlank()) {
				file.appendText("config_description=$description\n")
			}

			// Append preserved unknown lines from original config
			if (preservedUnknownLines.isNotEmpty()) {
				file.appendText("\n; Preserved settings from original config\n")
				preservedUnknownLines.forEach { file.appendText("$it\n") }
			}

			file
		} catch (_: IOException) {
			null
		}
	}

	/**
	 * Controller port assignment (which real controller/mouse/on-screen control drives JOY0/JOY1)
	 * is a per-device preference, not really a per-game one - a mismatched port assignment just
	 * means "my controller doesn't work" in whichever game doesn't happen to match whatever was
	 * selected when that particular config was last saved. Changing it in Settings rewrites every
	 * saved config on disk so they all agree, rather than only the config currently being edited.
	 * Returns the number of configs successfully updated.
	 */
	fun updateJoyportsForAllConfigs(joyport0: String, joyport1: String, onScreenJoystick: Boolean): Int {
		var updated = 0
		confDir.listFiles { f -> f.extension == "uae" && !f.name.startsWith(".") }?.forEach { file ->
			try {
				val parsed = ConfigParser.parse(file)
				val patched = parsed.settings.copy(
					joyport0 = joyport0,
					joyport1 = joyport1,
					onScreenJoystick = onScreenJoystick
				)
				if (saveConfig(patched, file.nameWithoutExtension, parsed.unknownLines, parsed.description) != null) {
					updated++
				}
			} catch (_: IOException) {
				// Skip configs that fail to parse/save - leave them untouched rather than lose data.
			}
		}
		return updated
	}

	/**
	 * Validate that a config name is safe for use as a filename.
	 * Rejects path separators, parent directory references, and blank names.
	 */
	fun isValidConfigName(name: String): Boolean {
		if (name.isBlank()) return false
		if (name.contains('/') || name.contains('\\') || name.contains("..")) return false
		return try {
			val testFile = File(confDir, "$name.uae")
			testFile.parentFile?.canonicalPath == confDir.canonicalPath
		} catch (_: IOException) {
			false
		}
	}

	fun deleteConfig(path: String): Boolean {
		return File(path).delete()
	}

	fun renameConfig(path: String, newName: String): File? {
		val safeName = newName.trim()
		if (!isValidConfigName(safeName)) return null
		val oldFile = File(path)
		if (!oldFile.exists()) return null
		val newFile = File(oldFile.parentFile, "$safeName.uae")
		return if (oldFile.renameTo(newFile)) newFile else null
	}

	fun duplicateConfig(path: String, newName: String): File? {
		val safeName = newName.trim()
		if (!isValidConfigName(safeName)) return null
		val source = File(path)
		if (!source.exists()) return null
		val target = File(source.parentFile, "$safeName.uae")
		return try {
			source.copyTo(target, overwrite = false)
			target
		} catch (_: IOException) {
			null
		}
	}

	companion object {
		@Volatile
		private var instance: ConfigRepository? = null

		fun getInstance(context: Context): ConfigRepository {
			return instance ?: synchronized(this) {
				instance ?: ConfigRepository(context.applicationContext).also { instance = it }
			}
		}
	}
}

