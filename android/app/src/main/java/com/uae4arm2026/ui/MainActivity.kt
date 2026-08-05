package com.uae4arm2026.ui

import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Bundle
import android.util.Log
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.core.splashscreen.SplashScreen.Companion.installSplashScreen
import androidx.lifecycle.lifecycleScope
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.uae4arm2026.data.AppPreferences
import com.uae4arm2026.data.EmulatorLauncher
import com.uae4arm2026.data.FileManager
import com.uae4arm2026.data.model.EmulatorSettings
import com.uae4arm2026.data.model.FileCategory
import com.uae4arm2026.ui.theme.Uae4ArmTheme
import com.google.android.play.core.review.ReviewManagerFactory
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File
import java.io.IOException

class MainActivity : ComponentActivity() {
	private var requestedRoute by mutableStateOf<String?>(null)
	var pendingEditConfigPath by mutableStateOf<String?>(null)
		private set

	private var isReady by mutableStateOf(false)
	var emulatorCrashDetected by mutableStateOf(false)
		private set
	var assetExtractionFailed by mutableStateOf(false)
		private set

	override fun onCreate(savedInstanceState: Bundle?) {
		val splashScreen = installSplashScreen()
		super.onCreate(savedInstanceState)
		enableEdgeToEdge()

		// Keep the splash screen visible while assets are being extracted
		splashScreen.setKeepOnScreenCondition { !isReady }

		setContent {
			Uae4ArmTheme {
				Uae4ArmApp()
			}
		}

		// Storage access is handled through SAF (Storage Access Framework) — no
		// runtime permission is requested at startup. File picking uses
		// ACTION_OPEN_DOCUMENT and ACTION_OPEN_DOCUMENT_TREE.
		startAssetExtraction()

		handleIncomingIntent(intent)
	}

	override fun onNewIntent(intent: Intent) {
		super.onNewIntent(intent)
		handleIncomingIntent(intent)
	}

	/**
	 * Handle ACTION_VIEW intents from file managers.
	 * Imports the file into app storage, then launches the emulator with it.
	 */
	private fun handleIncomingIntent(intent: Intent?) {
		intent?.getStringExtra(EXTRA_OPEN_ROUTE)?.let { route ->
			requestedRoute = route
			intent.removeExtra(EXTRA_OPEN_ROUTE)
		}

		intent?.getStringExtra(EXTRA_CONFIG_PATH)?.let { path ->
			pendingEditConfigPath = path
			intent.removeExtra(EXTRA_CONFIG_PATH)
		}

		if (intent?.action != Intent.ACTION_VIEW) return
		val uri = intent.data ?: return
		// Clear the action so it isn't re-processed on config change
		intent.action = null

		pendingFileUri = uri
	}

	/** URI from an incoming ACTION_VIEW intent, processed after asset extraction. */
	var pendingFileUri by mutableStateOf<Uri?>(null)
		private set

	fun clearPendingFileUri() {
		pendingFileUri = null
	}

	fun consumeRequestedRoute(): String? {
		val route = requestedRoute
		requestedRoute = null
		return route
	}

	fun consumePendingEditConfigPath(): String? {
		val path = pendingEditConfigPath
		pendingEditConfigPath = null
		return path
	}

	/**
	 * Import a file from a content/file URI and launch emulation with it.
	 */
	fun importAndLaunch(uri: Uri) {
		lifecycleScope.launch(Dispatchers.IO) {
			val fileName = FileManager.getDisplayName(this@MainActivity, uri) ?: uri.lastPathSegment ?: ""
			val ext = fileName.substringAfterLast('.', "").lowercase()
			val category = FileCategory.fromExtension(ext)

			if (ext == "uae") {
				// Config file: copy to conf dir and launch with it
				val confDir = File(getExternalFilesDir(null), "conf")
				if (!confDir.exists()) confDir.mkdirs()
				val targetFile = File(confDir, fileName)
				try {
					contentResolver.openInputStream(uri)?.use { input ->
						targetFile.outputStream().use { output -> input.copyTo(output) }
					}
					withContext(Dispatchers.Main) {
						EmulatorLauncher.launchWithConfig(this@MainActivity, targetFile.absolutePath)
					}
				} catch (e: Exception) {
					Log.e(TAG, "Failed to import config from intent", e)
				}
			} else if (category != null) {
				val importedPath = FileManager.importFile(this@MainActivity, uri, category)
				if (importedPath != null) {
					withContext(Dispatchers.Main) {
						when (category) {
							FileCategory.WHDLOAD_GAMES ->
								EmulatorLauncher.launchWhdload(this@MainActivity, importedPath, EmulatorSettings())
							FileCategory.FLOPPIES ->
								EmulatorLauncher.launchQuickStart(this@MainActivity,
com.uae4arm2026.data.model.AmigaModel.A500,
									floppyPath = importedPath)
							FileCategory.CD_IMAGES ->
								EmulatorLauncher.launchQuickStart(this@MainActivity,
com.uae4arm2026.data.model.AmigaModel.CD32,
									cdPath = importedPath)
							else -> {
								// ROMs and hard drives: just import, don't auto-launch
							}
						}
					}
				}
			} else {
				Log.w(TAG, "Ignoring unsupported file from intent: $fileName")
			}
		}
	}

	private fun startAssetExtraction() {
		lifecycleScope.launch(Dispatchers.IO) {
			val success = extractAssetsIfNeeded()
			ensureDirectories()
			withContext(Dispatchers.Main) {
				assetExtractionFailed = !success
				isReady = true
			}
		}
	}

	fun retryAssetExtraction() {
		assetExtractionFailed = false
		isReady = false
		startAssetExtraction()
	}

	/**
	 * @return true if assets are ready (already extracted or freshly extracted),
	 *         false if extraction failed.
	 */
	private fun extractAssetsIfNeeded(): Boolean {
		val externalDir = getExternalFilesDir(null)
		if (externalDir == null) {
			Log.e(TAG, "External files directory is unavailable")
			return false
		}
		val versionFile = File(externalDir, ".extracted_version")
		val currentVersion = try {
			if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.TIRAMISU) {
				packageManager.getPackageInfo(packageName, PackageManager.PackageInfoFlags.of(0)).versionName
			} else {
				@Suppress("DEPRECATION")
				packageManager.getPackageInfo(packageName, 0).versionName
			}
		} catch (e: PackageManager.NameNotFoundException) {
			"unknown"
		}

		if (versionFile.exists() && versionFile.readText().trim() == currentVersion) {
			Log.d(TAG, "Assets already extracted for version $currentVersion, skipping")
			return true
		}

		Log.d(TAG, "Extracting assets for version $currentVersion...")
		return try {
			copyAssets()
			versionFile.writeText(currentVersion ?: "unknown")
			Log.d(TAG, "Asset extraction complete")
			true
		} catch (e: Exception) {
			Log.e(TAG, "Asset extraction failed", e)
			false
		}
	}

	private fun copyAssets() {
		val assetManager = assets
		val files = try {
			assetManager.list("") ?: return
		} catch (e: IOException) {
			Log.e(TAG, "Failed to get asset file list", e)
			return
		}

		val skipDirs = setOf("images", "sounds", "webkit", "kioskmode")
		for (filename in files) {
			if (filename in skipDirs || filename.startsWith("_")) continue
			copyAssetFileOrDir(filename, "")
		}
	}

	private fun copyAssetFileOrDir(filename: String, parentPath: String) {
		val assetManager = assets
		val fullAssetPath = if (parentPath.isNotEmpty()) "$parentPath/$filename" else filename

		val children = try {
			assetManager.list(fullAssetPath)
		} catch (e: IOException) {
			null
		}

		if (children != null && children.isNotEmpty()) {
			// Directory: create and recurse
			val targetDir = File(getExternalFilesDir(null), fullAssetPath)
			if (!targetDir.exists()) targetDir.mkdirs()
			for (child in children) {
				copyAssetFileOrDir(child, fullAssetPath)
			}
		} else {
			// File: copy it
			copyAssetFile(fullAssetPath)
		}
	}

	/**
	 * Directories containing user-modifiable files that should not be overwritten
	 * on version upgrades (users may have customized controller mappings, WHDLoad configs, etc.)
	 */
	private val userModifiableDirs = setOf("controllers", "whdboot", "conf")

	private fun copyAssetFile(assetPath: String) {
		try {
			val outFile = File(getExternalFilesDir(null), assetPath)

			// Skip overwriting files in user-modifiable directories if they already exist,
			// EXCEPT for critical system files that must always be up-to-date.
			val criticalFiles = setOf("whdboot/boot-data.zip", "whdboot/WHDLoad", "whdboot/AmiQuit", "whdboot/JST")
			
			if (outFile.exists() && assetPath !in criticalFiles) {
				val topDir = assetPath.substringBefore('/')
				if (topDir in userModifiableDirs) {
					Log.d(TAG, "Preserving user-modified file: $assetPath")
					return
				}
			}

			outFile.parentFile?.let { parent ->
				if (!parent.exists()) parent.mkdirs()
			}

			assets.open(assetPath).use { input ->
				outFile.outputStream().use { output ->
					input.copyTo(output)
				}
			}
		} catch (e: IOException) {
			Log.e(TAG, "Failed to copy asset: $assetPath", e)
		}
	}

	/**
	 * Ensure user-facing subdirectories exist for file organization.
	 */
	private fun ensureDirectories() {
		val base = getExternalFilesDir(null) ?: return
		listOf("roms", "floppies", "harddrives", "cdroms", "lha", "conf").forEach { dir ->
			File(base, dir).let { if (!it.exists()) it.mkdirs() }
		}
	}

	/** Tracks whether the emulator was running so we can distinguish
	 *  "returning from emulation" vs normal activity resume. */
	private var emulatorWasLaunched = false

	override fun onResume() {
		super.onResume()
		if (!isReady) return
		val hadPendingLaunch = EmulatorLauncher.checkAndClearPendingLaunchMarker(this)

		// Check for user-initiated quit (pause menu → Quit to Launcher)
		// before checking for crashes. Clean exit takes priority.
		val wasCleanExit = EmulatorLauncher.checkAndClearCleanExit(this)

		if (wasCleanExit) {
			// User quit intentionally — clear any leftover session marker, no crash dialog
			EmulatorLauncher.clearSessionMarker(this)
			emulatorWasLaunched = false
		} else if (hadPendingLaunch && EmulatorLauncher.checkAndClearCrashMarker(this)) {
			emulatorCrashDetected = true
			emulatorWasLaunched = false
		} else if (hadPendingLaunch || emulatorWasLaunched) {
			// Successful emulator session — check if we should request a review
			emulatorWasLaunched = false
			if (AppPreferences.getInstance(this).incrementLaunchCountAndCheckReview()) {
				requestInAppReview()
			}
		}
	}

	/** Called by EmulatorLauncher before starting the SDL activity. */
	fun markEmulatorLaunched() {
		emulatorWasLaunched = true
	}

	private fun requestInAppReview() {
		val manager = ReviewManagerFactory.create(this)
		manager.requestReviewFlow().addOnSuccessListener { reviewInfo ->
			manager.launchReviewFlow(this, reviewInfo)
			// No success/failure handling needed — Google controls the UI
		}
	}

	fun clearCrashFlag() {
		emulatorCrashDetected = false
	}

	companion object {
		private const val TAG = "Uae4Arm-Main"
		const val EXTRA_OPEN_ROUTE = "com.uae4arm2026.OPEN_ROUTE"
		const val EXTRA_CONFIG_PATH = "com.uae4arm2026.CONFIG_PATH"
	}
}

