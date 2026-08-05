package com.uae4arm2026.ui

import android.content.Intent
import android.os.SystemClock
import android.widget.Toast
import androidx.activity.compose.BackHandler
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.setValue
import androidx.navigation.compose.currentBackStackEntryAsState
import androidx.compose.foundation.focusGroup
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.navigation.NavHostController
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.rememberNavController
import android.util.Log
import com.uae4arm2026.R
import com.uae4arm2026.Uae4ArmEmulatorActivity
import com.uae4arm2026.data.ConfigRepository
import com.uae4arm2026.data.FileManager
import com.uae4arm2026.data.model.FileCategory
import com.uae4arm2026.ui.viewmodel.SettingsViewModel
import java.io.File
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import com.uae4arm2026.ui.navigation.Screen
import com.uae4arm2026.ui.screens.ConfigurationsScreen
import com.uae4arm2026.ui.screens.FileManagerScreen
import com.uae4arm2026.ui.screens.OnboardingScreen
import com.uae4arm2026.ui.screens.Uae4ArmHomeScreen
import com.uae4arm2026.ui.screens.GuidedConfigScreen
import com.uae4arm2026.ui.screens.IntroScreen
import com.uae4arm2026.ui.screens.ModPlayerScreen
import com.uae4arm2026.ui.screens.settings.AppSettingsScreen
import com.uae4arm2026.ui.screens.settings.SettingsScreen

@Composable
fun Uae4ArmApp() {
	val navController = rememberNavController()
	val appContext = LocalContext.current
	val activity = appContext.findActivity() as? MainActivity

	// A game left running in the background (e.g. via the in-game "Edit Config" detour - see
	// Uae4ArmEmulatorActivity.openEditConfig()) should always be one back-press away, from
	// anywhere in the app - not several taps through Settings/Configurations/QuickStart. Handles
	// hardware/gesture back for every screen; on-screen back arrows are handled per-screen.
	BackHandler(enabled = Uae4ArmEmulatorActivity.isRunning) {
		val intent = Intent(appContext, Uae4ArmEmulatorActivity::class.java)
		intent.addFlags(Intent.FLAG_ACTIVITY_REORDER_TO_FRONT)
		appContext.startActivity(intent)
	}

	// On a handheld, a gamepad's B button IS the system back key, so a stray press at the root
	// screen would drop straight out to the device launcher mid-browse. Guard the root with a
	// deliberate double-press (any other screen still backs normally via the nav stack).
	// Read the current entry as state so "am I at the root?" is re-evaluated on every navigation
	// (previousBackStackEntry on its own isn't a Compose state read).
	val backStackEntry by navController.currentBackStackEntryAsState()
	val atRootScreen = backStackEntry != null && navController.previousBackStackEntry == null
	var backArmedAt by remember { mutableLongStateOf(0L) }
	val pressAgainToExit = stringResource(R.string.press_back_again_to_exit)
	BackHandler(enabled = !Uae4ArmEmulatorActivity.isRunning && atRootScreen) {
		val now = SystemClock.elapsedRealtime()
		if (now - backArmedAt < 2000L) {
			activity?.finish()
		} else {
			backArmedAt = now
			Toast.makeText(appContext, pressAgainToExit, Toast.LENGTH_SHORT).show()
		}
	}

	if (activity?.emulatorCrashDetected == true) {
		AlertDialog(
			onDismissRequest = { activity.clearCrashFlag() },
			title = { Text(stringResource(R.string.crash_dialog_title)) },
			text = { Text(stringResource(R.string.crash_dialog_message)) },
			confirmButton = {
				TextButton(onClick = { activity.clearCrashFlag() }) {
					Text(stringResource(R.string.crash_dialog_dismiss))
				}
			}
		)
	}

	if (activity?.assetExtractionFailed == true) {
		AlertDialog(
			onDismissRequest = {},
			title = { Text(stringResource(R.string.asset_extraction_failed_title)) },
			text = { Text(stringResource(R.string.asset_extraction_failed_message)) },
			confirmButton = {
				TextButton(onClick = { activity.retryAssetExtraction() }) {
					Text(stringResource(R.string.action_retry))
				}
			}
		)
	}

	val pendingUri = activity?.pendingFileUri
	LaunchedEffect(pendingUri) {
		if (pendingUri != null) {
			activity.clearPendingFileUri()
			activity.importAndLaunch(pendingUri)
		}
	}

	val requestedRoute = activity?.consumeRequestedRoute()
	LaunchedEffect(requestedRoute) {
		if (!requestedRoute.isNullOrBlank()) {
			navController.navigate(requestedRoute) {
				launchSingleTop = true
			}
		}
	}

	// Load the current running config into the settings view-model when the
	// emulator pause menu requests "Edit Configuration", then open the wizard.
	//
	// IMPORTANT: read the path here WITHOUT consuming/clearing it. consumePendingEditConfigPath()
	// clears MainActivity's backing state as a side effect, and calling it directly in the
	// composable body means the very next recomposition (triggered by anything unrelated - a
	// dialog state flip, the ViewModel being created, etc.) sees a now-null value and changes
	// this LaunchedEffect's key out from under the in-flight IO + navigation, cancelling it
	// (surfaced as LeftCompositionCancellationException). Keep the key stable by reading the
	// property plainly, and only clear it once the load actually succeeds.
	val context = LocalContext.current
	val pendingEditConfigPath = activity?.pendingEditConfigPath
	val settingsViewModel: SettingsViewModel? = activity?.let { viewModel<SettingsViewModel>(it) }
	LaunchedEffect(pendingEditConfigPath) {
		if (!pendingEditConfigPath.isNullOrBlank() && settingsViewModel != null) {
			try {
				val parsed = withContext(Dispatchers.IO) {
					ConfigRepository.getInstance(context).loadConfig(pendingEditConfigPath)
				}
				val name = File(pendingEditConfigPath).nameWithoutExtension
				settingsViewModel.loadConfig(parsed, name)
				activity.consumePendingEditConfigPath()
				navController.navigate(Screen.GuidedConfig.createRoute("edit")) {
					launchSingleTop = true
					popUpTo(Screen.Configurations.route) { inclusive = false }
				}
			} catch (e: Exception) {
				Log.e("Uae4Arm-App", "Failed to load edit config: $pendingEditConfigPath", e)
			}
		}
	}

	Uae4ArmNavHost(navController, Modifier.fillMaxSize())
}

// Process-lifetime flag: the boot intro should play once per cold start, not every time a new
// MainActivity instance is created within the same process (e.g. the "edit config" detour from
// a running game creates a fresh MainActivity - replaying the intro there would be jarring).
private var introHasPlayed = false

@Composable
private fun Uae4ArmNavHost(navController: NavHostController, modifier: Modifier = Modifier) {
	val context = LocalContext.current
	val postIntroDestination = remember {
		val hasAllLibraries = FileCategory.entries.all {
			FileManager.getCategoryLibraryPath(context, it) != null
		}
		if (hasAllLibraries) Screen.Configurations.route else Screen.Onboarding.route
	}
	val startDestination = if (introHasPlayed) postIntroDestination else Screen.Intro.route

	NavHost(
		navController = navController,
		startDestination = startDestination,
		modifier = modifier
			.fillMaxSize()
			.focusGroup()
	) {
		composable(Screen.Intro.route) {
			IntroScreen(navController = navController) {
				introHasPlayed = true
				navController.navigate(postIntroDestination) {
					popUpTo(Screen.Intro.route) { inclusive = true }
				}
			}
		}
		composable(Screen.Onboarding.route) {
			OnboardingScreen(navController = navController)
		}
		composable(Screen.QuickStart.route) {
			Uae4ArmHomeScreen(navController = navController)
		}
		composable(Screen.Settings.route) {
			SettingsScreen(navController = navController)
		}
		composable(Screen.AppSettings.route) {
			AppSettingsScreen(navController = navController)
		}
		composable(Screen.FileManager.route) {
			FileManagerScreen(navController = navController)
		}
		composable(Screen.FileManagerDownloads.route) {
			FileManagerScreen(initialSection = 1, showSectionTabs = false, showTopBar = false, navController = navController)
		}
		composable(Screen.Configurations.route) {
			ConfigurationsScreen(navController = navController)
		}
		composable(Screen.ModPlayer.route) {
			ModPlayerScreen(navController = navController)
		}
		composable(Screen.GuidedConfig.route) { backStackEntry ->
			val mode = backStackEntry.arguments?.getString("mode") ?: "adf"
			GuidedConfigScreen(mode = mode, navController = navController)
		}
	}
}
