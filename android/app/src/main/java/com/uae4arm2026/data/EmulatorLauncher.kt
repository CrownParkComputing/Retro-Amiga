package com.uae4arm2026.data

import android.content.Context
import android.content.Intent
import android.net.Uri
import com.uae4arm2026.Uae4ArmEmulatorActivity
import com.uae4arm2026.data.model.EmulatorSettings
import com.uae4arm2026.data.model.AmigaModel
import com.uae4arm2026.data.model.FileCategory
import org.json.JSONObject
import java.io.File

object EmulatorLauncher {
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

	/**
	 * Launch emulation with a Quick Start model and optional media.
	 * Uses --model + -0/-s for floppy/CD, plus -G to skip ImGui GUI.
	 */
	fun launchQuickStart(
		context: Context,
		model: AmigaModel,
		floppyPath: String? = null,
		floppy1Path: String? = null,
		cdPath: String? = null,
		hardDrivePath: String? = null,
		useRtg: Boolean = false,
		romExtFile: String? = null
	) {
		val args = mutableListOf("--rescan-roms", "--model", model.cmdArg)
		val launchFloppy0 = floppyPath?.let { MediaPathHelper.normalizeLaunchPath(context, it) }
		val launchFloppy1 = floppy1Path?.let { MediaPathHelper.normalizeLaunchPath(context, it) }
		val launchCd = cdPath?.let { MediaPathHelper.normalizeLaunchPath(context, it) }
		val normalizedLaunchCd = launchCd?.let(::normalizeCdImageValue).orEmpty()
		val launchHardDrive = hardDrivePath?.let { MediaPathHelper.normalizeLaunchPath(context, it) }
		val launchExtRom = romExtFile?.let { MediaPathHelper.normalizeLaunchPath(context, it) }

		if (launchFloppy0 != null && model.hasFloppy) {
			args.addAll(listOf("-0", launchFloppy0))
		}
		if (launchFloppy1 != null && model.hasFloppy) {
			args.addAll(listOf("-1", launchFloppy1))
		}
		if (normalizedLaunchCd.isNotEmpty() && model.hasCd) {
			args.addAll(listOf("-s", "cdimage0=$normalizedLaunchCd,image"))
		}
		if (!launchExtRom.isNullOrBlank() && model.hasCd) {
			args.addAll(listOf("-s", "kickstart_ext_rom_file=$launchExtRom"))
		}
		if (launchHardDrive != null) {
			if (MediaPathHelper.isDirectoryPath(context, launchHardDrive)) {
				val name = File(launchHardDrive).name.ifBlank { "DH0" }
				args.addAll(listOf("-s", "filesystem2=rw,DH0:$name:\"$launchHardDrive\",0"))
			} else {
				val geometry = if (ConfigGenerator.hasRdbSignature(launchHardDrive)) "0,0,0" else "32,1,2"
				args.addAll(listOf("-s", "hardfile2=rw,DH0:\"$launchHardDrive\",$geometry,512,0"))
			}
		}
		if (useRtg) {
			args.addAll(listOf("-s", "gfxcard_type=ZorroIII"))
			args.addAll(listOf("-s", "gfxcard_size=8"))
		}

		args.add("-G") // Skip ImGui GUI, start emulation directly

		// Track recent launch
		AppPreferences.getInstance(context).addRecentLaunch(JSONObject().apply {
			put("type", "quickstart")
			put("model", model.cmdArg)
			put("df0", floppyPath ?: "")
			put("df1", floppy1Path ?: "")
			put("cd", cdPath ?: "")
			put("hd", hardDrivePath ?: "")
			put("romExtFile", romExtFile ?: "")
		})

		launchSdlActivity(context, args.toTypedArray())
	}

	/**
	 * Launch emulation from a saved .uae config file.
	 */
	fun launchWithConfig(context: Context, configPath: String, skipGui: Boolean = true) {
		val args = mutableListOf("--rescan-roms", "--config", configPath)
		
		// UAE4ARM 2026: If it's a WHDLoad config, we must also pass --autoload to trigger the internal booter.
		// We use a simple line-based scan to avoid parsing the full config if not needed.
		try {
			val file = File(configPath)
			if (file.exists()) {
				val whdLine = file.useLines { lines -> lines.find { it.startsWith("whdload_filename=") } }
				whdLine?.substringAfter('=')?.trim()?.takeIf { it.isNotBlank() }?.let { lhaPath ->
					args.addAll(listOf("--autoload", lhaPath))
				}
			}
		} catch (e: Exception) {
			android.util.Log.w("Uae4Arm-Launcher", "Failed to check for whdload_filename in config", e)
		}

		if (skipGui) args.add("-G")

		AppPreferences.getInstance(context).addRecentLaunch(JSONObject().apply {
			put("type", "config")
			put("path", configPath)
		})
		launchSdlActivity(context, args.toTypedArray())
	}

	/**
	 * Launch a WHDLoad game via the --autoload mechanism.
	 * The emulator auto-configures based on its XML database match.
	 */
	fun launchWhdload(context: Context, lhaPath: String) {
		val launchPath = MediaPathHelper.normalizeLaunchPath(context, lhaPath)
		val args = arrayOf("--rescan-roms", "--autoload", launchPath, "-G")
		AppPreferences.getInstance(context).addRecentLaunch(JSONObject().apply {
			put("type", "whdload")
			put("path", launchPath)
		})
		launchSdlActivity(context, args)
	}

	fun launchWhdload(context: Context, lhaPath: String, settings: EmulatorSettings) {
		val launchPath = MediaPathHelper.normalizeLaunchPath(context, lhaPath)
		val configFile = ConfigGenerator.writeConfig(context, settings, ".current_settings.uae")
		val args = arrayOf("--rescan-roms", "--config", configFile.absolutePath, "--autoload", launchPath, "-G")
		AppPreferences.getInstance(context).addRecentLaunch(JSONObject().apply {
			put("type", "whdload")
			put("path", launchPath)
		})
		launchSdlActivity(context, args)
	}

	/**
	 * Launch emulation with pre-built args (used by SettingsScreen).
	 */
	fun launchWithArgs(context: Context, args: Array<String>) {
		launchSdlActivity(context, args)
	}

	private const val SESSION_MARKER = ".emulator_session"
	private const val CLEAN_EXIT_MARKER = ".clean_exit"
	private const val PENDING_LAUNCH_MARKER = ".pending_emulator_launch"

	/**
	 * @param trackSession If true, writes a crash-detection marker and marks the
	 *                     launch for review-prompt tracking. Set to false for
	 *                     GUI-only sessions (Advanced/ImGui) where process exit
	 *                     is expected and should not trigger the crash dialog.
	 */
	private fun launchSdlActivity(context: Context, args: Array<String>, trackSession: Boolean = true) {
		// Don't let a bundled tracker tune (boot intro / mod player) overlap the game's own audio.
		ModPlayer.stop()

		val hasRom = args.any { it.startsWith("kickstart_rom_file=") } ||
				args.contains("--config") ||
				args.contains("-s") && args.any { it.startsWith("kickstart_rom_file=") }

		android.util.Log.d("Uae4Arm-Launcher", "Launching emulator. trackSession=$trackSession, args: ${args.joinToString(" ")}")

		if (trackSession) {
			writeSessionMarker(context)
			writePendingLaunchMarker(context)
			(context as? com.uae4arm2026.ui.MainActivity)?.markEmulatorLaunched()
		}

		// Replace --rescan-roms with a no-op if ROM files haven't changed since last scan
		val filteredArgs = if (needsRomRescan(context)) {
			args
		} else {
			args.filter { it != "--rescan-roms" }.toTypedArray()
		}
		val finalArgs = buildManagedPathOverrides(context) + filteredArgs

		val intent = Intent(context, Uae4ArmEmulatorActivity::class.java)
		intent.putExtra("SDL_ARGS", finalArgs)
		context.startActivity(intent)
	}

	private fun buildManagedPathOverrides(context: Context): Array<String> {
		val appRoot = FileManager.getAppStoragePath(context)
		if (appRoot.isBlank()) return emptyArray()

		val overrides = linkedMapOf<String, String>()
		overrides["config_path"] = appRoot
		overrides["controllers_path"] = File(appRoot, "controllers").absolutePath
		overrides["whdboot_path"] = File(appRoot, "whdboot").absolutePath
		overrides["whdload_arch_path"] = FileManager.getEffectiveCategoryDir(context, FileCategory.WHDLOAD_GAMES).absolutePath
		overrides["floppy_path"] = FileManager.getEffectiveCategoryDir(context, FileCategory.FLOPPIES).absolutePath
		overrides["harddrive_path"] = FileManager.getEffectiveCategoryDir(context, FileCategory.HARD_DRIVES).absolutePath
		overrides["cdrom_path"] = FileManager.getEffectiveCategoryDir(context, FileCategory.CD_IMAGES).absolutePath
		overrides["rom_path"] = FileManager.getEffectiveCategoryDir(context, FileCategory.ROMS).absolutePath

		return overrides
			.filterValues { it.isNotBlank() }
			.flatMap { (key, value) -> listOf("-o", "$key=$value") }
			.toTypedArray()
	}

	/**
	 * Check if ROM files have changed since the last launch.
	 * Checks all directories that FileManager.scanForCategory(ROMS) scans:
	 * roms/, root app dir, and whdboot/game-data/Kickstarts/.
	 */
	private fun needsRomRescan(context: Context): Boolean {
		val prefs = AppPreferences.getInstance(context)
		val base = FileManager.getAppStoragePath(context)
		val category = FileCategory.ROMS
		val romExtensions = FileManager.getScannableExtensions(category)

		val fingerprints = mutableListOf<String>()

		// Local app-owned dirs
		val localDirs = listOf(
			FileManager.getCategoryDir(context, category),
			File(base),
			File(base, "whdboot/game-data/Kickstarts"),
			File(base, "whdboot/save-data/Kickstarts")
		)
		for (dir in localDirs) {
			fingerprints.add(computeDirFingerprint(dir, romExtensions))
		}

		// External SAF dir
		val uriString = FileManager.getCategoryLibraryUri(context, category)
		if (!uriString.isNullOrBlank()) {
			fingerprints.add(computeDocumentFingerprint(context, Uri.parse(uriString), romExtensions))
		}

		val currentFingerprint = fingerprints.joinToString("|")
		if (currentFingerprint == prefs.lastRomFingerprint) return false

		prefs.lastRomFingerprint = currentFingerprint
		return true
	}

	private fun computeDirFingerprint(dir: File, extensions: Set<String>): String {
		if (!dir.exists()) return "0:0:0"
		val romFiles = dir.listFiles { f ->
			f.isFile && f.extension.lowercase() in extensions
		} ?: return "0:0:0"
		val count = romFiles.size
		val totalSize = romFiles.sumOf { it.length() }
		val latestModified = romFiles.maxOfOrNull { it.lastModified() } ?: 0L
		return "$count:$totalSize:$latestModified"
	}

	private fun computeDocumentFingerprint(context: Context, treeUri: Uri, extensions: Set<String>): String {
		val resolver = context.contentResolver
		val childrenUri = android.provider.DocumentsContract.buildChildDocumentsUriUsingTree(
			treeUri,
			android.provider.DocumentsContract.getTreeDocumentId(treeUri)
		)

		val projection = arrayOf(
			android.provider.DocumentsContract.Document.COLUMN_DISPLAY_NAME,
			android.provider.DocumentsContract.Document.COLUMN_SIZE,
			android.provider.DocumentsContract.Document.COLUMN_LAST_MODIFIED
		)

		var count = 0
		var totalSize = 0L
		var latestModified = 0L

		try {
			resolver.query(childrenUri, projection, null, null, null)?.use { cursor ->
				val nameIndex = cursor.getColumnIndex(android.provider.DocumentsContract.Document.COLUMN_DISPLAY_NAME)
				val sizeIndex = cursor.getColumnIndex(android.provider.DocumentsContract.Document.COLUMN_SIZE)
				val modIndex = cursor.getColumnIndex(android.provider.DocumentsContract.Document.COLUMN_LAST_MODIFIED)

				while (cursor.moveToNext()) {
					val name = cursor.getString(nameIndex) ?: continue
					val ext = name.substringAfterLast('.', "").lowercase()
					if (ext in extensions) {
						count++
						totalSize += cursor.getLong(sizeIndex)
						val mod = cursor.getLong(modIndex)
						if (mod > latestModified) latestModified = mod
					}
				}
			}
		} catch (e: Exception) {
			android.util.Log.w("Uae4Arm-Launcher", "Fingerprint failed for $treeUri", e)
		}
		return "$count:$totalSize:$latestModified"
	}

	private fun writeSessionMarker(context: Context) {
		try {
			val marker = File(context.getExternalFilesDir(null), SESSION_MARKER)
			marker.writeText(System.currentTimeMillis().toString())
		} catch (_: Exception) {
			// Non-critical — crash detection is best-effort
		}
	}

	private fun writePendingLaunchMarker(context: Context) {
		try {
			File(context.getExternalFilesDir(null), PENDING_LAUNCH_MARKER).writeText(System.currentTimeMillis().toString())
		} catch (_: Exception) {
			// Best-effort
		}
	}

	/**
	 * Delete the session marker. Called by Uae4ArmEmulatorActivity on normal exit.
	 */
	fun clearSessionMarker(context: Context) {
		try {
			File(context.getExternalFilesDir(null), SESSION_MARKER).delete()
			File(context.getExternalFilesDir(null), PENDING_LAUNCH_MARKER).delete()
		} catch (_: Exception) {
			// Ignore
		}
	}

	/**
	 * Write a clean-exit marker so the main process knows this was a
	 * user-initiated quit (e.g., from the pause menu), not a crash.
	 * Called from the :sdl process before finish().
	 */
	fun writeCleanExitMarker(context: Context) {
		try {
			File(context.getExternalFilesDir(null), CLEAN_EXIT_MARKER).writeText("1")
		} catch (_: Exception) {
			// Best-effort
		}
	}

	/**
	 * Check and consume the clean-exit marker. Returns true if present
	 * (meaning the user quit intentionally).
	 */
	fun checkAndClearCleanExit(context: Context): Boolean {
		val marker = File(context.getExternalFilesDir(null), CLEAN_EXIT_MARKER)
		if (marker.exists()) {
			marker.delete()
			return true
		}
		return false
	}

	fun checkAndClearPendingLaunchMarker(context: Context): Boolean {
		val marker = File(context.getExternalFilesDir(null), PENDING_LAUNCH_MARKER)
		if (!marker.exists()) return false
		marker.delete()
		return true
	}

	/**
	 * Check if a previous emulator session crashed (marker file still present).
	 * Returns true if a crash was detected, and cleans up the marker.
	 *
	 * Includes a staleness check: if the marker is older than [STALE_MARKER_THRESHOLD_MS],
	 * it is silently discarded. This prevents false-positive crash dialogs when the system
	 * OOM-kills the :sdl process or the user force-stops the app from Android settings,
	 * since neither path triggers onDestroy(isFinishing=true).
	 */
	fun checkAndClearCrashMarker(context: Context): Boolean {
		val marker = File(context.getExternalFilesDir(null), SESSION_MARKER)
		if (!marker.exists()) return false

		val isCrash = try {
			val startTime = marker.readText().trim().toLongOrNull()
			if (startTime == null) {
				// Corrupt marker — treat as crash to be safe
				true
			} else {
				val elapsed = System.currentTimeMillis() - startTime
				elapsed in 1 until STALE_MARKER_THRESHOLD_MS
			}
		} catch (_: Exception) {
			// Unreadable marker (I/O error) — treat as crash to be safe
			true
		}

		marker.delete()
		return isCrash
	}

	/**
	 * Markers older than this are considered stale (force-stop / OOM) rather than crashes.
	 * 12 hours covers virtually all real emulator sessions.
	 */
	private const val STALE_MARKER_THRESHOLD_MS = 12 * 60 * 60 * 1000L
}

