package com.uae4arm2026.ui

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
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.navigation.NavHostController
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.rememberNavController
import com.uae4arm2026.R
import com.uae4arm2026.data.FileManager
import com.uae4arm2026.data.model.FileCategory
import com.uae4arm2026.ui.navigation.Screen
import com.uae4arm2026.ui.screens.ConfigurationsScreen
import com.uae4arm2026.ui.screens.FileManagerScreen
import com.uae4arm2026.ui.screens.OnboardingScreen
import com.uae4arm2026.ui.screens.Uae4ArmHomeScreen
import com.uae4arm2026.ui.screens.GuidedConfigScreen
import com.uae4arm2026.ui.screens.settings.AppSettingsScreen
import com.uae4arm2026.ui.screens.settings.SettingsScreen

@Composable
fun Uae4ArmApp() {
	val navController = rememberNavController()
	val activity = LocalContext.current.findActivity() as? MainActivity

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

	Uae4ArmNavHost(navController, Modifier.fillMaxSize())
}

@Composable
private fun Uae4ArmNavHost(navController: NavHostController, modifier: Modifier = Modifier) {
	val context = LocalContext.current
	val startDestination = remember {
		val hasAllLibraries = FileCategory.entries.all {
			FileManager.getCategoryLibraryPath(context, it) != null
		}
		if (hasAllLibraries) Screen.QuickStart.route else Screen.Onboarding.route
	}

	NavHost(
		navController = navController,
		startDestination = startDestination,
		modifier = modifier
			.fillMaxSize()
			.focusGroup()
	) {
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
		composable(Screen.GuidedConfig.route) { backStackEntry ->
			val mode = backStackEntry.arguments?.getString("mode") ?: "adf"
			GuidedConfigScreen(mode = mode, navController = navController)
		}
	}
}
