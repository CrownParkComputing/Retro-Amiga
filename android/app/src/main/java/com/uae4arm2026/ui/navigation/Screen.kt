package com.uae4arm2026.ui.navigation

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Download
import androidx.compose.material.icons.filled.Folder
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.Save
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.TravelExplore
import androidx.annotation.StringRes
import androidx.compose.ui.graphics.vector.ImageVector
import com.uae4arm2026.R

sealed class Screen(
	val route: String,
	@param:StringRes val titleRes: Int,
	val icon: ImageVector
) {
	data object QuickStart : Screen("quickstart", R.string.nav_home, Icons.Default.Home)
	data object Settings : Screen("settings", R.string.nav_settings, Icons.Default.Settings)
	data object AppSettings : Screen("app_settings", R.string.nav_settings, Icons.Default.Settings)
	data object FileManager : Screen("files", R.string.nav_files, Icons.Default.Folder)
	data object FileManagerDownloads : Screen("files/downloads", R.string.file_manager_section_downloads, Icons.Default.Download)
	data object Configurations : Screen("configs", R.string.nav_configs, Icons.Default.Save)
	// Not in bottom nav — shown only on first launch
	data object Onboarding : Screen("onboarding", R.string.nav_home, Icons.Default.TravelExplore)
	// Guided configuration wizards
	data object GuidedConfig : Screen("guided/{mode}", R.string.guided_config_title, Icons.Default.Add) {
		fun createRoute(mode: String) = "guided/$mode"
	}

	companion object {
		val bottomNavItems: List<Screen> by lazy {
			listOf<Screen?>(QuickStart, Settings, FileManager, FileManagerDownloads, Configurations)
				.filterNotNull()
		}
	}
}

