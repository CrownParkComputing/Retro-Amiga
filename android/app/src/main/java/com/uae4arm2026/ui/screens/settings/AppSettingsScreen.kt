package com.uae4arm2026.ui.screens.settings

import android.os.Build
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Info
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.navigation.NavController
import com.uae4arm2026.R
import com.uae4arm2026.data.AppPreferences

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AppSettingsScreen(navController: NavController) {
	val context = LocalContext.current
	val appPrefs = AppPreferences.getInstance(context)
	
	val themeModeOptions = listOf(
		"system" to stringResource(R.string.settings_display_theme_system),
		"light" to stringResource(R.string.settings_display_theme_light),
		"dark" to stringResource(R.string.settings_display_theme_dark)
	)

	Scaffold(
		topBar = {
			TopAppBar(
				title = { Text("App Settings") },
				navigationIcon = {
					IconButton(onClick = { navController.popBackStack() }) {
						Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
					}
				}
			)
		}
	) { innerPadding ->
		Column(
			modifier = Modifier
				.fillMaxSize()
				.padding(innerPadding)
				.verticalScroll(rememberScrollState())
				.padding(16.dp),
			verticalArrangement = Arrangement.spacedBy(16.dp)
		) {
			SettingsSectionHeader("Appearance")
			OutlinedCard {
				Column(modifier = Modifier.padding(16.dp)) {
					val themeMode by appPrefs.themeMode
					SettingsRadioGroup(
						label = stringResource(R.string.settings_display_theme_label),
						options = themeModeOptions,
						selected = themeMode,
						onSelected = { appPrefs.setThemeMode(it) }
					)

					if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
						Spacer(modifier = Modifier.height(16.dp))
						val useDynamicColor by appPrefs.useDynamicColor
						SettingsSwitchRow(
							label = stringResource(R.string.settings_display_dynamic_color),
							checked = useDynamicColor,
							onCheckedChange = { appPrefs.setDynamicColor(it) }
						)
					}
				}
			}

			SettingsSectionHeader("About")
			OutlinedCard {
				Column(modifier = Modifier.padding(16.dp)) {
					ListItem(
						headlineContent = { Text("UAE4ARM 2026") },
						supportingContent = { Text("Powered by Amiberry") },
						leadingContent = { Icon(Icons.Default.Info, contentDescription = null) }
					)
				}
			}
		}
	}
}
