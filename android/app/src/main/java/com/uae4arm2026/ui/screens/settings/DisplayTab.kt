package com.uae4arm2026.ui.screens.settings

import android.os.Build
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ExposedDropdownMenuAnchorType
import androidx.compose.material3.ExposedDropdownMenuBox
import androidx.compose.material3.ExposedDropdownMenuDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedCard
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.uae4arm2026.R
import com.uae4arm2026.data.AppPreferences
import com.uae4arm2026.ui.viewmodel.SettingsViewModel

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun DisplayTab(viewModel: SettingsViewModel) {
	val settings = viewModel.settings
	val amigaResolutionPresets = listOf(
		Triple(640, 256, stringResource(R.string.settings_display_resolution_pal_low)),
		Triple(640, 512, stringResource(R.string.settings_display_resolution_pal_high)),
		Triple(720, 568, stringResource(R.string.settings_display_resolution_default)),
		Triple(800, 600, stringResource(R.string.settings_display_resolution_800_600)),
		Triple(1024, 768, stringResource(R.string.settings_display_resolution_1024_768))
	)
	val rtgResolutionPresets = listOf(
		Triple(1280, 720, stringResource(R.string.settings_display_resolution_1280_720)),
		Triple(1600, 900, stringResource(R.string.settings_display_resolution_1600_900)),
		Triple(1920, 720, stringResource(R.string.settings_display_resolution_1920_720)),
		Triple(1920, 1080, stringResource(R.string.settings_display_resolution_1920_1080))
	)
	val context = LocalContext.current
	val appPrefs = AppPreferences.getInstance(context)

	SettingsTabContent {
		SettingsAdaptiveColumns(
			left = {
				OutlinedCard(modifier = Modifier.fillMaxWidth()) {
					Column(modifier = Modifier.padding(16.dp)) {
						Text(stringResource(R.string.settings_display_title), style = MaterialTheme.typography.titleMedium)
						Spacer(modifier = Modifier.height(8.dp))

						var amigaResExpanded by remember { mutableStateOf(false) }
						val currentAmigaRes = "${settings.gfxWidth}x${settings.gfxHeight}"
						val currentAmigaLabel = amigaResolutionPresets.firstOrNull {
							it.first == settings.gfxWidth && it.second == settings.gfxHeight
						}?.third ?: currentAmigaRes

						ExposedDropdownMenuBox(
							expanded = amigaResExpanded,
							onExpandedChange = { amigaResExpanded = it }
						) {
							OutlinedTextField(
								value = currentAmigaLabel,
								onValueChange = {},
								readOnly = true,
								label = { Text(stringResource(R.string.settings_display_amiga_resolution_label)) },
								trailingIcon = { ExposedDropdownMenuDefaults.TrailingIcon(expanded = amigaResExpanded) },
								modifier = Modifier
									.menuAnchor(ExposedDropdownMenuAnchorType.PrimaryNotEditable)
									.fillMaxWidth()
							)
							ExposedDropdownMenu(
								expanded = amigaResExpanded,
								onDismissRequest = { amigaResExpanded = false }
							) {
								amigaResolutionPresets.forEach { (width, height, label) ->
									DropdownMenuItem(
										text = { Text(label) },
										onClick = {
											viewModel.updateSettings { state ->
												state.copy(gfxWidth = width, gfxHeight = height)
											}
											amigaResExpanded = false
										}
									)
								}
							}
						}

						Spacer(modifier = Modifier.height(8.dp))
						SettingsSwitchRow(
							label = stringResource(R.string.settings_display_correct_aspect_ratio),
							checked = settings.correctAspect,
							onCheckedChange = {
								viewModel.updateSettings { state -> state.copy(correctAspect = it) }
							}
						)
						SettingsSwitchRow(
							label = stringResource(R.string.settings_display_auto_crop),
							checked = settings.autoCrop,
							onCheckedChange = {
								viewModel.updateSettings { state -> state.copy(autoCrop = it) }
							}
						)
						Spacer(modifier = Modifier.height(8.dp))
						SettingsSwitchRow(
							label = stringResource(R.string.settings_display_rtg_label),
							checked = settings.useRtg,
							enabled = !settings.address24Bit && settings.cpuModel >= 68020,
							onCheckedChange = {
								viewModel.updateSettings { state -> state.copy(useRtg = it) }
							}
						)
						if (settings.useRtg) {
							Spacer(modifier = Modifier.height(8.dp))
							var rtgResExpanded by remember { mutableStateOf(false) }
							val currentRtgRes = "${settings.rtgWidth}x${settings.rtgHeight}"
							val currentRtgLabel = rtgResolutionPresets.firstOrNull {
								it.first == settings.rtgWidth && it.second == settings.rtgHeight
							}?.third ?: currentRtgRes

							ExposedDropdownMenuBox(
								expanded = rtgResExpanded,
								onExpandedChange = { rtgResExpanded = it }
							) {
								OutlinedTextField(
									value = currentRtgLabel,
									onValueChange = {},
									readOnly = true,
									label = { Text(stringResource(R.string.settings_display_rtg_resolution_label)) },
									trailingIcon = { ExposedDropdownMenuDefaults.TrailingIcon(expanded = rtgResExpanded) },
									modifier = Modifier
										.menuAnchor(ExposedDropdownMenuAnchorType.PrimaryNotEditable)
										.fillMaxWidth()
								)
								ExposedDropdownMenu(
									expanded = rtgResExpanded,
									onDismissRequest = { rtgResExpanded = false }
								) {
									rtgResolutionPresets.forEach { (width, height, label) ->
										DropdownMenuItem(
											text = { Text(label) },
											onClick = {
												viewModel.updateSettings { state ->
													state.copy(rtgWidth = width, rtgHeight = height)
												}
												rtgResExpanded = false
											}
										)
									}
								}
							}
						}
						SettingsSwitchRow(
							label = stringResource(R.string.settings_display_show_leds),
							checked = settings.showLeds,
							onCheckedChange = {
								viewModel.updateSettings { state -> state.copy(showLeds = it) }
							}
						)
					}
				}
			},
			right = {
				OutlinedCard(modifier = Modifier.fillMaxWidth()) {
					Column(modifier = Modifier.padding(16.dp)) {
						Text(stringResource(R.string.settings_display_app_theme), style = MaterialTheme.typography.titleMedium)
						Spacer(modifier = Modifier.height(8.dp))

						val themeMode by appPrefs.themeMode
						val themeModeOptions = listOf(
							"system" to stringResource(R.string.settings_display_theme_system),
							"light" to stringResource(R.string.settings_display_theme_light),
							"dark" to stringResource(R.string.settings_display_theme_dark)
						)
						var themeExpanded by remember { mutableStateOf(false) }

						ExposedDropdownMenuBox(
							expanded = themeExpanded,
							onExpandedChange = { themeExpanded = it }
						) {
							OutlinedTextField(
								value = themeModeOptions.firstOrNull { it.first == themeMode }?.second ?: themeMode,
								onValueChange = {},
								readOnly = true,
								label = { Text(stringResource(R.string.settings_display_theme_label)) },
								trailingIcon = { ExposedDropdownMenuDefaults.TrailingIcon(expanded = themeExpanded) },
								modifier = Modifier
									.menuAnchor(ExposedDropdownMenuAnchorType.PrimaryNotEditable)
									.fillMaxWidth()
							)
							ExposedDropdownMenu(
								expanded = themeExpanded,
								onDismissRequest = { themeExpanded = false }
							) {
								themeModeOptions.forEach { (value, label) ->
									DropdownMenuItem(
										text = { Text(label) },
										onClick = {
											appPrefs.setThemeMode(value)
											themeExpanded = false
										}
									)
								}
							}
						}

						if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
							Spacer(modifier = Modifier.height(8.dp))
							val useDynamicColor by appPrefs.useDynamicColor
							SettingsSwitchRow(
								label = stringResource(R.string.settings_display_dynamic_color),
								checked = useDynamicColor,
								onCheckedChange = { appPrefs.setDynamicColor(it) }
							)
						}
					}
				}
			}
		)
	}
}
